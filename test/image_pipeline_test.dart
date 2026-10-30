import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scancraft/models/scan_document.dart';
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

  test('result preview is cropped to the selected area', () {
    // Left half bright, right half dark; select only the left half.
    final src = img.Image(width: 400, height: 300);
    img.fill(src, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(src, x1: 0, y1: 0, x2: 199, y2: 299, color: img.ColorRgb8(240, 240, 240));
    final req = PipelineRequest(
      srcPathAsBytes: Uint8List.fromList(img.encodePng(src)),
      corners: const [0.05, 0.05, 0.45, 0.05, 0.45, 0.95, 0.05, 0.95],
      shadowRemoval: 0,
      contrast: 0,
      filterIndex: FilterMode.original,
      strokes: const [],
      deskew: false,
      rotateQuads: 0,
      maxOutDim: 900,
    );
    final r = resultPreviewIsolate(req.toMap());
    final out = img.decodeJpg(r['bytes'] as Uint8List)!;
    expect(out.width, closeTo(160, 3));
    expect(out.height, closeTo(270, 3));
    expect(r['ratio'] as double, closeTo(160 / 270, 0.02));
    // Every sampled pixel comes from the bright (selected) half.
    for (final x in [5, 80, 150]) {
      expect(out.getPixel(x, 135).luminance, greaterThan(200), reason: 'x=$x');
    }
  });

  PipelineRequest cropRequest(img.Image src, List<double> corners) => PipelineRequest(
        srcPathAsBytes: Uint8List.fromList(img.encodePng(src)),
        corners: corners,
        shadowRemoval: 0,
        contrast: 0,
        filterIndex: FilterMode.original,
        strokes: const [],
        deskew: false,
        rotateQuads: 0,
        maxOutDim: 2000,
      );

  test('off-center crop keeps exactly the selected subject', () {
    // Dark frame with a red marker at x 220..259, y 140..179.
    final src = img.Image(width: 400, height: 300);
    img.fill(src, color: img.ColorRgb8(20, 20, 20));
    img.fillRect(src, x1: 220, y1: 140, x2: 259, y2: 179, color: img.ColorRgb8(230, 30, 30));
    // Select x 200..300, y 120..220 -> marker sits at 20..59 inside the crop.
    final out = runPipeline(cropRequest(src, [
      200 / 400, 120 / 300, 300 / 400, 120 / 300, //
      300 / 400, 220 / 300, 200 / 400, 220 / 300,
    ]));
    expect(out.width, closeTo(100, 2));
    expect(out.height, closeTo(100, 2));
    bool isRed(img.Pixel p) => p.r > 180 && p.g < 80;
    expect(isRed(out.getPixel(40, 40)), isTrue, reason: 'marker inside crop');
    expect(isRed(out.getPixel(10, 10)), isFalse, reason: 'above-left of marker');
    expect(isRed(out.getPixel(80, 80)), isFalse, reason: 'below-right of marker');
  });

  test('perspective crop flattens a skewed page edge to edge', () {
    final quad = [
      [80, 40],
      [330, 70],
      [360, 280],
      [40, 260],
    ];
    final src = img.Image(width: 400, height: 300);
    img.fill(src, color: img.ColorRgb8(15, 15, 15));
    img.fillPolygon(src,
        vertices: [for (final p in quad) img.Point(p[0], p[1])], color: img.ColorRgb8(245, 245, 245));
    final out = runPipeline(cropRequest(src, [
      for (final p in quad) ...[p[0] / 400, p[1] / 300],
    ]));
    // Every part of the result is page, including just inside each corner.
    final w = out.width, h = out.height;
    for (final (x, y) in [
      (w * 0.05, h * 0.05),
      (w * 0.95, h * 0.05),
      (w * 0.95, h * 0.95),
      (w * 0.05, h * 0.95),
      (w * 0.5, h * 0.5),
    ]) {
      expect(out.getPixel(x.round(), y.round()).luminance, greaterThan(200), reason: 'at ($x, $y)');
    }
  });

  test('cropped pages are stretched to the page shape', () {
    final src = img.Image(width: 400, height: 300);
    img.fill(src, color: img.ColorRgb8(240, 240, 240));
    PipelineRequest req(List<double> corners) => PipelineRequest(
          srcPathAsBytes: Uint8List.fromList(img.encodePng(src)),
          corners: corners,
          shadowRemoval: 0,
          contrast: 0,
          filterIndex: FilterMode.original,
          strokes: const [],
          deskew: false,
          rotateQuads: 0,
          maxOutDim: 2000,
          pageAspect: PageShape.aspect(PageShape.a4, DocumentKind.document),
        );
    // Tall, nearly square crop (200 x 240) -> portrait A4, long side kept.
    final tall = runPipeline(req([0.25, 0.1, 0.75, 0.1, 0.75, 0.9, 0.25, 0.9]));
    expect(tall.height, closeTo(240, 2));
    expect(tall.height / tall.width, closeTo(297 / 210, 0.02));
    // Wide crop (320 x 150) -> landscape A4.
    final wide = runPipeline(req([0.1, 0.25, 0.9, 0.25, 0.9, 0.75, 0.1, 0.75]));
    expect(wide.width, closeTo(320, 2));
    expect(wide.width / wide.height, closeTo(297 / 210, 0.02));
    // "Original" keeps the crop's own shape.
    expect(PageShape.aspect(PageShape.original, DocumentKind.document), 0);
    expect(PageShape.aspect(PageShape.a4, DocumentKind.idCard), closeTo(1.585, 0.01));
  });

  test('full-frame selection keeps the whole image', () {
    final src = img.Image(width: 321, height: 123);
    final out = runPipeline(PipelineRequest(
      srcPathAsBytes: Uint8List.fromList(img.encodePng(src)),
      corners: const [0, 0, 1, 0, 1, 1, 0, 1],
      shadowRemoval: 0,
      contrast: 0,
      filterIndex: FilterMode.original,
      strokes: const [],
      deskew: false,
      rotateQuads: 0,
      maxOutDim: 2000,
    ));
    expect([out.width, out.height], [321, 123]);
  });

  test('live filter preview keeps geometry and applies the filter', () {
    final src = img.Image(width: 64, height: 48);
    img.fill(src, color: img.ColorRgb8(200, 40, 40));
    final bytes = filterPreviewIsolate({
      'bytes': Uint8List.fromList(img.encodeJpg(src)),
      'filter': FilterMode.grayscale,
      'shadow': 0.0,
      'contrast': 0.0,
    });
    final out = img.decodeJpg(bytes)!;
    expect([out.width, out.height], [64, 48]);
    final p = out.getPixel(32, 24);
    expect((p.r - p.g).abs(), lessThan(6)); // no longer red
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
    // A tiny 120x160 px page still fills a full A4 sheet (long side 841.7 pt).
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)').firstMatch(text)!;
    expect(double.parse(box.group(2)!), closeTo(11.69 * 72, 1));
    expect(double.parse(box.group(1)!), closeTo(11.69 * 72 * 120 / 160, 1));

    final jpgs = await ExportService(store).exportJpgs(doc);
    expect(jpgs, hasLength(2));
    expect(store.exportsBytes, greaterThan(0));
  });
}
