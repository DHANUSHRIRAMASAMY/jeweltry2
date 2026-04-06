import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/jewelry_item.dart';

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
      version: 2, // bumped from 1 → 2 to trigger onUpgrade
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE jewelry (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            imagePath TEXT NOT NULL,
            type TEXT NOT NULL,
            scale REAL NOT NULL DEFAULT 1.0,
            category TEXT NOT NULL DEFAULT '',
            isAsset INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Remove the hardcoded sample items added in v1
          await db.delete(
            'jewelry',
            where: 'id IN (?, ?, ?, ?)',
            whereArgs: [
              'sample_earring_1',
              'sample_earring_2',
              'sample_necklace_1',
              'sample_chain_1',
            ],
          );
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

  /// Copy [imageFile] into app documents and save metadata.
  Future<JewelryItem> addJewelry({
    required File imageFile,
    required String name,
    required JewelryType type,
    required double scale,
    required String category,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final jewelryDir = Directory(p.join(dir.path, 'jewelry_images'));
    if (!jewelryDir.existsSync()) jewelryDir.createSync(recursive: true);

    final id = _uuid.v4();
    final ext = p.extension(imageFile.path).isNotEmpty
        ? p.extension(imageFile.path)
        : '.png';
    final destPath = p.join(jewelryDir.path, '$id$ext');
    await imageFile.copy(destPath);

    final item = JewelryItem(
      id: id,
      name: name,
      imagePath: destPath,
      type: type,
      scale: scale,
      category: category,
      isAsset: false,
    );

    final db = await _database;
    await db.insert('jewelry', item.toMap());
    return item;
  }

  Future<void> deleteJewelry(JewelryItem item) async {
    // Delete file only for user-added items
    if (!item.isAsset) {
      try {
        final f = File(item.imagePath);
        if (f.existsSync()) f.deleteSync();
      } catch (e) {
        debugPrint('File delete error: $e');
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
