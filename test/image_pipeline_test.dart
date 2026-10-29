import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scancraft/services/document_store.dart';
import 'package:scancraft/services/export_service.dart';
import 'package:scancraft/utils/image_pipeline.dart';

/// Dark background with a bright, slightly rotated quadrilateral "page".
img.Image _syntheticScan(List<List<int>> quad, {int w = 400, int h = 600}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(40, 40, 45));
  img.fillPolygon(
    image,
    vertices: [for (final p in quad) img.Point(p[0], p[1])],
    color: img.ColorRgb8(235, 235, 230),
  );
  return image;
}

void main() {
  test('detects the corners of a page on a dark background', () {
    final quad = [
      [60, 80],
      [340, 100],
      [330, 520],
      [70, 500],
    ];
    final corners = detectDocumentCorners(_syntheticScan(quad));
    expect(corners, isNotNull);
    for (var i = 0; i < 4; i++) {
      expect(corners![i * 2] * 400, closeTo(quad[i][0], 12), reason: 'x of corner $i');
      expect(corners[i * 2 + 1] * 600, closeTo(quad[i][1], 12), reason: 'y of corner $i');
    }
  });

  test('returns null when there is no page', () {
    final blank = img.Image(width: 300, height: 400);
    img.fill(blank, color: img.ColorRgb8(128, 128, 128));
    expect(detectDocumentCorners(blank), isNull);
  });

  test('orderCorners sorts arbitrary points into tl, tr, br, bl', () {
    final ordered = orderCorners([
      [0.9, 0.9],
      [0.1, 0.1],
      [0.1, 0.9],
      [0.9, 0.1],
    ]);
    expect(ordered, [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);
  });

  test('perspective crop outputs roughly the page size', () {
    final src = _syntheticScan([
      [50, 50],
      [350, 50],
      [350, 550],
      [50, 550],
    ]);
    final req = PipelineRequest(
      srcPathAsBytes: Uint8List.fromList(img.encodeJpg(src)),
      corners: [50 / 400, 50 / 600, 350 / 400, 50 / 600, 350 / 400, 550 / 600, 50 / 400, 550 / 600],
      shadowRemoval: 0,
      contrast: 0,
      filterIndex: FilterMode.original,
      strokes: const [],
      deskew: false,
      rotateQuads: 0,
      maxOutDim: 2000,
    );
    final out = runPipeline(req);
    expect(out.width, closeTo(300, 3));
    expect(out.height, closeTo(500, 3));
    // Center of the cropped page is the bright page colour.
    expect(out.getPixel(150, 250).luminance, greaterThan(200));
  });

  test('book spreads split into two halves', () {
    final spread = img.Image(width: 800, height: 500);
    final halves = splitSpreadIsolate(Uint8List.fromList(img.encodeJpg(spread)));
    expect(halves, hasLength(2));
    expect(img.decodeJpg(halves[0])!.width, 400);
  });

  test('PDF export writes one page per scan', () async {
    final root = await Directory.systemTemp.createTemp('scancraft_export_');
    addTearDown(() => root.delete(recursive: true));
    final store = DocumentStore.instance;
    await store.init(root: root);
    final page = File('${root.path}/p.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 120, height: 160)));
    final doc = await store.createDocument([page, page], name: 'Lease: draft/2');

    final pdf = await ExportService(store).exportPdf(doc);
    expect(pdf.path, endsWith('Lease_ draft_2.pdf'));
    final text = String.fromCharCodes(pdf.readAsBytesSync());
    expect(text.startsWith('%PDF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);

    final jpgs = await ExportService(store).exportJpgs(doc);
    expect(jpgs, hasLength(2));
    expect(store.exportsBytes, greaterThan(0));
  });
}
