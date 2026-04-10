import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Removes the background from a jewelry product photo entirely on-device.
///
/// Strategy (works well for standard product photos with plain backgrounds):
///   1. Decode the image
///   2. Sample background color from all four corners
///   3. Flood-fill from every edge pixel that matches the background
///   4. Apply a 1-pixel feather pass to soften hard edges
///   5. Encode as PNG with transparency and save
///
/// Runs in a separate Isolate so the UI never freezes.
class BackgroundRemover {
  BackgroundRemover._();

  /// Process [inputFile], remove background, save transparent PNG to
  /// [outputPath]. Returns the output file on success.
  static Future<File> process({
    required File inputFile,
    required String outputPath,
    int tolerance = 35,
  }) async {
    final bytes = await inputFile.readAsBytes(); // returns Uint8List
    final result = await Isolate.run(
      () => _removeBackground(bytes, tolerance),
    );
    final out = File(outputPath);
    await out.writeAsBytes(result);
    return out;
  }

  // ── Isolate worker ────────────────────────────────────────────────────────

  static List<int> _removeBackground(Uint8List bytes, int tolerance) {
    final src = img.decodeImage(bytes);
    if (src == null) throw Exception('Could not decode image');

    // Work on a copy with alpha channel
    final image = src.convert(numChannels: 4);
    final w = image.width;
    final h = image.height;

    // ── Step 1: sample background colour from corners ─────────────────────
    final bgColor = _sampleBackground(image, w, h);

    // ── Step 2: flood-fill from all four edges ────────────────────────────
    final visited = List.filled(w * h, false);

    // Seed from every pixel on the four borders
    final queue = <int>[];
    for (int x = 0; x < w; x++) {
      _enqueue(image, queue, visited, x, 0, w, h, bgColor, tolerance);
      _enqueue(image, queue, visited, x, h - 1, w, h, bgColor, tolerance);
    }
    for (int y = 1; y < h - 1; y++) {
      _enqueue(image, queue, visited, 0, y, w, h, bgColor, tolerance);
      _enqueue(image, queue, visited, w - 1, y, w, h, bgColor, tolerance);
    }

    // BFS flood fill
    while (queue.isNotEmpty) {
      final idx = queue.removeLast();
      final x = idx % w;
      final y = idx ~/ w;

      // Make transparent
      image.setPixelRgba(x, y, 0, 0, 0, 0);

      // 4-connected neighbours
      if (x > 0)     _enqueue(image, queue, visited, x - 1, y, w, h, bgColor, tolerance);
      if (x < w - 1) _enqueue(image, queue, visited, x + 1, y, w, h, bgColor, tolerance);
      if (y > 0)     _enqueue(image, queue, visited, x, y - 1, w, h, bgColor, tolerance);
      if (y < h - 1) _enqueue(image, queue, visited, x, y + 1, w, h, bgColor, tolerance);
    }

    // ── Step 3: feather — soften the edge by blending semi-transparent ────
    _featherEdges(image, w, h);

    return img.encodePng(image);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Sample the dominant background colour from the four corners (5×5 patches).
  static _Rgb _sampleBackground(img.Image image, int w, int h) {
    final samples = <_Rgb>[];
    const patch = 5;
    for (int dy = 0; dy < patch; dy++) {
      for (int dx = 0; dx < patch; dx++) {
        samples.add(_pixelRgb(image, dx, dy));
        samples.add(_pixelRgb(image, w - 1 - dx, dy));
        samples.add(_pixelRgb(image, dx, h - 1 - dy));
        samples.add(_pixelRgb(image, w - 1 - dx, h - 1 - dy));
      }
    }
    // Average
    int r = 0, g = 0, b = 0;
    for (final s in samples) { r += s.r; g += s.g; b += s.b; }
    return _Rgb(r ~/ samples.length, g ~/ samples.length, b ~/ samples.length);
  }

  static _Rgb _pixelRgb(img.Image image, int x, int y) {
    final p = image.getPixel(x, y);
    return _Rgb(p.r.toInt(), p.g.toInt(), p.b.toInt());
  }

  static void _enqueue(
    img.Image image,
    List<int> queue,
    List<bool> visited,
    int x,
    int y,
    int w,
    int h,
    _Rgb bg,
    int tolerance,
  ) {
    final idx = y * w + x;
    if (visited[idx]) return;
    final p = image.getPixel(x, y);
    // Already transparent
    if (p.a == 0) { visited[idx] = true; return; }
    if (_colorDistance(_Rgb(p.r.toInt(), p.g.toInt(), p.b.toInt()), bg) <= tolerance) {
      visited[idx] = true;
      queue.add(idx);
    }
  }

  static int _colorDistance(_Rgb a, _Rgb b) {
    final dr = a.r - b.r;
    final dg = a.g - b.g;
    final db = a.b - b.b;
    return math.sqrt(dr * dr + dg * dg + db * db).round();
  }

  /// One-pass feather: for every opaque pixel adjacent to a transparent one,
  /// reduce its alpha to 128 to create a soft anti-aliased edge.
  static void _featherEdges(img.Image image, int w, int h) {
    // Collect edge pixels first to avoid modifying while iterating
    final edgePixels = <int>[];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final p = image.getPixel(x, y);
        if (p.a == 0) continue; // already transparent
        // Check if any 4-neighbour is transparent
        if (image.getPixel(x - 1, y).a == 0 ||
            image.getPixel(x + 1, y).a == 0 ||
            image.getPixel(x, y - 1).a == 0 ||
            image.getPixel(x, y + 1).a == 0) {
          edgePixels.add(y * w + x);
        }
      }
    }
    for (final idx in edgePixels) {
      final x = idx % w;
      final y = idx ~/ w;
      final p = image.getPixel(x, y);
      image.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 128);
    }
  }
}

class _Rgb {
  final int r, g, b;
  const _Rgb(this.r, this.g, this.b);
}
