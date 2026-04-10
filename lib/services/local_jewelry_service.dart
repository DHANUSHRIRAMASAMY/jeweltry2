import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/jewelry_item.dart';
import 'background_remover.dart';

class LocalJewelryService {
  static final LocalJewelryService _instance = LocalJewelryService._();
  factory LocalJewelryService() => _instance;
  LocalJewelryService._();

  Database? _db;
  final _uuid = const Uuid();

  Future<Database> get _database async {
    _db ??= await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'jeweltry.db');
    return openDatabase(
      path,
      version: 4, // v4 adds rightImagePath column
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE jewelry (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            imagePath TEXT NOT NULL,
            type TEXT NOT NULL,
            scale REAL NOT NULL DEFAULT 1.0,
            category TEXT NOT NULL DEFAULT '',
            isAsset INTEGER NOT NULL DEFAULT 0,
            glbPath TEXT,
            rightImagePath TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.delete('jewelry', where: 'id IN (?, ?, ?, ?)', whereArgs: [
            'sample_earring_1',
            'sample_earring_2',
            'sample_necklace_1',
            'sample_chain_1',
          ]);
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE jewelry ADD COLUMN glbPath TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE jewelry ADD COLUMN rightImagePath TEXT');
        }
      },
    );
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<JewelryItem>> getAllItems({JewelryType? type}) async {
    final db = await _database;
    final rows = type == null
        ? await db.query('jewelry', orderBy: 'name ASC')
        : await db.query('jewelry',
            where: 'type = ?', whereArgs: [type.name], orderBy: 'name ASC');
    return rows.map(JewelryItem.fromMap).toList();
  }

  Future<List<JewelryItem>> searchByName(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await _database;
    final rows = await db.query(
      'jewelry',
      where: 'LOWER(name) LIKE ?',
      whereArgs: ['%${query.trim().toLowerCase()}%'],
      orderBy: 'name ASC',
      limit: 30,
    );
    return rows.map(JewelryItem.fromMap).toList();
  }

  Future<List<JewelryItem>> getItemsByTypeAndCategory(
      JewelryType type, String category) async {
    final db = await _database;
    final rows = await db.query(
      'jewelry',
      where: 'type = ? AND LOWER(category) = ?',
      whereArgs: [type.name, category.toLowerCase()],
      orderBy: 'name ASC',
    );
    return rows.map(JewelryItem.fromMap).toList();
  }

  Future<List<String>> getCategoriesForType(JewelryType type) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT category FROM jewelry WHERE type = ? ORDER BY category ASC',
      [type.name],
    );
    return rows
        .map((r) => r['category'] as String)
        .where((c) => c.isNotEmpty)
        .toList();
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<JewelryItem> addJewelry({
    required File imageFile,
    required String name,
    required JewelryType type,
    required double scale,
    required String category,
    File? glbFile,
    bool isPair = false, // true = split image into left + right halves
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final jewelryDir = Directory(p.join(dir.path, 'jewelry_images'));
    if (!jewelryDir.existsSync()) jewelryDir.createSync(recursive: true);

    final id = _uuid.v4();
    final imgDest = p.join(jewelryDir.path, '$id.png');

    // Remove background → save transparent PNG
    try {
      await BackgroundRemover.process(
        inputFile: imageFile,
        outputPath: imgDest,
      );
      debugPrint('BG removed: $imgDest');
    } catch (e) {
      debugPrint('BG removal failed ($e), copying original');
      await imageFile.copy(imgDest);
    }

    // Split into left/right halves if it's a pair
    String? rightDest;
    if (isPair && type == JewelryType.earring) {
      rightDest = p.join(jewelryDir.path, '${id}_right.png');
      try {
        await _splitEarringPair(
          leftDest: imgDest,   // overwrites left half into the main path
          rightDest: rightDest,
          processedPath: imgDest,
        );
        debugPrint('Earring pair split: left=$imgDest right=$rightDest');
      } catch (e) {
        debugPrint('Pair split failed ($e), using full image for both ears');
        rightDest = null;
      }
    }

    // Copy .glb if provided
    String? glbDest;
    if (glbFile != null) {
      final glbDir = Directory(p.join(dir.path, 'jewelry_models'));
      if (!glbDir.existsSync()) glbDir.createSync(recursive: true);
      glbDest = p.join(glbDir.path, '$id.glb');
      await glbFile.copy(glbDest);
    }

    final item = JewelryItem(
      id: id,
      name: name,
      imagePath: imgDest,
      type: type,
      scale: scale,
      category: category,
      isAsset: false,
      glbPath: glbDest,
      rightImagePath: rightDest,
    );

    final db = await _database;
    await db.insert('jewelry', item.toMap());
    return item;
  }

  /// Splits [processedPath] (a transparent PNG) into individual earrings
  /// using blob detection on the alpha channel.
  /// Overwrites [leftDest] with the left earring and saves right to [rightDest].
  static Future<void> _splitEarringPair({
    required String leftDest,
    required String rightDest,
    required String processedPath,
  }) async {
    final bytes = await File(processedPath).readAsBytes();
    final result = await Isolate.run(() => _blobSplit(bytes));
    await File(leftDest).writeAsBytes(result.$1);
    await File(rightDest).writeAsBytes(result.$2);
  }

  /// Blob-detection split:
  ///   1. Scan alpha channel for opaque pixels (alpha > 10)
  ///   2. Find the vertical gap column that separates the two earrings
  ///      (the column with the fewest opaque pixels between the two blobs)
  ///   3. Crop left half and right half at that gap
  ///   4. Trim transparent borders from each crop
  static (List<int>, List<int>) _blobSplit(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) throw Exception('Cannot decode image');

    final w = src.width;
    final h = src.height;

    // Build column opacity histogram: how many opaque pixels per column
    final colOpacity = List<int>.filled(w, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = src.getPixel(x, y);
        if (pixel.a > 10) colOpacity[x]++;
      }
    }

    // Find the split column: the column with minimum opacity in the middle 60%
    // (ignore outer 20% on each side to avoid edge effects)
    final startX = (w * 0.20).round();
    final endX   = (w * 0.80).round();
    int splitX = w ~/ 2; // default: center
    int minVal = colOpacity[splitX];
    for (int x = startX; x < endX; x++) {
      if (colOpacity[x] < minVal) {
        minVal = colOpacity[x];
        splitX = x;
      }
    }

    // Crop at the split column
    final leftCrop  = img.copyCrop(src, x: 0,      y: 0, width: splitX,     height: h);
    final rightCrop = img.copyCrop(src, x: splitX, y: 0, width: w - splitX, height: h);

    // Trim transparent borders from each crop so the earring fills the image
    final leftTrimmed  = _trimTransparent(leftCrop);
    final rightTrimmed = _trimTransparent(rightCrop);

    return (img.encodePng(leftTrimmed), img.encodePng(rightTrimmed));
  }

  /// Remove transparent border pixels from all four sides of [src].
  static img.Image _trimTransparent(img.Image src) {
    final w = src.width;
    final h = src.height;

    int top    = 0;
    int bottom = h - 1;
    int left   = 0;
    int right  = w - 1;

    // Find top
    outer: for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (src.getPixel(x, y).a > 10) { top = y; break outer; }
      }
    }
    // Find bottom
    outer: for (int y = h - 1; y >= 0; y--) {
      for (int x = 0; x < w; x++) {
        if (src.getPixel(x, y).a > 10) { bottom = y; break outer; }
      }
    }
    // Find left
    outer: for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        if (src.getPixel(x, y).a > 10) { left = x; break outer; }
      }
    }
    // Find right
    outer: for (int x = w - 1; x >= 0; x--) {
      for (int y = 0; y < h; y++) {
        if (src.getPixel(x, y).a > 10) { right = x; break outer; }
      }
    }

    // Add a small padding so the earring doesn't touch the edge
    const pad = 4;
    final x0 = (left   - pad).clamp(0, w - 1);
    final y0 = (top    - pad).clamp(0, h - 1);
    final x1 = (right  + pad).clamp(0, w - 1);
    final y1 = (bottom + pad).clamp(0, h - 1);

    if (x1 <= x0 || y1 <= y0) return src; // nothing to trim
    return img.copyCrop(src, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  }

  Future<void> deleteJewelry(JewelryItem item) async {
    if (!item.isAsset) {
      for (final path in [item.imagePath, item.glbPath, item.rightImagePath]) {
        if (path == null) continue;
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (e) {
          debugPrint('File delete error: $e');
        }
      }
    }
    final db = await _database;
    await db.delete('jewelry', where: 'id = ?', whereArgs: [item.id]);
  }

  Future<void> updateScale(String id, double scale) async {
    final db = await _database;
    await db.update('jewelry', {'scale': scale},
        where: 'id = ?', whereArgs: [id]);
  }
}
