import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/scan_document.dart';
import '../../models/scan_session.dart';
import '../../services/document_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pipeline.dart';

/// Capture modes offered by the viewfinder.
class ScanMode {
  static const String single = 'single';
  static const String batch = 'batch';
  static const String idCard = 'id-card';
  static const String book = 'book';
  static const String qr = 'qr';
}

class CameraViewfinderScreen extends StatefulWidget {
  const CameraViewfinderScreen({super.key});

  @override
  State<CameraViewfinderScreen> createState() => _CameraViewfinderScreenState();
}

class _CameraViewfinderScreenState extends State<CameraViewfinderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _laserController;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  String? _cameraError;

  bool isAutoMode = DocumentStore.instance.settings.autoCapture;
  int flashMode = 0; // 0: auto, 1: torch/on, 2: off
  bool _capturing = false;
  bool _showGrid = false;
  String _mode = ScanMode.batch;
  bool _modeFromArgs = false;

  // Live detection state
  bool _streaming = false;
  bool _processingFrame = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  List<double>? _liveQuad; // normalized to the preview, tl,tr,br,bl
  List<double>? _stableQuad;
  int _stableCount = 0;
  bool _autoArmed = true;

  bool _initializing = false;
  bool _away = false; // another screen (editor, QR scanner) is on top

  final ScanSession _session = ScanSession.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _laserController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_modeFromArgs) {
      _modeFromArgs = true;
      final arg = ModalRoute.of(context)?.settings.arguments;
      if (arg is String && arg != ScanMode.qr) _mode = arg;
      if (_session.kind == DocumentKind.idCard) _mode = ScanMode.idCard;
      if (_session.kind == DocumentKind.book) _mode = ScanMode.book;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller != null) {
        _controller = null;
        _cameraReady = false;
        _streaming = false;
        controller.dispose();
      }
    } else if (state == AppLifecycleState.resumed && _controller == null && mounted && !_away) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera available on this device.');
        return;
      }
      // Prefer the back camera.
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // Stream formats used for live edge detection; stills are always JPEG.
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraReady = true;
        _cameraError = null;
      });
      await _applyFlash();
      if (!_away) await _startStream();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e.code == 'CameraAccessDenied'
            ? 'Camera permission denied. Enable it in system settings to scan.'
            : 'Camera error: ${e.description ?? e.code}';
        _cameraReady = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Camera unavailable: $e';
        _cameraReady = false;
      });
    } finally {
      _initializing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _laserController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Live detection
  // ---------------------------------------------------------------------------

  bool get _detectionEnabled => _mode != ScanMode.book;

  Future<void> _startStream() async {
    final controller = _controller;
    if (controller == null || _streaming || _away || !_detectionEnabled) return;
    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
    } catch (e) {
      // Streaming is optional; capture still works without live detection.
      debugPrint('ScanCraft: image stream unavailable: $e');
    }
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (_processingFrame || now.difference(_lastFrame).inMilliseconds < 350) return;
    _processingFrame = true;
    _lastFrame = now;
    try {
      final quad = _detectInFrame(image);
      if (!mounted) return;
      _updateQuad(quad);
    } catch (e) {
      debugPrint('ScanCraft: detection failed: $e');
    } finally {
      _processingFrame = false;
    }
  }

  /// Samples the frame's luminance down to ~120px wide and runs the detector,
  /// then rotates the result into the upright preview orientation.
  List<double>? _detectInFrame(CameraImage image) {
    const targetW = 120;
    final plane = image.planes.first;
    final step = (image.width / targetW).ceil().clamp(1, 64);
    final w = image.width ~/ step, h = image.height ~/ step;
    final lum = Uint8List(w * h);
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    var i = 0;
    for (var y = 0; y < h; y++) {
      final row = y * step * stride;
      for (var x = 0; x < w; x++) {
        if (isBgra) {
          final p = row + x * step * 4;
          lum[i++] = (bytes[p + 2] * 77 + bytes[p + 1] * 150 + bytes[p] * 29) >> 8;
        } else {
          lum[i++] = bytes[row + x * step];
        }
      }
    }
    final quad = detectQuadInLuminance(lum, w, h);
    if (quad == null) return null;
    // Android frames arrive in sensor orientation; iOS frames are already upright.
    final rotation = Platform.isAndroid ? (_controller?.description.sensorOrientation ?? 90) : 0;
    final pts = <List<double>>[];
    for (var k = 0; k < 4; k++) {
      final x = quad[k * 2], y = quad[k * 2 + 1];
      pts.add(switch (rotation) {
        90 => [1 - y, x],
        180 => [1 - x, 1 - y],
        270 => [y, 1 - x],
        _ => [x, y],
      });
    }
    return orderCorners(pts);
  }

  static double _quadDelta(List<double> a, List<double> b) {
    var m = 0.0;
    for (var i = 0; i < 8; i++) {
      final d = (a[i] - b[i]).abs();
      if (d > m) m = d;
    }
    return m;
  }

  void _updateQuad(List<double>? quad) {
    if (quad == null) {
      _stableQuad = null;
      _stableCount = 0;
      _autoArmed = true; // page removed -> ready for the next one
      setState(() => _liveQuad = null);
      return;
    }
    final prev = _stableQuad;
    if (prev != null && _quadDelta(prev, quad) < 0.03) {
      _stableCount++;
    } else {
      if (prev != null && _quadDelta(prev, quad) > 0.08) _autoArmed = true;
      _stableCount = 0;
    }
    _stableQuad = quad;
    setState(() => _liveQuad = quad);

    if (isAutoMode && _autoArmed && _stableCount >= 3 && !_capturing) {
      _autoArmed = false;
      _capture();
    }
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  Future<void> _applyFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      switch (flashMode) {
        case 0:
          await controller.setFlashMode(FlashMode.auto);
        case 1:
          await controller.setFlashMode(FlashMode.torch);
        default:
          await controller.setFlashMode(FlashMode.off);
      }
    } on CameraException {
      // Flash not supported on this device; ignore.
    }
  }

  Future<void> _cycleFlash() async {
    setState(() => flashMode = (flashMode + 1) % 3);
    await _applyFlash();
  }

  int get _requiredPages => switch (_mode) {
        ScanMode.single => 1,
        ScanMode.idCard => 2,
        _ => 0,
      };

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      await _stopStream();
      final XFile file = await controller.takePicture();
      if (_mode == ScanMode.book) {
        final halves = await compute(splitSpreadIsolate, await File(file.path).readAsBytes());
        final dir = DocumentStore.instance.tempDir;
        await dir.create(recursive: true);
        final stamp = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < halves.length; i++) {
          final out = File('${dir.path}/spread_${stamp}_$i.jpg');
          await out.writeAsBytes(halves[i]);
          _session.addPage(out);
        }
        try {
          await File(file.path).delete();
        } catch (_) {}
      } else {
        _session.addPage(File(file.path));
      }
      if (!mounted) return;
      setState(() {});
      final count = _session.pageCount;
      final required = _requiredPages;
      if (required > 0 && count >= required) {
        _goToEditor();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          backgroundColor: AppTheme.slate900,
          content: Text(
            _mode == ScanMode.idCard
                ? 'Front captured • now flip the card'
                : 'Page $count captured • tap Pages to continue',
            style: const TextStyle(fontFamily: 'Space Grotesk'),
          ),
        ),
      );
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.error,
            content: Text('Capture failed: ${e.code}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.error, content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
        await _startStream();
      }
    }
  }

  Future<void> _importFromGallery() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 95);
    if (picked.isEmpty || !mounted) return;
    for (final f in picked) {
      _session.addPage(File(f.path));
    }
    setState(() {});
    _goToEditor();
  }

  void _goToEditor() {
    if (_session.pageCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture or import at least one page first.')),
      );
      return;
    }
    _session.kind = switch (_mode) {
      ScanMode.idCard => DocumentKind.idCard,
      ScanMode.book => DocumentKind.book,
      _ => DocumentKind.document,
    };
    // Pause detection (and auto-capture) while the editor is on top.
    _away = true;
    _stopStream();
    Navigator.pushNamed(context, '/crop').then((_) {
      if (!mounted) return;
      _away = false;
      setState(() {
        _liveQuad = null;
        _autoArmed = false; // don't re-shoot the page that was just captured
      });
      if (_controller == null) {
        _initCamera();
      } else {
        _startStream();
      }
    });
  }

  Future<void> _selectMode(String mode) async {
    if (mode == ScanMode.qr) {
      // The barcode scanner needs exclusive access to the camera.
      final controller = _controller;
      setState(() {
        _controller = null;
        _cameraReady = false;
        _streaming = false;
        _liveQuad = null;
      });
      _away = true;
      await controller?.dispose();
      if (!mounted) return;
      await Navigator.pushNamed(context, '/qr');
      _away = false;
      if (mounted) _initCamera();
      return;
    }
    setState(() {
      _mode = mode;
      _liveQuad = null;
      _stableQuad = null;
      _stableCount = 0;
    });
    if (_detectionEnabled) {
      await _startStream();
    } else {
      await _stopStream();
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _instruction {
    if (!_cameraReady) return 'STARTING CAMERA…';
    if (_mode == ScanMode.idCard) {
      return _session.pageCount == 0 ? 'ID CARD • FRONT SIDE' : 'ID CARD • BACK SIDE';
    }
    if (_mode == ScanMode.book) return 'ALIGN SPINE WITH THE CENTER LINE';
    if (_liveQuad == null) return isAutoMode ? 'SEARCHING FOR DOCUMENT…' : 'MANUAL • TAP SHUTTER';
    return isAutoMode ? 'DOCUMENT DETECTED • HOLD STEADY' : 'DOCUMENT DETECTED • TAP SHUTTER';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ===== Real camera preview with aligned overlays =====
          Positioned.fill(child: _buildCameraPreview()),
          // Dark scrim to help overlays read well
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Sweeping laser line while searching
          if (_cameraReady && _liveQuad == null && _detectionEnabled)
            AnimatedBuilder(
              animation: _laserController,
              builder: (context, child) {
                return Align(
                  alignment: Alignment(
                    0,
                    _laserController.value * 1.6 - 0.8,
                  ),
                  child: IgnorePointer(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppTheme.primaryGreen,
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          // UI chrome
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                if (_session.targetDocId != null) _buildTargetPill(),
                const Spacer(),
                _buildInstructPill(_instruction, dotted: _liveQuad != null),
                const SizedBox(height: 12),
                _buildModeChips(),
                const SizedBox(height: 12),
                _buildOfflinePill(),
                const SizedBox(height: 24),
                _buildBottomControls(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _controller;
    if (_cameraError != null) {
      return Container(
        color: AppTheme.slate900,
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: AppTheme.slate400, size: 40),
            const SizedBox(height: 12),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.slate400, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _cameraError = null);
                _initCamera();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: AppTheme.slate900,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryGreen),
            SizedBox(height: 12),
            Text(
              'Initializing camera…',
              style: TextStyle(color: AppTheme.slate400, fontSize: 12),
            ),
          ],
        ),
      );
    }
    // Size the preview at its true (portrait) aspect ratio and cover the
    // screen, so overlays drawn in the same box line up with the image.
    final previewSize = controller.value.previewSize;
    final pw = previewSize == null ? 3.0 : previewSize.shortestSide;
    final ph = previewSize == null ? 4.0 : previewSize.longestSide;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: pw,
          height: ph,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              IgnorePointer(
                child: CustomPaint(
                  painter: _OverlayPainter(
                    quad: _liveQuad,
                    showGrid: _showGrid,
                    mode: _mode,
                    scale: pw / 360,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _roundIcon(
            child: const Icon(Icons.arrow_back, color: AppTheme.slate900),
            onTap: () => Navigator.pop(context),
          ),
          // AUTO / MANUAL pill
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              children: [
                _modeToggle('AUTO', isAutoMode, () => setState(() {
                      isAutoMode = true;
                      _autoArmed = true;
                    })),
                _modeToggle('MANUAL', !isAutoMode, () => setState(() => isAutoMode = false)),
              ],
            ),
          ),
          Row(
            children: [
              _roundIcon(
                child: Icon(
                  flashMode == 0
                      ? Icons.flash_auto
                      : flashMode == 1
                          ? Icons.flash_on
                          : Icons.flash_off,
                  color: flashMode == 1 ? AppTheme.primaryGreen : AppTheme.slate700,
                  size: 20,
                ),
                onTap: _cycleFlash,
              ),
              const SizedBox(width: 6),
              _roundIcon(
                child: Icon(Icons.grid_4x4,
                    color: _showGrid ? AppTheme.primaryGreen : AppTheme.slate700, size: 20),
                onTap: () => setState(() => _showGrid = !_showGrid),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetPill() {
    final doc = DocumentStore.instance.byId(_session.targetDocId!);
    if (doc == null) return const SizedBox.shrink();
    return _buildInstructPill('ADDING TO: ${doc.name.toUpperCase()}');
  }

  Widget _roundIcon({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.slate200),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _modeToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppTheme.slate600,
          ),
        ),
      ),
    );
  }

  Widget _buildInstructPill(String text, {bool dotted = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotted)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.primaryGreen,
                shape: BoxShape.circle,
              ),
            ),
          if (dotted) const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChips() {
    // Adding to / replacing within an existing document keeps the mode fixed.
    final locked = _session.targetDocId != null;
    final modes = [
      (ScanMode.single, 'Single Page', Icons.crop_portrait),
      (ScanMode.batch, 'Batch / Multi-Page', Icons.filter_none),
      if (!locked) (ScanMode.idCard, 'ID Card / Passport', Icons.badge_outlined),
      (ScanMode.book, 'Book / Dual', Icons.menu_book_outlined),
      if (!locked) (ScanMode.qr, 'QR / Barcode', Icons.qr_code_scanner),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (mode, label, icon) in modes) ...[
            _modeChip(label, _mode == mode, icon, () {
              if (_session.pageCount > 0 && mode != ScanMode.qr && mode != _mode && !locked) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Finish or clear the current pages before switching mode.'),
                ));
                return;
              }
              _selectMode(mode);
            }),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool isSelected, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.secondaryContainer : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.secondary.withValues(alpha: 0.3) : AppTheme.slate200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? AppTheme.secondary : AppTheme.slate500),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.onSecondaryContainer : AppTheme.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflinePill() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, color: AppTheme.primaryGreen, size: 16),
          const SizedBox(width: 6),
          Text(
            '100% On-Device • No Data Leaves Phone',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final lastPage = _session.lastPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _sideButton(
            icon: Icons.photo_library,
            label: 'Import',
            onTap: _importFromGallery,
          ),
          // Shutter button
          GestureDetector(
            onTap: _capturing ? null : _capture,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _capturing ? AppTheme.slate400 : AppTheme.primaryContainer,
                    ),
                    child: _capturing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.camera_alt, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
          ),
          // Pages tray
          GestureDetector(
            onTap: _goToEditor,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: lastPage != null
                            ? Image.file(lastPage, fit: BoxFit.cover, cacheWidth: 150)
                            : const Icon(Icons.description,
                                color: AppTheme.slate400, size: 22),
                      ),
                    ),
                    if (_session.pageCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${_session.pageCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _session.pageCount > 0 ? 'Done' : 'Pages',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Icon(icon, color: AppTheme.slate900, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the detected page outline, the rule-of-thirds grid, and mode guides
/// (ID card frame, book spine) on top of the preview.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.quad, required this.showGrid, required this.mode, required this.scale});

  final List<double>? quad;
  final bool showGrid;
  final String mode;
  final double scale; // keeps stroke widths visually constant across preview sizes

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1 * scale;
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), grid);
        canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), grid);
      }
    }

    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale;
    if (mode == ScanMode.idCard) {
      // ID-1 card ratio 85.6 x 54 mm.
      final w = size.width * 0.86;
      final h = w / 1.586;
      final rect = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(12 * scale)), guide);
    } else if (mode == ScanMode.book) {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, size.height * 0.1), Offset(x, size.height * 0.9), guide);
    }

    final q = quad;
    if (q == null) return;
    final pts = [
      for (var i = 0; i < 4; i++) Offset(q[i * 2] * size.width, q[i * 2 + 1] * size.height),
    ];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
        path,
        Paint()
          ..color = AppTheme.primaryGreen.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = AppTheme.primaryGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * scale);
    final dot = Paint()..color = Colors.white;
    final core = Paint()..color = AppTheme.primaryGreen;
    for (final p in pts) {
      canvas.drawCircle(p, 12 * scale, dot);
      canvas.drawCircle(p, 6 * scale, core);
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.quad != quad || old.showGrid != showGrid || old.mode != mode || old.scale != scale;
}
