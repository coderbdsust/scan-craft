import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  int? _dragIndex;

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

  bool get _eraserMode => _page?.filter == 5;

  void _markDirty(void Function(_PageEdit p) change) {
    final p = _page;
    if (p == null) return;
    setState(() {
      change(p);
      p.dirty = true;
    });
  }

  void _dragCorner(int index, DragUpdateDetails d) {
    final rb = _canvasBox;
    if (rb == null) return;
    final size = rb.size;
    _markDirty((p) {
      p.corners[index * 2] = (p.corners[index * 2] + d.delta.dx / size.width).clamp(0.0, 1.0);
      p.corners[index * 2 + 1] = (p.corners[index * 2 + 1] + d.delta.dy / size.height).clamp(0.0, 1.0);
    });
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

  int? _hitCorner(Offset local, Size size) {
    final p = _page;
    if (p == null) return null;
    const radius = 34.0;
    for (var i = 0; i < 4; i++) {
      final cx = p.corners[i * 2] * size.width;
      final cy = p.corners[i * 2 + 1] * size.height;
      final d = (local - Offset(cx, cy)).distance;
      if (d <= radius) return i;
    }
    return null;
  }

  void _onPanStart(DragStartDetails d) {
    if (_eraserMode) return;
    final rb = _canvasBox;
    if (rb == null) return;
    final local = rb.globalToLocal(d.globalPosition);
    setState(() => _dragIndex = _hitCorner(local, rb.size));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final i = _dragIndex;
    if (i != null) {
      _dragCorner(i, d);
    }
  }

  void _onPanEnd(DragEndDetails d) => setState(() => _dragIndex = null);

  void _goTo(int index) {
    if (index < 0 || index >= _edits.length) return;
    setState(() {
      _index = index;
      _dragIndex = null;
    });
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
                  _buildCanvas(page),
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

  Widget _buildCanvas(_PageEdit page) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: page.ratio,
        child: LayoutBuilder(
          key: _canvasBoxKey,
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final handles = <Widget>[];
            for (var i = 0; i < 4; i++) {
              final cx = page.corners[i * 2] * w;
              final cy = page.corners[i * 2 + 1] * h;
              final isDragged = _dragIndex == i;
              handles.add(Positioned(
                left: cx - 16,
                top: cy - 16,
                child: _buildCropHandle(isActive: isDragged),
              ));
            }
            return GestureDetector(
              onTapUp: _onCanvasTap,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
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
                          : page.previewBytes == null
                              ? const Center(child: CircularProgressIndicator())
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    page.previewBytes!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                    ),
                  ),
                  // Crop quad
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CropQuadPainter(List.of(page.corners)),
                      ),
                    ),
                  ),
                  ...handles,
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
                            color: Colors.white.withValues(alpha: 0.55),
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCropHandle({required bool isActive}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryGreen,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
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
            'Filters and sliders are applied when you tap Save.',
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
    if (_edits.isEmpty) Navigator.pop(context);
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

class _CropQuadPainter extends CustomPainter {
  final List<double> corners;

  _CropQuadPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(corners[0] * size.width, corners[1] * size.height),
      Offset(corners[2] * size.width, corners[3] * size.height),
      Offset(corners[4] * size.width, corners[5] * size.height),
      Offset(corners[6] * size.width, corners[7] * size.height),
    ];
    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();
    final fill = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);
    final stroke = Paint()
      ..color = AppTheme.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, stroke);

    // Perspective guide lines (faint)
    final guide = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(points[0], points[2], guide);
    canvas.drawLine(points[1], points[3], guide);
  }

  @override
  bool shouldRepaint(_CropQuadPainter oldDelegate) => !listEquals(oldDelegate.corners, corners);
}
