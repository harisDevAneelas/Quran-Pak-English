import 'package:flutter/foundation.dart';

import 'db_ayah.dart';
import 'quran_database.dart';
import 'translation_catalog.dart';

/// Lazy-loads and caches translator packs from `english_db.sqlite` (`Quran` table).
///
/// Multiple packs can be loaded at once for multi-select translation display.
class TranslationRepository {
  TranslationRepository();

  final Map<String, Map<String, String>> _packs = {};
  final Map<String, Future<void>> _inFlight = {};

  static final Set<String> _allowedColumns = {
    for (final option in TranslationCatalog.all) option.id,
  };

  bool isLoaded(String translatorId) {
    final id = TranslationCatalog.resolveId(translatorId);
    return _packs[id]?.isNotEmpty == true;
  }

  /// Ensures [translatorId] is in memory (no-op if already loaded).
  Future<void> ensureLoaded(String translatorId) {
    final id = TranslationCatalog.resolveId(translatorId);
    final existing = _packs[id];
    if (existing != null && existing.isNotEmpty) {
      return SynchronousFuture<void>(null);
    }
    final pending = _inFlight[id];
    if (pending != null) return pending;

    final future = _load(id);
    _inFlight[id] = future;
    return future.whenComplete(() {
      _inFlight.remove(id);
    });
  }

  Future<void> _load(String id) async {
    if (!_allowedColumns.contains(id)) {
      throw StateError('Unknown translation column: $id');
    }

    try {
      final db = await QuranDatabase.instance;
      await Future<void>.delayed(Duration.zero);

      final rows = await db.rawQuery(
        'SELECT SuraNum, AyaNum, "$id" AS text '
        'FROM Quran WHERE "$id" IS NOT NULL AND "$id" != \'\'',
      );

      final map = <String, String>{};
      for (final row in rows) {
        final surah = _asInt(row['SuraNum']);
        final dbAyah = _asInt(row['AyaNum']);
        final text = row['text']?.toString() ?? '';
        if (surah == null || dbAyah == null || text.isEmpty) continue;

        final appAyah = DbAyah.toApp(surah, dbAyah);
        if (appAyah == null) continue;

        map['$surah:$appAyah'] = text;
      }

      if (map.isEmpty) {
        throw StateError('Empty translation pack from SQLite: $id');
      }
      _packs[id] = map;
      debugPrint('Translation loaded from DB: $id (${map.length} ayahs)');
    } catch (error, stack) {
      debugPrint('Translation load failed for $id: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Every catalog column that has text for this one ayah.
  Future<Map<String, String>> textsForAyah(int surah, int ayah) async {
    final dbAyah = DbAyah.of(surah, ayah);
    final columns = [
      for (final option in TranslationCatalog.all) '"${option.id}"',
    ].join(', ');
    final db = await QuranDatabase.instance;
    final rows = await db.rawQuery(
      'SELECT $columns FROM Quran WHERE SuraNum = ? AND AyaNum = ? LIMIT 1',
      [surah, dbAyah],
    );
    if (rows.isEmpty) return const {};
    final row = rows.first;
    final out = <String, String>{};
    for (final option in TranslationCatalog.all) {
      final text = row[option.id]?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      out[option.id] = text;
    }
    return out;
  }

  /// Translation for [surah]:[ayah] from pack [translatorId], if loaded.
  String? textAt(String translatorId, int surah, int ayah) {
    final id = TranslationCatalog.resolveId(translatorId);
    return _packs[id]?['$surah:$ayah'];
  }

  void clear() {
    _packs.clear();
    _inFlight.clear();
  }
}
