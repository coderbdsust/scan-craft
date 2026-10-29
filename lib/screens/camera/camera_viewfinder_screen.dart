import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/scan_session.dart';
import '../../theme/app_theme.dart';

class CameraViewfinderScreen extends StatefulWidget {
  const CameraViewfinderScreen({super.key});

  @override
  State<CameraViewfinderScreen> createState() => _CameraViewfinderScreenState();
}

class _CameraViewfinderScreenState extends State<CameraViewfinderScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _laserController;

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  String? _cameraError;

  bool isAutoMode = true;
  int flashMode = 0; // 0: auto, 1: torch/on, 2: off
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'No camera available on this device.');
        return;
      }
      // Prefer the back camera.
      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraReady = true;
      });
    } on CameraException catch (e) {
      setState(() {
        _cameraError = 'Camera error: ${e.description ?? e.code}';
        _cameraReady = false;
      });
    } catch (e) {
      setState(() {
        _cameraError = 'Camera unavailable: $e';
        _cameraReady = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _laserController.dispose();
    super.dispose();
  }

  Future<void> _cycleFlash() async {
    setState(() => flashMode = (flashMode + 1) % 3);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      switch (flashMode) {
        case 0:
          await controller.setFlashMode(FlashMode.auto);
          break;
        case 1:
          await controller.setFlashMode(FlashMode.torch);
          break;
        default:
          await controller.setFlashMode(FlashMode.off);
      }
    } on CameraException {
      // Flash not supported on this device; ignore.
    }
  }

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
      final XFile file = await controller.takePicture();
      if (mounted) {
        ScanSession.instance.addPage(File(file.path));
        setState(() {});
        final count = ScanSession.instance.pageCount;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 1),
              backgroundColor: AppTheme.slate900,
              content: Text(
                'Page $count captured • tap DONE to continue',
                style: const TextStyle(fontFamily: 'Space Grotesk'),
              ),
            ),
          );
        }
      }
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.error,
            content: Text('Capture failed: ${e.code}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _goToEditor() {
    if (ScanSession.instance.pageCount == 0) return;
    Navigator.pushNamed(context, '/crop');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ===== Real camera preview =====
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
                      Colors.black.withOpacity(0.35),
                      Colors.transparent,
                      Colors.black.withOpacity(0.45),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Detection overlay decoration
          const Positioned.fill(
            child: IgnorePointer(
              child: DocumentDetectionOverlay(),
            ),
          ),
          // Sweeping laser line
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
                          color: AppTheme.primaryGreen.withOpacity(0.6),
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
                const Spacer(),
                _buildInstructPill(
                  _cameraReady
                      ? 'DOCUMENT DETECTED • AUTO SNAPPING'
                      : 'STARTING CAMERA ENGINE…',
                  dotted: _cameraReady,
                ),
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
              'Initializing optical engine…',
              style: TextStyle(color: AppTheme.slate400, fontSize: 12),
            ),
          ],
        ),
      );
    }
    // CameraPreview handles orientation internally on modern plugin versions.
    return CameraPreview(controller);
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
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              children: [
                _modeToggle('AUTO', isAutoMode, () => setState(() => isAutoMode = true)),
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
                child: const Icon(Icons.grid_4x4, color: AppTheme.slate700, size: 20),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundIcon({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
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
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppTheme.slate900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _modeChip('Single Page', false),
          const SizedBox(width: 8),
          _modeChip('Batch / Multi-Page', true, Icons.filter_none),
          const SizedBox(width: 8),
          _modeChip('ID Card / Passport', false),
          const SizedBox(width: 8),
          _modeChip('Book / Dual', false),
          const SizedBox(width: 8),
          _modeChip('QR / Barcode', false),
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool isSelected, [IconData? icon]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.secondaryContainer : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? AppTheme.secondary.withOpacity(0.3) : AppTheme.slate200),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppTheme.secondary),
            const SizedBox(width: 4),
          ],
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
    );
  }

  Widget _buildOfflinePill() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, color: AppTheme.primaryGreen, size: 16),
          const SizedBox(width: 6),
          Text(
            '🔒 100% On-Device • No Data Leaves Phone',
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
    final session = ScanSession.instance;
    final lastPage = session.lastPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _sideButton(
            icon: Icons.photo_library,
            label: 'Import',
            onTap: () async {
              // Gallery import (secondary path)
              final controller = _controller;
              if (controller != null && controller.value.isInitialized) {
                await controller.setFlashMode(FlashMode.off);
              }
            },
          ),
          // Shutter button
          GestureDetector(
            onTap: _capturing ? null : _capture,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
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
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: lastPage != null
                            ? Image.file(lastPage, fit: BoxFit.cover)
                            : const Icon(Icons.description,
                                color: AppTheme.slate400, size: 22),
                      ),
                    ),
                    if (session.pageCount > 0)
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
                            '${session.pageCount}',
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
                const Text(
                  'Pages',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.slate700,
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
              color: Colors.white.withOpacity(0.9),
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
              color: AppTheme.slate700,
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentDetectionOverlay extends StatelessWidget {
  const DocumentDetectionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final quad = Rect.fromLTWH(
          w * 0.14,
          h * 0.30,
          w * 0.72,
          h * 0.42,
        );
        final detectionPaint = Paint()
          ..color = AppTheme.primaryGreen.withOpacity(0.18)
          ..style = PaintingStyle.fill;
        final strokePaint = Paint()
          ..color = AppTheme.primaryGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

        return CustomPaint(
          size: Size(w, h),
          painter: _QuadPainter(quad, detectionPaint, strokePaint),
          child: Stack(
            children: [
              Positioned(
                left: quad.left - 14,
                top: quad.top - 14,
                child: _cornerHandle(),
              ),
              Positioned(
                right: constraints.maxWidth - quad.right - 14,
                top: quad.top - 14,
                child: _cornerHandle(),
              ),
              Positioned(
                left: quad.left - 14,
                bottom: h - quad.bottom - 14,
                child: _cornerHandle(),
              ),
              Positioned(
                right: constraints.maxWidth - quad.right - 14,
                bottom: h - quad.bottom - 14,
                child: _cornerHandle(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cornerHandle() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.primaryGreen,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.4),
              blurRadius: 4,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final Rect quad;
  final Paint fillPaint;
  final Paint strokePaint;

  _QuadPainter(this.quad, this.fillPaint, this.strokePaint);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(quad.left, quad.top)
      ..lineTo(quad.right, quad.top)
      ..lineTo(quad.right, quad.bottom)
      ..lineTo(quad.left, quad.bottom)
      ..close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.quad != quad ||
      oldDelegate.fillPaint.color != fillPaint.color;
}
