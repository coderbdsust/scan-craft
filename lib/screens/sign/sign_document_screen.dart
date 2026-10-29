import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/document_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pipeline.dart';
import '../../widgets/dialogs.dart';

/// Draw a signature, place it on a page, and burn it into the page image.
class SignDocumentScreen extends StatefulWidget {
  const SignDocumentScreen({super.key});

  @override
  State<SignDocumentScreen> createState() => _SignDocumentScreenState();
}

class _SignDocumentScreenState extends State<SignDocumentScreen> {
  final store = DocumentStore.instance;
  String? _docId;
  int _pageIndex = 0;
  double? _pageRatio;

  Uint8List? _signaturePng;
  double _sigAspect = 3; // width / height of the signature image
  // Signature box: top-left and width, normalized to the page.
  Offset _sigPos = const Offset(0.55, 0.8);
  double _sigWidth = 0.35;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_docId == null) {
      _docId = ModalRoute.of(context)?.settings.arguments as String?;
      final doc = _docId == null ? null : store.byId(_docId!);
      if (doc != null) {
        _pageIndex = doc.pageCount - 1; // signatures usually go on the last page
        _loadRatio();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _drawSignature());
    }
  }

  Future<void> _loadRatio() async {
    final doc = store.byId(_docId!);
    if (doc == null) return;
    final bytes = await store.pageFile(doc, _pageIndex).readAsBytes();
    final image = await decodeImageFromList(bytes);
    if (mounted) setState(() => _pageRatio = image.width / image.height);
    image.dispose();
  }

  Future<void> _drawSignature() async {
    final result = await showModalBottomSheet<(Uint8List, double)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SignaturePadSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        _signaturePng = result.$1;
        _sigAspect = result.$2;
      });
    }
  }

  Future<void> _apply() async {
    final doc = store.byId(_docId!);
    final sig = _signaturePng;
    if (doc == null || sig == null) return;
    setState(() => _saving = true);
    try {
      final pageBytes = await store.pageFile(doc, _pageIndex).readAsBytes();
      final stamped = await compute(stampSignatureIsolate, {
        'page': pageBytes,
        'signature': sig,
        'rect': [_sigPos.dx, _sigPos.dy, _sigWidth],
      });
      await store.tempDir.create(recursive: true);
      final out = File('${store.tempDir.path}/signed_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await out.writeAsBytes(stamped);
      await store.replacePage(doc.id, _pageIndex, out);
      await out.delete();
      await store.markSigned(doc.id);
      if (!mounted) return;
      showSnack(context, 'Signature added to page ${_pageIndex + 1}');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not sign: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _docId == null ? null : store.byId(_docId!);
    if (doc == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Document not found.')));
    }
    return Scaffold(
      backgroundColor: AppTheme.slate100,
      appBar: AppBar(
        title: const Text('Sign Document', style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _signaturePng == null || _saving ? null : _apply,
            child: const Text('Apply'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (doc.pageCount > 1)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                itemCount: doc.pageCount,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ChoiceChip(
                  label: Text('Page ${i + 1}'),
                  selected: i == _pageIndex,
                  onSelected: (_) {
                    setState(() {
                      _pageIndex = i;
                      _pageRatio = null;
                    });
                    _loadRatio();
                  },
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _pageRatio == null
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                        aspectRatio: _pageRatio!,
                        child: LayoutBuilder(builder: (context, c) {
                          final w = c.maxWidth, h = c.maxHeight;
                          final sigW = _sigWidth * w;
                          final sigH = sigW / _sigAspect;
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)],
                                  ),
                                  child: Image.file(store.pageFile(doc, _pageIndex), fit: BoxFit.fill),
                                ),
                              ),
                              if (_signaturePng != null)
                                Positioned(
                                  left: _sigPos.dx * w,
                                  top: _sigPos.dy * h,
                                  child: GestureDetector(
                                    onPanUpdate: (d) => setState(() {
                                      _sigPos = Offset(
                                        (_sigPos.dx + d.delta.dx / w).clamp(0.0, 1 - _sigWidth),
                                        (_sigPos.dy + d.delta.dy / h).clamp(0.0, 1 - sigH / h),
                                      );
                                    }),
                                    child: Container(
                                      width: sigW,
                                      height: sigH,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppTheme.primaryGreen, width: 1.5),
                                        color: AppTheme.primaryGreen.withValues(alpha: 0.05),
                                      ),
                                      child: Image.memory(_signaturePng!, fit: BoxFit.fill),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }),
                      ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_signaturePng != null)
                    Row(
                      children: [
                        const Icon(Icons.photo_size_select_large, size: 18, color: AppTheme.slate500),
                        Expanded(
                          child: Slider(
                            value: _sigWidth,
                            min: 0.12,
                            max: 0.8,
                            onChanged: (v) => setState(() {
                              _sigWidth = v;
                              _sigPos = Offset(_sigPos.dx.clamp(0.0, 1 - v), _sigPos.dy);
                            }),
                          ),
                        ),
                      ],
                    ),
                  Text(
                    _signaturePng == null ? 'Draw your signature to place it.' : 'Drag the signature into place, then tap Apply.',
                    style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _drawSignature,
                    icon: const Icon(Icons.draw),
                    label: Text(_signaturePng == null ? 'Draw Signature' : 'Redraw Signature'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet with a finger-drawing pad. Pops with (pngBytes, aspectRatio).
class _SignaturePadSheet extends StatefulWidget {
  const _SignaturePadSheet();

  @override
  State<_SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<_SignaturePadSheet> {
  final List<List<Offset>> _strokes = [];
  Size _padSize = Size.zero;

  Future<void> _done() async {
    if (_strokes.every((s) => s.isEmpty)) return;
    // Crop to the drawn area so the stamp has no empty margins.
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final s in _strokes) {
      for (final p in s) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    const pad = 8.0, scale = 3.0;
    final bounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    _SignaturePainter(_strokes).paint(canvas, _padSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage((bounds.width * scale).ceil(), (bounds.height * scale).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null || !mounted) return;
    Navigator.pop(context, (data.buffer.asUint8List(), bounds.width / bounds.height));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sign below',
                style: TextStyle(fontFamily: 'Space Grotesk', fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate300),
              ),
              child: LayoutBuilder(builder: (context, c) {
                _padSize = c.biggest;
                return GestureDetector(
                  onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                  onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                  child: CustomPaint(painter: _SignaturePainter(_strokes), size: Size.infinite),
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(_strokes.clear),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _strokes.isEmpty ? null : _done,
                    child: const Text('Use Signature'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0B1F4D)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
