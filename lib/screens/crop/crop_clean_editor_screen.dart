import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/scan_session.dart';
import '../../services/document_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pipeline.dart';
import '../../widgets/dialogs.dart';

const List<double> _fullFrame = [0, 0, 1, 0, 1, 1, 0, 1];

/// Edit state for one page of the batch.
class _PageEdit {
  _PageEdit(this.file);

  final File file;
  Uint8List? previewBytes;
  Uint8List? workBytes; // smaller copy for live previews
  Uint8List? filteredBytes; // previewBytes with the current filter applied
  Uint8List? resultBytes; // cropped + filtered, what Save will produce
  double resultRatio = 3 / 4;
  int renderGen = 0;
  double ratio = 3 / 4;
  String? error;

  /// Corners found by edge detection (null = none found).
  List<double>? detected;
  final List<double> corners = List.of(_fullFrame); // tl, tr, br, bl
  bool autoDeskew = true;
  int filter = 0;
  double shadow = 0.0;
  double contrast = 0.0;
  int rotateQuads = 0;
  final List<List<double>> strokes = []; // normalized to the source frame
  bool dirty = false;

  bool get loaded => previewBytes != null || error != null;

  bool get hasTone => shadow > 0.01 || contrast > 0.01 || (filter != 0 && filter != 5);

  void resetCorners() {
    corners.setAll(0, detected ?? _fullFrame);
  }
}

class CropCleanEditorScreen extends StatefulWidget {
  const CropCleanEditorScreen({super.key});

  @override
  State<CropCleanEditorScreen> createState() => _CropCleanEditorScreenState();
}

class _CropCleanEditorScreenState extends State<CropCleanEditorScreen> {
  final ScanSession _session = ScanSession.instance;
  final List<_PageEdit> _edits = [];
  int _index = 0;

  // Corner dragging: updates repaint through notifiers instead of rebuilding
  // the whole screen on every pointer move.
  int? _dragIndex;
  int? _pendingCorner;
  Offset _grabOffset = Offset.zero;
  final ValueNotifier<int> _cornerTick = ValueNotifier(0);
  final ValueNotifier<Offset?> _loupe = ValueNotifier(null);

  bool _showResult = false;
  Timer? _renderDebounce;

  bool _busy = false;
  String _busyLabel = '';

  // Which filter chips map to pipeline indices
  static const List<String> _filterNames = [
    'Original',
    'Magic Color',
    'Clean White',
    'Sharp B&W',
    'Grayscale',
    'Finger Eraser',
  ];
  static const List<IconData> _filterIcons = [
    Icons.image_outlined,
    Icons.auto_fix_high,
    Icons.cleaning_services,
    Icons.contrast,
    Icons.filter_b_and_w,
    Icons.pan_tool,
  ];
  // Filter chips index -> pipeline filter mode index
  static const List<int> _pipelineFilterOfChip = [
    FilterMode.original,
    FilterMode.magicColor,
    FilterMode.cleanWhite,
    FilterMode.sharpBW,
    FilterMode.grayscale,
  ];

  _PageEdit? get _page => _edits.isEmpty ? null : _edits[_index];

  RenderBox? get _canvasBox =>
      _canvasBoxKey.currentContext?.findRenderObject() as RenderBox?;

  final GlobalKey _canvasBoxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_session.pageCount == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    for (final f in _session.pages) {
      _edits.add(_PageEdit(f));
    }
    // Start on the newest page; load every preview in the background.
    _index = _edits.length - 1;
    _loadAll();
  }

  @override
  void dispose() {
    _renderDebounce?.cancel();
    _cornerTick.dispose();
    _loupe.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    // Current page first so the canvas fills quickly.
    final order = [_index, for (var i = 0; i < _edits.length; i++) if (i != _index) i];
    for (final i in order) {
      if (!mounted) return;
      await _loadPreview(_edits[i]);
    }
  }

  Future<void> _loadPreview(_PageEdit edit) async {
    try {
      final bytes = await edit.file.readAsBytes();
      final result = await compute(loadPreviewIsolate, bytes);
      if (!mounted) return;
      setState(() {
        edit.previewBytes = result['preview'] as Uint8List;
        edit.workBytes = result['work'] as Uint8List;
        // Match canvas aspect to the actual page so crop UVs map 1:1.
        edit.ratio = result['ratio'] as double;
        edit.detected = (result['corners'] as List<double>?);
        edit.resetCorners();
        // A detected outline means the page needs cropping even if untouched.
        edit.dirty = edit.detected != null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => edit.error = 'Could not open this image ($e)');
    }
  }

  // ------------------------------------------------------------------
  // Live previews
  // ------------------------------------------------------------------

  int _pipelineFilter(_PageEdit p) =>
      p.filter == 5 ? FilterMode.original : _pipelineFilterOfChip[p.filter];

  void _scheduleRender({bool immediate = false}) {
    _renderDebounce?.cancel();
    _renderDebounce = Timer(Duration(milliseconds: immediate ? 0 : 250), _render);
  }

  /// Re-renders the filtered canvas image and, in result mode, the cropped
  /// output for the current page. Stale renders are dropped.
  Future<void> _render() async {
    final p = _page;
    final work = p?.workBytes;
    if (p == null || work == null || !mounted) return;
    final gen = ++p.renderGen;
    try {
      if (p.hasTone) {
        final bytes = await compute(filterPreviewIsolate, {
          'bytes': work,
          'filter': _pipelineFilter(p),
          'shadow': p.shadow,
          'contrast': p.contrast,
        });
        if (!mounted || gen != p.renderGen) return;
        setState(() => p.filteredBytes = bytes);
      } else if (p.filteredBytes != null) {
        setState(() => p.filteredBytes = null);
      }
      if (_showResult) {
        final req = PipelineRequest(
          srcPathAsBytes: work,
          corners: List.of(p.corners),
          shadowRemoval: p.shadow,
          contrast: p.contrast,
          filterIndex: _pipelineFilter(p),
          strokes: [for (final s in p.strokes) List.of(s)],
          deskew: p.autoDeskew,
          rotateQuads: p.rotateQuads,
          maxOutDim: 900,
        );
        final r = await compute(resultPreviewIsolate, req.toMap());
        if (!mounted || gen != p.renderGen) return;
        setState(() {
          p.resultBytes = r['bytes'] as Uint8List;
          p.resultRatio = r['ratio'] as double;
        });
      }
    } catch (e) {
      debugPrint('ScanCraft: preview render failed: $e');
    }
  }

  void _setResultMode(bool value) {
    if (value == _showResult) return;
    setState(() {
      _showResult = value;
      if (value) _page?.resultBytes = null;
    });
    if (value) _scheduleRender(immediate: true);
  }

  bool get _eraserMode => _page?.filter == 5;

  void _markDirty(void Function(_PageEdit p) change) {
    final p = _page;
    if (p == null) return;
    setState(() {
      change(p);
      p.dirty = true;
    });
    _cornerTick.value++;
    _scheduleRender();
  }

  void _onCanvasTap(TapUpDetails d) {
    if (!_eraserMode) return;
    final rb = _canvasBox;
    if (rb == null) return;
    final size = rb.size;
    final local = rb.globalToLocal(d.globalPosition);
    final u = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (local.dy / size.height).clamp(0.0, 1.0);
    _markDirty((p) => p.strokes.add([u, v, 0.035]));
  }

  /// Decides at pointer-down whether a touch grabs a corner. Claimed touches
  /// win immediately, so the page scroll can't steal the drag.
  bool _claimPointer(Offset globalPosition) {
    final p = _page;
    final rb = _canvasBox;
    if (p == null || rb == null || !p.loaded || _showResult || _eraserMode) return false;
    final local = rb.globalToLocal(globalPosition);
    final size = rb.size;
    int? best;
    var bestDistance = 48.0; // generous touch target around each handle
    for (var i = 0; i < 4; i++) {
      final corner = Offset(p.corners[i * 2] * size.width, p.corners[i * 2 + 1] * size.height);
      final d = (local - corner).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
        _grabOffset = corner - local;
      }
    }
    _pendingCorner = best;
    return best != null;
  }

  void _onDragStart(DragStartDetails d) {
    _dragIndex = _pendingCorner;
    HapticFeedback.selectionClick();
    _moveCorner(d.globalPosition);
  }

  void _onDragUpdate(DragUpdateDetails d) => _moveCorner(d.globalPosition);

  /// The corner follows the finger 1:1 (keeping the initial grab offset).
  void _moveCorner(Offset globalPosition) {
    final i = _dragIndex;
    final p = _page;
    final rb = _canvasBox;
    if (i == null || p == null || rb == null) return;
    final size = rb.size;
    final local = rb.globalToLocal(globalPosition) + _grabOffset;
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    p.corners[i * 2] = x;
    p.corners[i * 2 + 1] = y;
    _cornerTick.value++;
    _loupe.value = Offset(x * size.width, y * size.height);
  }

  void _endDrag() {
    if (_dragIndex == null) return;
    _loupe.value = null;
    _markDirty((_) => _dragIndex = null);
  }

  void _goTo(int index) {
    if (index < 0 || index >= _edits.length) return;
    setState(() {
      _index = index;
      _dragIndex = null;
      _edits[index].resultBytes = null;
    });
    _cornerTick.value++;
    _scheduleRender(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.slate900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.document_scanner, color: AppTheme.primaryGreen, size: 18),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Crop & Clean',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.slate600),
            enabled: !_busy && page != null,
            onSelected: _onMenu,
            itemBuilder: (_) => [
              if (_edits.length > 1)
                const PopupMenuItem(value: 'apply-all', child: Text('Apply these settings to all pages')),
              PopupMenuItem(
                value: 'detect',
                enabled: page?.detected != null,
                child: const Text('Snap to detected edges'),
              ),
              const PopupMenuItem(value: 'full', child: Text('Use full image')),
              const PopupMenuItem(value: 'delete', child: Text('Remove this page')),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppTheme.slate200),
                bottom: BorderSide(color: AppTheme.slate200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _pagerButton(Icons.chevron_left, _index > 0 ? () => _goTo(_index - 1) : null),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Page ${_index + 1} of ${_edits.length}',
                              style: const TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate900,
                              ),
                            ),
                            const Text(
                              'CROP & ENHANCE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _pagerButton(
                          Icons.chevron_right, _index < _edits.length - 1 ? () => _goTo(_index + 1) : null),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _resetPage,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _finishEditing,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (page != null)
            SingleChildScrollView(
              child: Column(
                children: [
                  _buildModeToggle(),
                  if (_showResult) _buildResult(page) else _buildCanvas(page),
                  if (_edits.length > 1) _buildPageStrip(),
                  _buildPresets(page),
                  _buildControls(page),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          if (_busy) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _pagerButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.slate100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: onTap == null ? AppTheme.slate300 : AppTheme.slate700, size: 20),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Canvas
  // ------------------------------------------------------------------

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Adjust crop'), icon: Icon(Icons.crop, size: 18)),
            ButtonSegment(value: true, label: Text('Preview result'), icon: Icon(Icons.visibility_outlined, size: 18)),
          ],
          selected: {_showResult},
          onSelectionChanged: (v) => _setResultMode(v.first),
        ),
      ),
    );
  }

  /// The cropped, filtered page exactly as Save will produce it (at preview
  /// resolution).
  Widget _buildResult(_PageEdit page) {
    final bytes = page.resultBytes;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: Center(
          child: bytes == null
              ? const SizedBox(height: 320, child: Center(child: CircularProgressIndicator()))
              : AspectRatio(
                  aspectRatio: page.resultRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCanvas(_PageEdit page) {
    final image = page.filteredBytes ?? page.previewBytes;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _CornerDragRecognizer: GestureRecognizerFactoryWithHandlers<_CornerDragRecognizer>(
          () => _CornerDragRecognizer(),
          (r) => r
            ..claims = _claimPointer
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = _onDragStart
            ..onUpdate = _onDragUpdate
            ..onEnd = ((_) => _endDrag())
            ..onCancel = _endDrag,
        ),
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (r) => r.onTapUp = _onCanvasTap,
        ),
      },
      // The padding is part of the touch area, so handles sitting on the
      // image border can still be grabbed from outside.
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AspectRatio(
          aspectRatio: page.ratio,
          child: LayoutBuilder(
            key: _canvasBoxKey,
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: page.error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(page.error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppTheme.slate300)),
                              ),
                            )
                          : image == null
                              ? const Center(child: CircularProgressIndicator())
                              : Image.memory(
                                  image,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                    ),
                  ),
                  // Crop quad, darkened outside area and handles
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _CropQuadPainter(
                            corners: page.corners,
                            activeIndex: () => _dragIndex,
                            showHandles: !_eraserMode,
                            repaint: _cornerTick,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_eraserMode)
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'ERASER MODE — tap spots to erase',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (final s in page.strokes)
                    Positioned(
                      left: s[0] * w - 20,
                      top: s[1] * h - 20,
                      child: IgnorePointer(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.85),
                            border: Border.all(color: AppTheme.primaryGreen, width: 1),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: page.detected != null ? AppTheme.primaryGreen : AppTheme.slate400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            page.filter != 0
                                ? _filterNames[page.filter].toUpperCase()
                                : page.detected != null
                                    ? 'EDGES DETECTED • DRAG TO ADJUST'
                                    : 'DRAG CORNERS TO CROP',
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Magnifier above the corner being dragged
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _loupe,
                    builder: (context, pos, _) {
                      if (pos == null) return const SizedBox.shrink();
                      const size = 96.0, lift = 86.0;
                      // Show it below the finger when there is no room above.
                      final dy = pos.dy - lift - size / 2 < -20 ? lift : -lift;
                      return Positioned(
                        left: pos.dx - size / 2,
                        top: pos.dy + dy - size / 2,
                        child: IgnorePointer(
                          child: RawMagnifier(
                            size: const Size(size, size),
                            magnificationScale: 2.2,
                            focalPointOffset: Offset(0, -dy),
                            decoration: MagnifierDecoration(
                              shape: const CircleBorder(side: BorderSide(color: AppTheme.primaryGreen, width: 2)),
                              shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                            ),
                            child: const Center(child: Icon(Icons.add, color: AppTheme.primaryGreen, size: 18)),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPageStrip() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        itemCount: _edits.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = _edits[i];
          final selected = i == _index;
          return GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: 46,
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppTheme.primaryGreen : AppTheme.slate200,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (e.previewBytes != null)
                      Image.memory(e.previewBytes!, fit: BoxFit.cover, cacheWidth: 120)
                    else
                      const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                    Positioned(
                      left: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: Colors.white.withValues(alpha: 0.85),
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Presets & controls
  // ------------------------------------------------------------------

  Widget _buildPresets(_PageEdit page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ENHANCEMENT PRESETS',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: AppTheme.slate600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.successBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, size: 12, color: AppTheme.primaryGreen),
                    SizedBox(width: 4),
                    Text(
                      'ON-DEVICE CLEAN ENGINE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.successText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _filterNames.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildFilterPreset(page, i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPreset(_PageEdit page, int index) {
    final selected = page.filter == index;
    return GestureDetector(
      onTap: () => _markDirty((p) => p.filter = index),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primaryGreen : AppTheme.slate200, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? AppTheme.successGreen : AppTheme.slate100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_filterIcons[index], color: selected ? AppTheme.primaryGreen : AppTheme.slate700),
            ),
            const SizedBox(height: 6),
            Text(
              _filterNames[index],
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppTheme.primaryGreen : AppTheme.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(_PageEdit page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.crop_rotate, color: AppTheme.primaryGreen, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Auto Deskew',
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slate900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: page.autoDeskew,
                          onChanged: (val) => _markDirty((p) => p.autoDeskew = val),
                          activeThumbColor: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _markDirty((p) => p.rotateQuads = (p.rotateQuads + 1) % 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.rotate_90_degrees_cw, color: AppTheme.secondary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          page.rotateQuads == 0 ? 'Rotate 90°' : 'Rotated ${page.rotateQuads * 90}°',
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: page.rotateQuads == 0 ? AppTheme.slate900 : AppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Column(
              children: [
                _buildSlider(
                  'Shadow Remover',
                  Icons.blur_on,
                  page.shadow,
                  (val) => _markDirty((p) => p.shadow = val),
                  AppTheme.primaryGreen,
                ),
                const SizedBox(height: 8),
                _buildSlider(
                  'Dynamic Contrast',
                  Icons.tonality,
                  page.contrast,
                  (val) => _markDirty((p) => p.contrast = val),
                  AppTheme.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap "Preview result" to see the cropped page before saving.',
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, IconData icon, double value, ValueChanged<double> onChanged, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.slate900,
                  ),
                ),
              ],
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: AppTheme.slate200,
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(value: value, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildBusyOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black38,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primaryGreen),
                const SizedBox(height: 16),
                Text(
                  _busyLabel,
                  style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  void _onMenu(String action) {
    final p = _page;
    if (p == null) return;
    switch (action) {
      case 'apply-all':
        setState(() {
          for (final e in _edits) {
            if (identical(e, p)) continue;
            e
              ..filter = p.filter == 5 ? e.filter : p.filter
              ..shadow = p.shadow
              ..contrast = p.contrast
              ..autoDeskew = p.autoDeskew
              ..rotateQuads = p.rotateQuads
              ..dirty = true;
          }
        });
        _scheduleRender(immediate: true);
        showSnack(context, 'Settings applied to all ${_edits.length} pages');
      case 'detect':
        _markDirty((p) => p.resetCorners());
      case 'full':
        _markDirty((p) => p.corners.setAll(0, _fullFrame));
      case 'delete':
        _removeCurrentPage();
    }
  }

  void _removeCurrentPage() {
    final i = _index;
    _session.removeAt(i);
    setState(() {
      _edits.removeAt(i);
      if (_index >= _edits.length) _index = _edits.length - 1;
    });
    if (_edits.isEmpty) {
      Navigator.pop(context);
      return;
    }
    _cornerTick.value++;
    _scheduleRender(immediate: true);
  }

  void _resetPage() {
    final p = _page;
    if (p == null) return;
    setState(() {
      p.filter = 0;
      p.shadow = 0.0;
      p.contrast = 0.0;
      p.rotateQuads = 0;
      p.autoDeskew = true;
      p.strokes.clear();
      p.resetCorners();
      p.dirty = p.detected != null;
    });
    _cornerTick.value++;
    _scheduleRender(immediate: true);
  }

  /// Processes every edited page, then saves the batch to the library.
  Future<void> _finishEditing() async {
    if (_edits.isEmpty) return;
    if (_edits.any((e) => !e.loaded)) {
      showSnack(context, 'Still loading pages…');
      return;
    }
    if (_edits.any((e) => e.error != null)) {
      showSnack(context, 'Remove the pages that could not be opened first.', error: true);
      return;
    }
    final store = DocumentStore.instance;
    final processed = <File>[];
    setState(() => _busy = true);
    try {
      await store.tempDir.create(recursive: true);
      final outputs = <File>[];
      for (var i = 0; i < _edits.length; i++) {
        final e = _edits[i];
        if (!e.dirty) {
          outputs.add(e.file);
          continue;
        }
        setState(() => _busyLabel = 'Processing page ${i + 1} of ${_edits.length}…');
        final req = PipelineRequest(
          srcPathAsBytes: await e.file.readAsBytes(),
          corners: List.of(e.corners),
          shadowRemoval: e.shadow,
          contrast: e.contrast,
          filterIndex: e.filter == 5
              ? FilterMode.original // eraser-only mode keeps color
              : _pipelineFilterOfChip[e.filter],
          strokes: e.strokes,
          deskew: e.autoDeskew,
          rotateQuads: e.rotateQuads,
          maxOutDim: 2400,
        );
        final encoded = await compute(_processIsolate, req.toMap());
        final out = File('${store.tempDir.path}/edit_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await out.writeAsBytes(encoded);
        processed.add(out);
        outputs.add(out);
      }

      setState(() => _busyLabel = 'Saving to vault…');
      final target = _session.targetDocId == null ? null : store.byId(_session.targetDocId!);
      final String docId;
      if (target != null && _session.replacePageIndex != null) {
        await store.replacePage(target.id, _session.replacePageIndex!, outputs.first);
        docId = target.id;
      } else if (target != null) {
        await store.addPages(target.id, outputs);
        docId = target.id;
      } else {
        docId = (await store.createDocument(outputs, kind: _session.kind)).id;
      }
      _session.clear();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/detail', ModalRoute.withName('/'), arguments: docId);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Processing failed: $e', error: true);
      }
    } finally {
      // The store keeps its own copies.
      for (final f in processed) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Runs pipeline + JPEG encode in a background isolate.
  static Uint8List _processIsolate(Map<String, dynamic> m) =>
      processAndEncodeIsolate(PipelineRequest.fromMap(m));
}

/// Pan recognizer that only takes pointers landing on a crop handle, and
/// wins the gesture arena immediately for them (ahead of the page scroll).
class _CornerDragRecognizer extends PanGestureRecognizer {
  bool Function(Offset globalPosition) claims = _never;

  static bool _never(Offset _) => false;

  @override
  bool isPointerAllowed(PointerEvent event) => super.isPointerAllowed(event) && claims(event.position);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _CropQuadPainter extends CustomPainter {
  _CropQuadPainter({
    required this.corners,
    required this.activeIndex,
    required this.showHandles,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<double> corners; // mutated in place while dragging
  final int? Function() activeIndex;
  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      for (var i = 0; i < 4; i++) Offset(corners[i * 2] * size.width, corners[i * 2 + 1] * size.height),
    ];
    final quad = Path()..addPolygon(points, true);

    // Dim everything that will be cropped away.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPolygon(points, true);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawPath(
        quad,
        Paint()
          ..color = AppTheme.primaryGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Rule-of-thirds guides inside the quad.
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    Offset lerp(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;
    for (final t in const [1 / 3, 2 / 3]) {
      canvas.drawLine(lerp(points[0], points[1], t), lerp(points[3], points[2], t), guide);
      canvas.drawLine(lerp(points[0], points[3], t), lerp(points[1], points[2], t), guide);
    }

    if (!showHandles) return;
    final active = activeIndex();
    for (var i = 0; i < 4; i++) {
      final p = points[i];
      final isActive = active == i;
      if (isActive) {
        canvas.drawCircle(p, 26, Paint()..color = AppTheme.primaryGreen.withValues(alpha: 0.25));
      }
      canvas.drawCircle(
          p,
          isActive ? 17 : 15,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(p, isActive ? 16 : 14, Paint()..color = Colors.white);
      canvas.drawCircle(p, isActive ? 8 : 7, Paint()..color = AppTheme.primaryGreen);
    }
  }

  @override
  bool shouldRepaint(_CropQuadPainter oldDelegate) => true;
}
