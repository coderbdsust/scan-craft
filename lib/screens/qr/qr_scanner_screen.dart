import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_theme.dart';

/// Decodes QR codes and barcodes on-device and shows the raw value.
/// Links are never opened automatically.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _showingResult = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_showingResult || capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    final value = barcode.rawValue ?? barcode.displayValue;
    if (value == null || value.isEmpty) return;
    _showingResult = true;
    await _controller.stop();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                barcode.format.name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 240),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.slate50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: SingleChildScrollView(child: SelectableText(value)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: value));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                        }
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => SharePlus.instance.share(ShareParams(text: value)),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    _showingResult = false;
    if (mounted) await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('QR / Barcode', style: TextStyle(fontFamily: 'Space Grotesk')),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Scanner unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.slate400),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primaryGreen, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Point the camera at a QR code or barcode',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
