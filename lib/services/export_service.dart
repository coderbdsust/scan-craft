import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/scan_document.dart';
import '../utils/image_pipeline.dart';
import 'document_store.dart';

/// Builds PDF / JPG exports of a document on-device and hands them to the
/// system share sheet (where the user can save to Files, Drive, email, ...).
class ExportService {
  ExportService(this.store);

  final DocumentStore store;

  /// Long side of the physical page used to size exports, in inches:
  /// ID-1 card size for ID cards, otherwise the paper chosen in Settings.
  double _longEdgeInches(ScanDocument doc) {
    if (doc.kind == DocumentKind.idCard) return 3.37;
    return store.settings.pageShape == PageShape.letter ? 11.0 : 11.69;
  }

  Future<List<Map<String, dynamic>>> _renderPages(ScanDocument doc) async {
    final rendered = <Map<String, dynamic>>[];
    for (final file in store.pageFiles(doc)) {
      final bytes = await file.readAsBytes();
      rendered.add(await compute(renderExportPageIsolate, {
        'bytes': bytes,
        'dpi': doc.dpi,
        'profile': doc.colorProfile,
        'longEdgeInches': _longEdgeInches(doc),
      }));
    }
    return rendered;
  }

  static String safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\-. ]+'), '_').trim();
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  Future<File> exportPdf(ScanDocument doc) async {
    final pages = await _renderPages(doc);
    final pdf = pw.Document(title: doc.name, creator: 'ScanCraft');
    for (final p in pages) {
      final w = (p['width'] as int).toDouble();
      final h = (p['height'] as int).toDouble();
      // Every page fills a real sheet: its long side is the paper's long side,
      // whatever the pixel count (DPI only controls image quality).
      final pointsPerPixel = _longEdgeInches(doc) * 72 / (w > h ? w : h);
      final format = PdfPageFormat(w * pointsPerPixel, h * pointsPerPixel);
      final image = pw.MemoryImage(p['bytes'] as Uint8List);
      pdf.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
    }
    await store.exportsDir.create(recursive: true);
    final out = File('${store.exportsDir.path}/${safeFileName(doc.name)}.pdf');
    await out.writeAsBytes(await pdf.save(), flush: true);
    store.exportsChanged();
    return out;
  }

  Future<List<File>> exportJpgs(ScanDocument doc) async {
    final pages = await _renderPages(doc);
    await store.exportsDir.create(recursive: true);
    final base = safeFileName(doc.name);
    final files = <File>[];
    for (var i = 0; i < pages.length; i++) {
      final suffix = pages.length == 1 ? '' : '_p${i + 1}';
      final out = File('${store.exportsDir.path}/$base$suffix.jpg');
      await out.writeAsBytes(pages[i]['bytes'] as Uint8List, flush: true);
      files.add(out);
    }
    store.exportsChanged();
    return files;
  }

  Future<void> share(List<File> files, {required String subject}) async {
    await SharePlus.instance.share(ShareParams(
      files: [for (final f in files) XFile(f.path)],
      subject: subject,
    ));
  }
}
