import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Index into the filter list used by the editor UI.
class FilterMode {
  static const int original = 0;
  static const int magicColor = 1;
  static const int cleanWhite = 2;
  static const int sharpBW = 3;
  static const int grayscale = 4;
  static const int fingerEraser = 5; // not a colour filter, it's a mode
}

/// Serializable request for a background isolate.
class PipelineRequest {
  PipelineRequest({
    required this.srcPathAsBytes,
    required this.corners, // tl,tr,br,bl normalized 0..1 of source frame
    required this.shadowRemoval, // 0..1
    required this.contrast, // 0..1
    required this.filterIndex,
    required this.strokes, // each = [x,y,radius] normalized to the SOURCE frame 0..1
    required this.deskew,
    required this.rotateQuads, // extra 90-degree turns after deskew
    required this.maxOutDim,
  });

  final Uint8List srcPathAsBytes;
  final List<double> corners; // 8 doubles
  final double shadowRemoval;
  final double contrast;
  final int filterIndex;
  final List<List<double>> strokes;
  final bool deskew;
  final int rotateQuads;
  final int maxOutDim;

  Map<String, dynamic> toMap() => {
        'bytes': srcPathAsBytes,
        'corners': corners,
        'shadow': shadowRemoval,
        'contrast': contrast,
        'filter': filterIndex,
        'strokes': strokes,
        'deskew': deskew,
        'rotateQuads': rotateQuads,
        'maxOutDim': maxOutDim,
      };

  static PipelineRequest fromMap(Map<String, dynamic> m) => PipelineRequest(
        srcPathAsBytes: m['bytes'] as Uint8List,
        corners: (m['corners'] as List).cast<double>(),
        shadowRemoval: m['shadow'] as double,
        contrast: m['contrast'] as double,
        filterIndex: m['filter'] as int,
        strokes: (m['strokes'] as List).map((e) => (e as List).cast<double>()).toList(),
        deskew: m['deskew'] as bool,
        rotateQuads: m['rotateQuads'] as int,
        maxOutDim: m['maxOutDim'] as int,
      );
}

/// Runs the full pipeline; designed to be called inside compute().
img.Image runPipeline(PipelineRequest req) {
  img.Image src = img.decodeImage(req.srcPathAsBytes)!;
  src = img.bakeOrientation(src);

  // Downscale source for performance if huge.
  final maxDim = math.max(src.width, src.height);
  if (maxDim > req.maxOutDim) {
    final scale = req.maxOutDim / maxDim;
    src = img.copyResize(src, width: (src.width * scale).round());
  }

  final w = src.width.toDouble();
  final h = src.height.toDouble();

  // 0. Finger eraser strokes, painted on the source frame where the user
  // tapped them (before the perspective warp moves pixels around).
  if (req.strokes.isNotEmpty) {
    src = img.Image.from(src);
    for (final s in req.strokes) {
      _paintWhiteCircle(src, (s[0] * w).round(), (s[1] * h).round(),
          (s[2] * math.max(w, h)).round().clamp(4, 400));
    }
  }

  // 1. Perspective crop from normalized corners.
  final c = req.corners;
  final tl = _Pt(c[0] * w, c[1] * h);
  final tr = _Pt(c[2] * w, c[3] * h);
  final br = _Pt(c[4] * w, c[5] * h);
  final bl = _Pt(c[6] * w, c[7] * h);

  img.Image out;
  if (_isFullFrame(c)) {
    out = img.Image.from(src); // nothing to crop
  } else {
    final outW = _quadAvgWidth(tl, tr, br, bl).round().clamp(16, 8192);
    final outH = _quadAvgHeight(tl, tr, br, bl).round().clamp(16, 8192);
    final H = _homographyToSource(tl, tr, br, bl, outW, outH);
    out = _warpBilinear(src, outW, outH, H);
  }

  // 2. Auto-deskew (estimate on grayscale of warped page).
  double angleDeg = 0;
  if (req.deskew) {
    angleDeg = _estimateSkewDegrees(out, candidates: const [
      -3.5, -3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]);
    if (angleDeg != 0) {
      out = _rotateBilinear(out, angleDeg, fillWhite: true);
    }
  }

  // 3. Extra 90° rotations from the Rotate button.
  if (req.rotateQuads != 0) {
    out = img.copyRotate(out, angle: req.rotateQuads * 90);
  }

  // 4. Shadow removal (divide-by-background illumination correction).
  if (req.shadowRemoval > 0.01) {
    out = _removeShadows(out, req.shadowRemoval);
  }

  // 5. Colour filter.
  _applyFilter(out, req.filterIndex);

  // 6. Dynamic contrast.
  if (req.contrast > 0.01) {
    _adjustContrast(out, req.contrast);
  }

  return out;
}

bool _isFullFrame(List<double> c) {
  const full = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
  for (var i = 0; i < 8; i++) {
    if ((c[i] - full[i]).abs() > 0.002) return false;
  }
  return true;
}

/// Runs pipeline + JPEG encoding; intended for `compute`.
Uint8List processAndEncodeIsolate(PipelineRequest req) {
  final image = runPipeline(req);
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

// ---------------------------------------------------------------------------
// Geometry & warp helpers
// ---------------------------------------------------------------------------

class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
}

double _dist(_Pt a, _Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

double _quadAvgWidth(_Pt tl, _Pt tr, _Pt br, _Pt bl) =>
    (_dist(tl, tr) + _dist(br, bl)) / 2;

double _quadAvgHeight(_Pt tl, _Pt tr, _Pt br, _Pt bl) =>
    (_dist(tl, bl) + _dist(tr, br)) / 2;

/// Homography mapping OUTPUT pixel -> SOURCE pixel so we can inverse-sample.
/// Solves the 8-unknown DLT system for the 4 corner pairs.
List<double> _homographyToSource(_Pt tl, _Pt tr, _Pt br, _Pt bl, int outW, int outH) {
  final dst = [_Pt(0, 0), _Pt(outW - 1.0, 0), _Pt(outW - 1.0, outH - 1.0), _Pt(0, outH - 1.0)];
  final src = [tl, tr, br, bl];
  final A = List<double>.filled(8 * 8, 0);
  final b = List<double>.filled(8, 0);
  var row = 0;
  for (var i = 0; i < 4; i++) {
    // Inputs (X, Y) are output pixels, results (u, v) are source pixels, so
    // the solved matrix maps OUTPUT -> SOURCE as _warpBilinear expects.
    final X = dst[i].x, Y = dst[i].y, u = src[i].x, v = src[i].y;
    A[row * 8 + 0] = X; A[row * 8 + 1] = Y; A[row * 8 + 2] = 1;
    A[row * 8 + 6] = -u * X; A[row * 8 + 7] = -u * Y; b[row] = u;
    row++;
    A[row * 8 + 3] = X; A[row * 8 + 4] = Y; A[row * 8 + 5] = 1;
    A[row * 8 + 6] = -v * X; A[row * 8 + 7] = -v * Y; b[row] = v;
    row++;
  }
  final hv = _solve8(A, b);
  return hv;
}

/// Gaussian elimination with partial pivoting (8x8).
List<double> _solve8(List<double> A, List<double> B) {
  final n = 8;
  final m = List<List<double>>.generate(n, (i) => List<double>.generate(n + 1, (j) {
        return j == n ? B[i] : A[i * n + j];
      }));
  for (var col = 0; col < n; col++) {
    var piv = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[piv][col].abs()) piv = r;
    }
    final t = m[col]; m[col] = m[piv]; m[piv] = t;
    final d = m[col][col];
    if (d == 0) continue;
    for (var j = col; j <= n; j++) {
      m[col][j] /= d;
    }
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      final f = m[r][col];
      if (f == 0) continue;
      for (var j = col; j <= n; j++) {
        m[r][j] -= f * m[col][j];
      }
    }
  }
  return List<double>.generate(n, (i) => m[i][n]);
}

img.Image _warpBilinear(img.Image src, int outW, int outH, List<double> hv) {
  final out = img.Image(width: outW, height: outH, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(255, 255, 255, 255));
  final sw = src.width - 1.0, sh = src.height - 1.0;
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final den = hv[6] * x + hv[7] * y + 1;
      var sx = (hv[0] * x + hv[1] * y + hv[2]) / den;
      var sy = (hv[3] * x + hv[4] * y + hv[5]) / den;
      if (sx < -2 || sy < -2 || sx > src.width + 1 || sy > src.height + 1) continue;
      sx = sx.clamp(0, sw);
      sy = sy.clamp(0, sh);
      final x0 = sx.floor(), y0 = sy.floor();
      final x1 = math.min(x0 + 1, src.width - 1);
      final y1 = math.min(y0 + 1, src.height - 1);
      final fx = sx - x0, fy = sy - y0;
      final p00 = src.getPixel(x0, y0);
      final p10 = src.getPixel(x1, y0);
      final p01 = src.getPixel(x0, y1);
      final p11 = src.getPixel(x1, y1);
      num r = p00.r + (p10.r - p00.r) * fx + (p01.r - p00.r) * fy + (p00.r - p10.r - p01.r + p11.r) * fx * fy;
      num g = p00.g + (p10.g - p00.g) * fx + (p01.g - p00.g) * fy + (p00.g - p10.g - p01.g + p11.g) * fx * fy;
      num bch = p00.b + (p10.b - p00.b) * fx + (p01.b - p00.b) * fy + (p00.b - p10.b - p01.b + p11.b) * fx * fy;
      out.setPixelRgba(x, y, _clamp255(r), _clamp255(g), _clamp255(bch), 255);
    }
  }
  return out;
}

img.Image _rotateBilinear(img.Image src, double deg, {bool fillWhite = false}) {
  final a = deg * math.pi / 180.0;
  final s = math.sin(a), c = math.cos(a);
  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(255, 255, 255, 255));
  final cx = (src.width - 1) / 2.0, cy = (src.height - 1) / 2.0;
  final sw = src.width - 1.0, sh = src.height - 1.0;
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final dx = x - cx, dy = y - cy;
      // inverse rotation into source space
      final sx = c * dx + s * dy + cx;
      final sy = -s * dx + c * dy + cy;
      if (sx < 0 || sy < 0 || sx > sw || sy > sh) continue;
      final x0 = sx.floor(), y0 = sy.floor();
      final x1 = math.min(x0 + 1, src.width - 1);
      final y1 = math.min(y0 + 1, src.height - 1);
      final fx = sx - x0, fy = sy - y0;
      final p00 = src.getPixel(x0, y0);
      final p10 = src.getPixel(x1, y0);
      final p01 = src.getPixel(x0, y1);
      final p11 = src.getPixel(x1, y1);
      num r = p00.r + (p10.r - p00.r) * fx + (p01.r - p00.r) * fy + (p00.r - p10.r - p01.r + p11.r) * fx * fy;
      num g = p00.g + (p10.g - p00.g) * fx + (p01.g - p00.g) * fy + (p00.g - p10.g - p01.g + p11.g) * fx * fy;
      num b = p00.b + (p10.b - p00.b) * fx + (p01.b - p00.b) * fy + (p00.b - p10.b - p01.b + p11.b) * fx * fy;
      out.setPixelRgba(x, y, _clamp255(r), _clamp255(g), _clamp255(b), 255);
    }
  }
  return out;
}

int _clamp255(num v) => v.toInt().clamp(0, 255);

// ---------------------------------------------------------------------------
// Enhancements
// ---------------------------------------------------------------------------

/// Illumination removal: divide pixel by heavy local background estimate.
img.Image _removeShadows(img.Image src, double k) {
  final gw = math.max(32, src.width ~/ 8);
  final gh = math.max(32, src.height ~/ 8);
  var gray = img.grayscale(src);
  gray = img.copyResize(gray, width: gw, height: gh);
  gray = img.gaussianBlur(gray, radius: math.max(2, gw ~/ 12));
  final bg = img.copyResize(gray, width: src.width, height: src.height, interpolation: img.Interpolation.linear);

  final out = img.Image.from(src); // copy
  const strength = 3.0; // strength inside the "divide" formula
  for (final p in out) {
    final bp = bg.getPixel(p.x, p.y).luminance / 255.0;
    final bgNorm = math.max(0.25, bp);
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    double adj(num v) {
      final corrected = ((v + strength) / (bgNorm * 255 + strength)) * 255.0;
      return v + k * (corrected - v);
    }
    p.r = _clamp255(adj(r)).toInt();
    p.g = _clamp255(adj(g)).toInt();
    p.b = _clamp255(adj(b)).toInt();
  }
  return out;
}

void _applyFilter(img.Image image, int filterIndex) {
  switch (filterIndex) {
    case FilterMode.magicColor:
      _applyLevels(image, loP: 0.005, hiP: 0.985);
      img.adjustColor(image, saturation: 1.28, contrast: 1.10, gamma: 0.96);
      break;
    case FilterMode.cleanWhite:
      _applyLevels(image, loP: 0.01, hiP: 0.955);
      img.adjustColor(image, saturation: 1.05, gamma: 0.92, brightness: 3);
      break;
    case FilterMode.sharpBW:
      img.grayscale(image);
      _thresholdContrast(image, blackPoint: 110, whitePoint: 175);
      break;
    case FilterMode.grayscale:
      img.grayscale(image);
      break;
  }
}

/// Per-channel contrast stretch from [loP]..[hiP] histogram percentiles.
void _applyLevels(img.Image image, {double loP = 0.005, double hiP = 0.985}) {
  final total = image.width * image.height;
  final loCut = (total * loP).floor();
  final hiCut = (total * hiP).floor();
  for (var channel = 0; channel < 3; channel++) {
    final hist = List<int>.filled(256, 0);
    for (final p in image) {
      hist[_lumChannel(p, channel)]++;
    }
    var lo = 0, acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc > loCut) { lo = v; break; }
    }
    acc = 0;
    var hi = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc > hiCut) { hi = v; break; }
    }
    hi = math.max(hi, lo + 16);
    final lut = List<int>.generate(256, (v) {
      if (v <= lo) return 0;
      if (v >= hi) return 255;
      return ((v - lo) * 255.0 / (hi - lo)).round();
    });
    for (final p in image) {
      switch (channel) {
        case 0: p.r = lut[p.r.toInt()]; break;
        case 1: p.g = lut[p.g.toInt()]; break;
        default: p.b = lut[p.b.toInt()];
      }
    }
  }
}

int _lumChannel(img.Pixel p, int channel) {
  switch (channel) {
    case 0: return p.r.toInt();
    case 1: return p.g.toInt();
    default: return p.b.toInt();
  }
}

/// Hard three-point curve for B&W document scans.
void _thresholdContrast(img.Image image, {required int blackPoint, required int whitePoint}) {
  final lut = List<int>.generate(256, (v) {
    if (v <= blackPoint) return 0;
    if (v >= whitePoint) return 255;
    return ((v - blackPoint) * 255.0 / (whitePoint - blackPoint)).round();
  });
  for (final p in image) {
    p.r = lut[p.r.toInt()];
    p.g = lut[p.g.toInt()];
    p.b = lut[p.b.toInt()];
  }
}

void _adjustContrast(img.Image image, double c) {
  final factor = 1.0 + c * 0.55;
  final lut = List<int>.generate(256, (v) {
    final x = (v - 128) * factor + 128;
    return x.round().clamp(0, 255);
  });
  for (final p in image) {
    p.r = lut[p.r.toInt()];
    p.g = lut[p.g.toInt()];
    p.b = lut[p.b.toInt()];
  }
}

void _paintWhiteCircle(img.Image image, int cx, int cy, int radius) {
  final r2 = radius * radius;
  for (var y = -radius; y <= radius; y++) {
    final py = cy + y;
    if (py < 0 || py >= image.height) continue;
    final w = math.sqrt((r2 - y * y).clamp(0, r2)).floor();
    for (var x = -w; x <= w; x++) {
      final px = cx + x;
      if (px < 0 || px >= image.width) continue;
      image.setPixelRgba(px, py, 255, 255, 255, 255);
    }
  }
}

// ---------------------------------------------------------------------------
// Editor preview + export rendering (both run inside compute)
// ---------------------------------------------------------------------------

/// Decodes a page, returns a downscaled JPEG preview, its aspect ratio and the
/// detected document corners (or null when no page outline was found).
Map<String, dynamic> loadPreviewIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image format');
  final baked = img.bakeOrientation(decoded);
  img.Image preview = baked;
  final maxDim = math.max(baked.width, baked.height);
  if (maxDim > 1400) {
    preview = img.copyResize(baked, width: (baked.width * 1400 / maxDim).round());
  }
  // Smaller copy used for live filter / result previews.
  final work = maxDim > 900
      ? img.copyResize(baked, width: (baked.width * 900 / maxDim).round())
      : baked;
  return {
    'preview': Uint8List.fromList(img.encodeJpg(preview, quality: 90)),
    'work': Uint8List.fromList(img.encodeJpg(work, quality: 90)),
    'ratio': preview.width / preview.height,
    'corners': detectDocumentCorners(preview),
  };
}

/// Applies only the tone steps (shadow removal, filter, contrast) to a preview
/// so the editor can show them live without changing the image geometry.
Uint8List filterPreviewIsolate(Map<String, dynamic> m) {
  final image = img.decodeImage(m['bytes'] as Uint8List)!;
  final shadow = m['shadow'] as double;
  final contrast = m['contrast'] as double;
  var out = image;
  if (shadow > 0.01) out = _removeShadows(out, shadow);
  _applyFilter(out, m['filter'] as int);
  if (contrast > 0.01) _adjustContrast(out, contrast);
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

/// Full pipeline on a preview-sized image: what Save will produce.
/// Returns {bytes, ratio}.
Map<String, dynamic> resultPreviewIsolate(Map<String, dynamic> m) {
  final out = runPipeline(PipelineRequest.fromMap(m));
  return {
    'bytes': Uint8List.fromList(img.encodeJpg(out, quality: 85)),
    'ratio': out.width / out.height,
  };
}

/// Re-encodes a page for export: applies [colorProfile] ('color', 'gray',
/// 'bw') and limits the long edge to what [dpi] needs for a page whose long
/// side is [longEdgeInches]. Returns {bytes, width, height}.
Map<String, dynamic> renderExportPageIsolate(Map<String, dynamic> m) {
  final bytes = m['bytes'] as Uint8List;
  final dpi = m['dpi'] as int;
  final profile = m['profile'] as String;
  final longEdgeInches = m['longEdgeInches'] as double;
  var image = img.bakeOrientation(img.decodeImage(bytes)!);
  final maxPx = (longEdgeInches * dpi).round();
  final longEdge = math.max(image.width, image.height);
  if (longEdge > maxPx) {
    final scale = maxPx / longEdge;
    image = img.copyResize(image,
        width: (image.width * scale).round(), height: (image.height * scale).round());
  }
  if (profile == 'gray') {
    _applyFilter(image, FilterMode.grayscale);
  } else if (profile == 'bw') {
    _applyFilter(image, FilterMode.sharpBW);
  }
  final quality = dpi >= 600 ? 95 : (dpi >= 300 ? 88 : 72);
  return {
    'bytes': Uint8List.fromList(img.encodeJpg(image, quality: quality)),
    'width': image.width,
    'height': image.height,
  };
}

/// Splits a two-page book spread into left and right JPEG halves.
List<Uint8List> splitSpreadIsolate(Uint8List bytes) {
  final image = img.bakeOrientation(img.decodeImage(bytes)!);
  // A spread held in portrait is rotated so the spine runs vertically.
  final spread = image.height > image.width ? img.copyRotate(image, angle: -90) : image;
  final half = spread.width ~/ 2;
  final left = img.copyCrop(spread, x: 0, y: 0, width: half, height: spread.height);
  final right = img.copyCrop(spread, x: half, y: 0, width: spread.width - half, height: spread.height);
  return [
    Uint8List.fromList(img.encodeJpg(left, quality: 92)),
    Uint8List.fromList(img.encodeJpg(right, quality: 92)),
  ];
}

/// Stamps a transparent PNG signature onto a page at a normalized rectangle
/// (x, y, width as fractions of the page width/height). Returns a JPEG.
Uint8List stampSignatureIsolate(Map<String, dynamic> m) {
  final page = img.bakeOrientation(img.decodeImage(m['page'] as Uint8List)!);
  final sig = img.decodePng(m['signature'] as Uint8List)!;
  final rect = (m['rect'] as List).cast<double>();
  final dstW = (rect[2] * page.width).round().clamp(8, page.width);
  final dstH = (dstW * sig.height / sig.width).round().clamp(4, page.height);
  img.compositeImage(
    page,
    sig,
    dstX: (rect[0] * page.width).round(),
    dstY: (rect[1] * page.height).round(),
    dstW: dstW,
    dstH: dstH,
  );
  return Uint8List.fromList(img.encodeJpg(page, quality: 92));
}

// ---------------------------------------------------------------------------
// Document edge detection
// ---------------------------------------------------------------------------

/// Finds a document outline in [image]. Returns 8 normalized doubles
/// (tl, tr, br, bl) or null when nothing page-like was found.
List<double>? detectDocumentCorners(img.Image image) {
  const target = 160;
  final scale = target / math.max(image.width, image.height);
  final small = scale < 1
      ? img.copyResize(image,
          width: math.max(1, (image.width * scale).round()),
          height: math.max(1, (image.height * scale).round()))
      : image;
  final w = small.width, h = small.height;
  final lum = Uint8List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      lum[i++] = small.getPixel(x, y).luminance.toInt();
    }
  }
  return detectQuadInLuminance(lum, w, h);
}

/// Edge detection on a raw luminance buffer (row-major, [w] x [h]). Used both
/// for still photos and for live camera frames.
///
/// Approach: blur, Otsu-threshold, keep the largest bright region that does
/// not cover the whole frame, then take its extreme points as corners.
List<double>? detectQuadInLuminance(Uint8List lum, int w, int h) {
  if (w < 8 || h < 8) return null;
  final blurred = _boxBlur3(lum, w, h);
  final t = _otsuThreshold(blurred);
  final mask = Uint8List(w * h);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = blurred[i] > t ? 1 : 0;
  }

  // Largest 4-connected bright component.
  final labels = Int32List(w * h);
  final stack = <int>[];
  var bestLabel = 0, bestSize = 0, label = 0;
  var bestTouchesAll = false;
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || labels[start] != 0) continue;
    label++;
    var size = 0;
    var touches = 0; // bitmask: 1 left, 2 right, 4 top, 8 bottom
    labels[start] = label;
    stack.add(start);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      size++;
      final x = p % w, y = p ~/ w;
      if (x == 0) touches |= 1;
      if (x == w - 1) touches |= 2;
      if (y == 0) touches |= 4;
      if (y == h - 1) touches |= 8;
      void visit(int q) {
        if (mask[q] == 1 && labels[q] == 0) {
          labels[q] = label;
          stack.add(q);
        }
      }

      if (x > 0) visit(p - 1);
      if (x < w - 1) visit(p + 1);
      if (y > 0) visit(p - w);
      if (y < h - 1) visit(p + w);
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = label;
      bestTouchesAll = touches == 15;
    }
  }
  final total = w * h;
  if (bestLabel == 0 || bestSize < total * 0.12 || bestSize > total * 0.97) return null;
  if (bestTouchesAll && bestSize > total * 0.85) return null; // bright background, not a page

  // Extreme points: tl = min(x+y), br = max(x+y), tr = max(x-y), bl = min(x-y).
  var tl = 0, br = 0, tr = 0, bl = 0;
  var minS = 1 << 30, maxS = -(1 << 30), maxD = -(1 << 30), minD = 1 << 30;
  for (var p = 0; p < labels.length; p++) {
    if (labels[p] != bestLabel) continue;
    final x = p % w, y = p ~/ w;
    final s = x + y, d = x - y;
    if (s < minS) { minS = s; tl = p; }
    if (s > maxS) { maxS = s; br = p; }
    if (d > maxD) { maxD = d; tr = p; }
    if (d < minD) { minD = d; bl = p; }
  }
  final pts = [tl, tr, br, bl]
      .map((p) => [((p % w) + 0.5) / w, ((p ~/ w) + 0.5) / h])
      .toList();

  // The region should fill most of its own outline (i.e. be roughly a quad).
  final quadArea = _polygonArea(pts) * total;
  if (quadArea < total * 0.1 || bestSize < quadArea * 0.75) return null;
  if (!_isConvex(pts)) return null;
  return [for (final p in pts) ...p];
}

/// Re-orders four arbitrary normalized points into tl, tr, br, bl.
List<double> orderCorners(List<List<double>> pts) {
  List<double> pick(double Function(List<double>) score, bool max) =>
      pts.reduce((a, b) => (max ? score(a) >= score(b) : score(a) <= score(b)) ? a : b);
  final tl = pick((p) => p[0] + p[1], false);
  final br = pick((p) => p[0] + p[1], true);
  final tr = pick((p) => p[0] - p[1], true);
  final bl = pick((p) => p[0] - p[1], false);
  return [...tl, ...tr, ...br, ...bl];
}

Uint8List _boxBlur3(Uint8List src, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0, n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          sum += src[yy * w + xx];
          n++;
        }
      }
      out[y * w + x] = sum ~/ n;
    }
  }
  return out;
}

int _otsuThreshold(Uint8List data) {
  final hist = List<int>.filled(256, 0);
  for (final v in data) {
    hist[v]++;
  }
  final total = data.length;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

double _polygonArea(List<List<double>> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i][0] * p[j][1] - p[j][0] * p[i][1];
  }
  return a.abs() / 2;
}

bool _isConvex(List<List<double>> p) {
  var sign = 0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length], c = p[(i + 2) % p.length];
    final cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
    if (cross.abs() < 1e-9) return false;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Skew estimation (projection profile variance on binarized ink)
// ---------------------------------------------------------------------------

double _estimateSkewDegrees(img.Image image, {required List<double> candidates}) {
  const step = 4;
  final w = image.width, h = image.height;
  final xs = <double>[];
  final ys = <double>[];
  for (var y = 0; y < h; y += step) {
    for (var x = 0; x < w; x += step) {
      final lum = image.getPixel(x, y).luminance;
      if (lum < 120) {
        xs.add(x.toDouble());
        ys.add(y.toDouble());
      }
    }
  }
  if (xs.length < 50) return 0;

  double best = 0;
  double bestScore = -1;
  for (final deg in candidates) {
    final a = deg * math.pi / 180.0;
    final s = math.sin(a), c = math.cos(a);
    final rows = <double, int>{};
    for (var i = 0; i < xs.length; i++) {
      final row = (ys[i] * c - xs[i] * s).roundToDouble();
      rows[row] = (rows[row] ?? 0) + 1;
    }
    var score = 0.0;
    rows.forEach((_, v) => score += (v * v).toDouble());
    if (score > bestScore) {
      bestScore = score;
      best = deg;
    }
  }
  return best;
}
