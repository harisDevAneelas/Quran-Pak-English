import 'package:flutter/foundation.dart';

import 'db_ayah.dart';
import 'quran_database.dart';

/// One word-by-word cell: Arabic and its English gloss from `Quran.words`.
class WordByWordPair {
  const WordByWordPair({required this.arabic, required this.gloss});

  final String arabic;
  final String gloss;
}

/// Loads paired word-by-word glosses from `Quran.words`.
///
/// Keys use the app mushaf numbering (Fatiha = 6 ayahs). Each value is
/// `[arabic:english]` pairs. An empty cell list means that ayah has no glosses.
class WordByWordRepository {
  WordByWordRepository._();

  static final Map<int, Map<String, List<WordByWordPair>>> _surahCache = {};
  static final Map<int, Future<Map<String, List<WordByWordPair>>>> _inFlight =
      {};

  static final RegExp pairPattern = RegExp(r'\[([^\[\]]+)\]');

  /// Parses a `words` value. The first colon separates the sides.
  static List<WordByWordPair> parsePairs(String raw) {
    final pairs = <WordByWordPair>[];
    for (final match in pairPattern.allMatches(raw)) {
      final inner = match.group(1)!;
      final colon = inner.indexOf(':');
      if (colon <= 0) continue;
      final arabic = inner.substring(0, colon).trim();
      final gloss = inner.substring(colon + 1).trim();
      if (arabic.isEmpty) continue;
      pairs.add(WordByWordPair(arabic: arabic, gloss: gloss));
    }
    return pairs;
  }

  /// Ensures paired glosses for [surah] are cached.
  static Future<void> ensureSurahLoaded(int surah) async {
    assert(surah >= 1 && surah <= 114);
    if (_surahCache.containsKey(surah)) return;
    await _loadSurah(surah);
  }

  static Future<Map<String, List<WordByWordPair>>> _loadSurah(int surah) {
    final existing = _inFlight[surah];
    if (existing != null) return existing;

    final future = () async {
      debugPrint('WBW loading surah $surah from words');
      final db = await QuranDatabase.instance;
      final rows = await db.rawQuery(
        'SELECT AyaNum, words FROM Quran '
        'WHERE SuraNum = ? AND words IS NOT NULL '
        "AND words != '' "
        'ORDER BY AyaNum',
        [surah],
      );

      final map = <String, List<WordByWordPair>>{};
      for (final row in rows) {
        final dbAyah = _asInt(row['AyaNum']);
        final raw = row['words']?.toString() ?? '';
        if (dbAyah == null || raw.isEmpty) continue;

        final appAyah = DbAyah.toApp(surah, dbAyah);
        if (appAyah == null) continue;

        final pairs = parsePairs(raw);
        if (pairs.isEmpty) continue;
        map['$surah:$appAyah'] = List<WordByWordPair>.unmodifiable(pairs);
      }

      _surahCache[surah] = map;
      debugPrint('WBW loaded surah $surah (${map.length} ayahs)');
      return map;
    }();

    _inFlight[surah] = future;
    return future.whenComplete(() {
      _inFlight.remove(surah);
    });
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Pairs for an app [surah] and [ayah]. Empty until [ensureSurahLoaded].
  static List<WordByWordPair> pairsFor({
    required int surah,
    required int ayah,
  }) {
    return _surahCache[surah]?['$surah:$ayah'] ?? const [];
  }

  static void clear() {
    _surahCache.clear();
    _inFlight.clear();
  }
}
