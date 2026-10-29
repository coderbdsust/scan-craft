import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../models/scan_session.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pipeline.dart';

class CropCleanEditorScreen extends StatefulWidget {
  const CropCleanEditorScreen({super.key});

  @override
  State<CropCleanEditorScreen> createState() => _CropCleanEditorScreenState();
}

class _CropCleanEditorScreenState extends State<CropCleanEditorScreen> {
  File? _baseFile; // source page being edited
  Uint8List? _previewBytes; // small preview for the canvas

  // Crop quad in normalized canvas coords (uv 0..1)
  final List<double> _corners = [0.08, 0.10, 0.92, 0.06, 0.94, 0.90, 0.06, 0.94]; // tl, tr, br, bl
  int? _dragIndex;

  bool autoDeskew = true;
  int selectedFilter = 0;
  double shadowRemover = 0.0;
  double contrast = 0.0;
  int rotateQuads = 0;

  final List<List<double>> _strokes = []; // normalized to canvas

  bool _dirty = false;
  bool _busy = false;

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

  RenderBox? get _canvasBox =>
      _canvasBoxKey.currentContext?.findRenderObject() as RenderBox?;

  @override
  void initState() {
    super.initState();
    final session = ScanSession.instance;
    if (session.lastPage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    _loadPreview(session.lastPage!);
  }

  Future<void> _loadPreview(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final baked = img.bakeOrientation(decoded);
      // Small preview for fast iteration
      final maxDim = _maxInt(baked.width, baked.height);
      img.Image preview = baked;
      if (maxDim > 1400) {
        final scale = 1400.0 / maxDim;
        preview = img.copyResize(baked, width: (baked.width * scale).round());
      }
      final previewBytes = Uint8List.fromList(img.encodeJpg(preview, quality: 92));
      if (!mounted) return;
      setState(() {
        _baseFile = file;
        _previewBytes = previewBytes;
        // Match canvas aspect to the actual page so crop UVs map 1:1.
        _canvasRatio = preview.width / preview.height;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load image: $e')),
        );
      }
    }
  }

  static int _maxInt(int a, int b) => a > b ? a : b;

  bool get _eraserMode => selectedFilter == 5;

  void _dragCorner(int index, DragUpdateDetails d) {
    final rb = _canvasBox;
    if (rb == null) return;
    final size = rb.size;
    setState(() {
      _corners[index * 2] = (_corners[index * 2] + d.delta.dx / size.width).clamp(0.0, 1.0);
      _corners[index * 2 + 1] = (_corners[index * 2 + 1] + d.delta.dy / size.height).clamp(0.0, 1.0);
      _dirty = true;
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
    setState(() {
      _strokes.add([u, v, 0.035]);
      _dirty = true;
    });
  }

  int? _hitCorner(Offset local, Size size) {
    const radius = 34.0;
    for (var i = 0; i < 4; i++) {
      final cx = _corners[i * 2] * size.width;
      final cy = _corners[i * 2 + 1] * size.height;
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

  final GlobalKey _canvasBoxKey = GlobalKey();

  /// Canvas aspect ratio (width/height); matches the page image so the
  /// contained image fills the box exactly and UV math maps 1:1.
  double _canvasRatio = 3 / 4;

  @override
  Widget build(BuildContext context) {
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
                color: AppTheme.primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.document_scanner, color: AppTheme.primaryGreen, size: 18),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Document Inspection',
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
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppTheme.slate600),
            onPressed: () {},
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
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.chevron_left, color: AppTheme.slate700, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Page Editor',
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate900,
                              ),
                            ),
                            Text(
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
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _resetAll,
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
                      label: const Text('Done'),
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
          SingleChildScrollView(
            child: Column(
              children: [
                _buildCanvas(),
                _buildPresets(),
                _buildControls(),
                const SizedBox(height: 40),
              ],
            ),
          ),
          if (_busy) _buildBusyOverlay(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Canvas
  // ------------------------------------------------------------------

  Widget _buildCanvas() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: _canvasRatio,
        child: LayoutBuilder(
          key: _canvasBoxKey,
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final handles = <Widget>[];
            for (var i = 0; i < 4; i++) {
              final cx = _corners[i * 2] * w;
              final cy = _corners[i * 2 + 1] * h;
              final isDragged = _dragIndex == i;
              handles.add(Positioned(
                left: cx - 16,
                top: cy - 16,
                child: _buildCropHandle(isActive: isDragged || i == 0),
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
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _previewBytes == null
                          ? const Center(child: CircularProgressIndicator())
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                _previewBytes!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ),
                    ),
                  ),
                  // Crop quad
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CropQuadPainter(_corners),
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
                  for (final s in _strokes)
                    Positioned(
                      left: s[0] * w - 20,
                      top: s[1] * h - 20,
                      child: IgnorePointer(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.55),
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
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            selectedFilter == 0 ? 'DRAG CORNERS TO CROP' : _filterNames[selectedFilter].toUpperCase(),
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
            color: Colors.black.withOpacity(0.2),
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
                      color: AppTheme.primaryGreen.withOpacity(0.5),
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

  // ------------------------------------------------------------------
  // Presets & controls
  // ------------------------------------------------------------------

  Widget _buildPresets() {
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
                    child: _buildFilterPreset(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPreset(int index) {
    final selected = selectedFilter == index;
    return GestureDetector(
      onTap: () => setState(() {
        selectedFilter = index;
        _dirty = true;
      }),
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

  Widget _buildControls() {
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
                          value: autoDeskew,
                          onChanged: (val) => setState(() {
                            autoDeskew = val;
                            _dirty = true;
                          }),
                          activeColor: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    rotateQuads = (rotateQuads + 1) % 4;
                    _dirty = true;
                  }),
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
                          rotateQuads == 0 ? 'Rotate 90°' : 'Rotated $rotateQuads×',
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: rotateQuads == 0 ? AppTheme.slate900 : AppTheme.primaryGreen,
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
                  shadowRemover,
                  (val) => setState(() {
                    shadowRemover = val;
                    _dirty = true;
                  }),
                  AppTheme.primaryGreen,
                ),
                const SizedBox(height: 8),
                _buildSlider(
                  'Dynamic Contrast',
                  Icons.tonality,
                  contrast,
                  (val) => setState(() {
                    contrast = val;
                    _dirty = true;
                  }),
                  AppTheme.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, IconData icon, double value, Function(double) onChanged, Color color) {
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
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primaryGreen),
                SizedBox(height: 16),
                Text(
                  'Applying on-device engine…',
                  style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600),
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

  void _resetAll() {
    setState(() {
      selectedFilter = 0;
      shadowRemover = 0.0;
      contrast = 0.0;
      rotateQuads = 0;
      autoDeskew = true;
      _strokes.clear();
      _corners.setAll(0, [0.08, 0.10, 0.92, 0.06, 0.94, 0.90, 0.06, 0.94]);
      _dirty = false;
    });
  }

  /// Produces a preview bytes of the current state live (only for the visual
  /// canvas). Full processing happens on Done.
  Future<void> _finishEditing() async {
    if (_baseFile == null) return;
    setState(() => _busy = true);
    try {
      final hasEdit = _dirty;
      if (!hasEdit) {
        // Pass through untouched page
        if (!mounted) return;
        Navigator.pushNamed(context, '/detail');
        return;
      }
      final file = _baseFile!;
      final bytes = await file.readAsBytes();

      final pipelineFilter = selectedFilter == 5
          ? FilterMode.original // eraser-only mode keeps color
          : _pipelineFilterOfChip[selectedFilter];

      final req = PipelineRequest(
        srcPathAsBytes: bytes,
        corners: _corners,
        shadowRemoval: shadowRemover,
        contrast: contrast,
        filterIndex: pipelineFilter,
        strokes: _strokes,
        deskew: autoDeskew,
        rotateQuads: rotateQuads,
        maxOutDim: 2200,
      );
      final encoded = await compute(_processIsolate, req.toMap());

      final dir = await getApplicationDocumentsDirectory();
      final scansDir = Directory('${dir.path}/scans');
      if (!await scansDir.exists()) {
        await scansDir.create(recursive: true);
      }
      final base = file.path.split('/').last.replaceAll('.', '_');
      final out = File(
          '${scansDir.path}/$base-edited-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(encoded);

      // Swap the processed file into the session page list.
      final idx = ScanSession.instance.pages.lastIndexOf(file);
      if (idx >= 0) {
        ScanSession.instance.pages[idx] = out;
      } else {
        ScanSession.instance.addPage(out);
      }
      if (!mounted) return;
      Navigator.pushNamed(context, '/detail');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.error,
            content: Text('Processing failed: $e'),
          ),
        );
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
      ..color = AppTheme.primaryGreen.withOpacity(0.14)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);
    final stroke = Paint()
      ..color = AppTheme.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, stroke);

    // Perspective guide lines (faint)
    final guide = Paint()
      ..color = AppTheme.primaryGreen.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(points[0], points[2], guide);
    canvas.drawLine(points[1], points[3], guide);
  }

  @override
  bool shouldRepaint(_CropQuadPainter oldDelegate) => oldDelegate.corners != corners;
}
