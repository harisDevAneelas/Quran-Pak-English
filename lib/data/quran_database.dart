import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'quran_database_factory_stub.dart'
    if (dart.library.html) 'quran_database_factory_web.dart'
    if (dart.library.io) 'quran_database_factory_io.dart';

abstract final class QuranDatabase {
  static const assetPath = 'assets/data/english_db.sqlite';

  /// Bump when `assets/data/english_db.sqlite` is replaced so installs recopy it.
  static const _fileName = 'quran_app_en_v1.sqlite';

  static Database? _db;
  static Future<Database>? _opening;
  static bool _factoryConfigured = false;

  static void configureFactory() {
    if (_factoryConfigured) return;
    configureSqfliteFactory();
    _factoryConfigured = true;
  }

  static Future<Database> get instance {
    final existing = _db;
    if (existing != null && existing.isOpen) {
      return SynchronousFuture(existing);
    }
    return _opening ??= _open().then((db) {
      _db = db;
      _opening = null;
      return db;
    });
  }

  static Future<void> warmUp() async {
    configureFactory();
    await instance;
  }

  static Future<Database> _open() async {
    configureFactory();
    final path = await _resolvedPath();
    await _ensureCopied(path);
    return openDatabase(path, readOnly: true, singleInstance: true);
  }

  static Future<String> _resolvedPath() async {
    if (kIsWeb) return _fileName;
    final dir = await getDatabasesPath();
    return p.join(dir, _fileName);
  }

  static Future<void> _ensureCopied(String path) async {
    if (await databaseExists(path)) return;

    debugPrint('QuranDatabase: copying $assetPath → $path');
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await databaseFactory.writeDatabaseBytes(path, bytes);
    debugPrint('QuranDatabase: copy done (${bytes.length} bytes)');
  }
}
