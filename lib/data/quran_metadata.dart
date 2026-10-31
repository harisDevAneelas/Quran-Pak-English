import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/surah_ayah_counts.dart';
import 'db_ayah.dart';
import 'quran_database.dart';

/// Bismillah from `quran.metadata.json`.
///
/// Surah names, intros, and related facts come from `Sura`. Para ranges and
/// 15-line pages come from `Juz`, `Quran.ParaStart`, and `Quran.PageNum1`.
class QuranMetadata {
  const QuranMetadata({
    required this.surahs,
    required this.juz,
    required this.bismillahWords,
  });

  final List<SurahMeta> surahs;
  final List<JuzMeta> juz;

  /// Plain bismillah words (no Tajweed) for Surah headers.
  final List<String> bismillahWords;

  static const assetPath = 'assets/data/quran.metadata.json';

  static QuranMetadata? _cache;
  static Future<QuranMetadata>? _inFlight;

  /// In-memory metadata if [load] has already finished; otherwise `null`.
  static QuranMetadata? get cached => _cache;

  /// Loads and caches metadata for the app lifetime.
  static Future<QuranMetadata> load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= () async {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = QuranMetadata.fromJson(json);
      final meta = await parsed._withDatabaseDivisions();
      _cache = meta;
      _inFlight = null;
      return meta;
    }();
  }

  factory QuranMetadata.fromJson(Map<String, dynamic> json) {
    final bismi = json['bismillah'] as Map<String, dynamic>? ?? const {};
    final words = (bismi['words'] as List<dynamic>? ?? const [])
        .map((e) => (e as Map<String, dynamic>)['text'] as String)
        .toList(growable: false);

    return QuranMetadata(
      surahs: const [],
      juz: const [],
      bismillahWords: words,
    );
  }

  JuzMeta? juzAt(int juzNum) {
    if (juzNum < 1 || juzNum > juz.length) return null;
    return juz[juzNum - 1];
  }

  Future<QuranMetadata> _withDatabaseDivisions() async {
    final db = await QuranDatabase.instance;
    final surahRows = await db.rawQuery(
      'SELECT SuraNum, SurahOrder, SurahIntro, '
      'JuzNum, ArabicName, EngName, PageNum, TotalAya '
      'FROM Sura ORDER BY SuraNum',
    );
    final juzRows = await db.rawQuery(
      'SELECT JuzNum, UrduName, ArabicName, EngName '
      'FROM Juz ORDER BY JuzNum',
    );
    final ayahRows = await db.rawQuery(
      'SELECT SuraNum, AyaNum, ParaStart, PageNum1 '
      'FROM Quran ORDER BY SuraNum, AyaNum',
    );
    return QuranMetadata(
      surahs: [
        for (final row in surahRows) SurahMeta.fromSuraRow(row),
      ],
      juz: parasFromRows(juzRows: juzRows, ayahRows: ayahRows),
      bismillahWords: bismillahWords,
    );
  }

  /// Para list from `Juz` names and `Quran.ParaStart` / `PageNum1`.
  static List<JuzMeta> parasFromRows({
    required List<Map<String, Object?>> juzRows,
    required List<Map<String, Object?>> ayahRows,
  }) {
    final spans = <int, _ParaSpan>{};
    for (final row in ayahRows) {
      final surah = (row['SuraNum'] as num).toInt();
      final dbAyah = (row['AyaNum'] as num).toInt();
      final appAyah = DbAyah.toApp(surah, dbAyah);
      if (appAyah == null) continue;
      final para = (row['ParaStart'] as num).toInt();
      final page = (row['PageNum1'] as num?)?.toInt();
      final span = spans.putIfAbsent(para, _ParaSpan.new);
      span.startSurah ??= surah;
      span.startAyah ??= appAyah;
      span.pageNum ??= page;
      span.endSurah = surah;
      span.endAyah = appAyah;
      span.ayahs++;
    }

    final paras = <JuzMeta>[];
    for (final row in juzRows) {
      final juz = (row['JuzNum'] as num).toInt();
      final span = spans[juz];
      if (span == null ||
          span.startSurah == null ||
          span.startAyah == null ||
          span.endSurah == null ||
          span.endAyah == null) {
        continue;
      }
      final nameUr = row['UrduName']?.toString() ?? '';
      final nameAr = row['ArabicName']?.toString() ?? '';
      final nameEn = row['EngName']?.toString() ?? '';
      paras.add(
        JuzMeta(
          juz: juz,
          nameAr: nameAr.isEmpty ? 'Para $juz' : nameAr,
          nameUr: nameUr,
          nameEn: nameEn,
          startSurah: span.startSurah!,
          startAyah: span.startAyah!,
          endSurah: span.endSurah!,
          endAyah: span.endAyah!,
          pageNum: span.pageNum,
          totalAyahs: span.ayahs,
        ),
      );
    }
    return paras;
  }

  /// Safe lookup after load; empty string if metadata is not ready yet.
  static String nameArOrEmpty(int surah) {
    final cached = _cache;
    if (cached == null || surah < 1 || surah > cached.surahs.length) {
      return '';
    }
    return cached.surahs[surah - 1].nameAr;
  }

  /// Safe Surah lookup after [load]; null if not ready / out of range.
  static SurahMeta? surahOrNull(int surah) {
    final cached = _cache;
    if (cached == null || surah < 1 || surah > cached.surahs.length) {
      return null;
    }
    return cached.surahs[surah - 1];
  }

  /// Safe joined bismillah text after [load]; empty if not ready.
  static String bismillahTextOrEmpty() {
    final words = _cache?.bismillahWords;
    if (words == null || words.isEmpty) return '';
    return words.join(' ');
  }

  /// How many leading words of this ayah are the para name. Zero if not a start.
  ///
  /// Para 1's name is الم on Baqarah 2:1. Fatiha stays in the para range but
  /// is not the painted opening.
  static int paraOpeningWordCount(int surah, int ayah) {
    final cached = _cache;
    if (cached == null) return 0;
    return openingWordCountAt(cached.juz, surah, ayah);
  }

  /// Para-name word count for [surah]:[ayah] from a juz list.
  static int openingWordCountAt(List<JuzMeta> juz, int surah, int ayah) {
    for (final j in juz) {
      if (j.juz == 1) {
        if (surah == 2 && ayah == 1) return j.openingWordCount;
        continue;
      }
      if (j.startSurah == surah && j.startAyah == ayah) {
        return j.openingWordCount;
      }
    }
    return 0;
  }
}

class SurahMeta {
  const SurahMeta({
    required this.surah,
    required this.nameAr,
    required this.ayahCount,
    this.englishName = '',
    this.englishNameTranslation = '',
    this.revelationType = '',
    this.arabicNameDb = '',
    this.dbAyahCount,
    this.juzNum,
    this.pageNum,
    this.chronologicalOrder,
    this.intro = '',
  });

  final int surah;
  final String nameAr;
  final int ayahCount;
  final String englishName;
  final String englishNameTranslation;
  final String revelationType;

  /// Plain Arabic name from the SQLite `Sura` table.
  final String arabicNameDb;

  /// Ayah count as stored in SQLite (may count Bismillah for Al-Fatiha).
  final int? dbAyahCount;

  /// Starting juz for this surah (`Sura.JuzNum`).
  final int? juzNum;

  /// Starting 15-line page (`Sura.PageNum`).
  final int? pageNum;

  /// Revelation order (1–114) parsed from `Sura.SurahOrder`.
  final int? chronologicalOrder;

  /// Urdu introduction from `Sura.SurahIntro`.
  final String intro;

  /// Arabic name without harakat, for menus and search.
  String get plainNameAr {
    final source = nameAr.isNotEmpty ? nameAr : arabicNameDb;
    final stripped = _stripArabicDiacritics(source)
        .replaceAll(RegExp(r'\s+'), ' ');
    return stripped.trim();
  }

  /// Preferred title for lists / drawers (English EngName first).
  String get listTitle {
    if (englishName.isNotEmpty) return englishName;
    if (arabicNameDb.isNotEmpty) return arabicNameDb;
    if (plainNameAr.isNotEmpty) return plainNameAr;
    return 'Surah $surah';
  }

  String get revelationLabel {
    return switch (revelationType) {
      'Meccan' => 'Meccan',
      'Medinan' => 'Medinan',
      _ => revelationType,
    };
  }

  /// One `Sura` row. [ayahCount] is the app count (Fatiha is 6).
  factory SurahMeta.fromSuraRow(Map<String, Object?> row) {
    final surah = (row['SuraNum'] as num).toInt();
    final arabic = row['ArabicName']?.toString() ?? '';
    final orderText = row['SurahOrder']?.toString() ?? '';
    final parsed = _parseSurahOrder(orderText);
    return SurahMeta(
      surah: surah,
      nameAr: arabic,
      ayahCount: SurahAyahCounts.of(surah),
      englishName: row['EngName']?.toString() ?? '',
      englishNameTranslation: parsed.translation,
      revelationType: parsed.revelation,
      arabicNameDb: arabic,
      dbAyahCount: (row['TotalAya'] as num?)?.toInt(),
      juzNum: (row['JuzNum'] as num?)?.toInt(),
      pageNum: (row['PageNum'] as num?)?.toInt(),
      chronologicalOrder: parsed.chronologicalOrder,
      intro: row['SurahIntro']?.toString() ?? '',
    );
  }
}

({String translation, String revelation, int? chronologicalOrder})
_parseSurahOrder(String text) {
  final translation =
      RegExp(r'\(([^)]+)\)').firstMatch(text)?.group(1)?.trim() ?? '';
  final place = RegExp(r'Revealed in ([A-Za-z]+)').firstMatch(text)?.group(1);
  final revelation = switch (place) {
    'Mecca' => 'Meccan',
    'Medina' => 'Medinan',
    _ => '',
  };
  final chronologicalOrder = int.tryParse(
    RegExp(r'Chronological order (\d+)').firstMatch(text)?.group(1) ?? '',
  );
  return (
    translation: translation,
    revelation: revelation,
    chronologicalOrder: chronologicalOrder,
  );
}

class _ParaSpan {
  int? startSurah;
  int? startAyah;
  int? endSurah;
  int? endAyah;
  int? pageNum;
  int ayahs = 0;
}

String _stripArabicDiacritics(String input) {
  return input.replaceAll(
    RegExp(
      r'[\u0610-\u061A\u0640\u064B-\u065F\u0670\u06D6-\u06ED\u200C\u200D]',
    ),
    '',
  );
}

class JuzMeta {
  const JuzMeta({
    required this.juz,
    required this.nameAr,
    required this.startSurah,
    required this.startAyah,
    required this.endSurah,
    required this.endAyah,
    this.nameEn = '',
    this.nameUr = '',
    this.pageNum,
    this.totalAyahs,
  });

  final int juz;
  final String nameAr;
  final int startSurah;
  final int startAyah;
  final int endSurah;
  final int endAyah;

  /// English / common juz title from SQLite `Juz.EngName`.
  final String nameEn;

  /// Short Urdu label from SQLite `Juz.UrduName` (e.g. الم).
  final String nameUr;

  final int? pageNum;
  final int? totalAyahs;

  /// Words in the Urdu para name (`لَنْ تَنَالُوا` is two). At least one.
  int get openingWordCount {
    final parts = nameUr
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final n = parts.length;
    if (n < 1) return 1;
    return n > 3 ? 3 : n;
  }

  /// Preferred sidebar / list title. English para names, then Arabic, then
  /// the short opening label used only for the painted word count.
  String get displayName {
    if (nameEn.isNotEmpty) return nameEn;
    if (nameAr.isNotEmpty) return nameAr;
    if (nameUr.isNotEmpty) return nameUr;
    return 'Para $juz';
  }
}
