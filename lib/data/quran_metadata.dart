import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/mushaf_script.dart';
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
    required this.bismillahIndopak,
    required this.bismillahUthmani,
    this.paraNames = const {},
  });

  final List<SurahMeta> surahs;
  final List<JuzMeta> juz;

  /// Plain IndoPak header words (no Tajweed).
  final List<String> bismillahIndopak;

  /// Plain Uthmani header words (no Tajweed).
  final List<String> bismillahUthmani;

  /// Arabic/Urdu para openings from `quran.metadata.json` (`para[].name`).
  final Map<int, String> paraNames;

  /// Header words for [script].
  List<String> bismillahWordsFor(MushafScript script) => switch (script) {
        MushafScript.indopak => bismillahIndopak,
        MushafScript.uthmani => bismillahUthmani,
      };

  /// Display title for a para (metadata Arabic first).
  String paraNameOrEmpty(int para) {
    final fromMeta = paraNames[para]?.trim() ?? '';
    if (fromMeta.isNotEmpty) return fromMeta;
    final j = juzAt(para);
    if (j == null) return '';
    return j.displayName;
  }

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
    return QuranMetadata(
      surahs: const [],
      juz: const [],
      bismillahIndopak: _bismillahWordsFrom(bismi['indopak']),
      bismillahUthmani: _bismillahWordsFrom(bismi['uthmani']),
      paraNames: _paraNamesFrom(json['para']),
    );
  }

  static Map<int, String> _paraNamesFrom(Object? node) {
    if (node is! List) return const {};
    final out = <int, String>{};
    for (final e in node) {
      if (e is! Map) continue;
      final para = (e['para'] as num?)?.toInt();
      final name = e['name']?.toString().trim() ?? '';
      if (para == null || para < 1 || name.isEmpty) continue;
      out[para] = name;
    }
    return Map<int, String>.unmodifiable(out);
  }

  static List<String> _bismillahWordsFrom(Object? node) {
    if (node is! Map) return const [];
    final words = node['words'] as List<dynamic>? ?? const [];
    return [
      for (final e in words)
        if (e is Map<String, dynamic>) (e['text'] as String?) ?? '',
    ].where((t) => t.isNotEmpty).toList(growable: false);
  }

  JuzMeta? juzAt(int juzNum) {
    if (juzNum < 1 || juzNum > juz.length) return null;
    return juz[juzNum - 1];
  }

  Future<QuranMetadata> _withDatabaseDivisions() async {
    final db = await QuranDatabase.instance;
    final surahRows = await db.rawQuery(
      'SELECT SuraNum, SurahOrder, SurahIntro, SimpleEngName, '
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
      juz: parasFromRows(
        juzRows: juzRows,
        ayahRows: ayahRows,
        paraNames: paraNames,
      ),
      bismillahIndopak: bismillahIndopak,
      bismillahUthmani: bismillahUthmani,
      paraNames: paraNames,
    );
  }

  /// Para list from `Quran.ParaStart` / `PageNum1`; titles from metadata.
  static List<JuzMeta> parasFromRows({
    required List<Map<String, Object?>> juzRows,
    required List<Map<String, Object?>> ayahRows,
    Map<int, String> paraNames = const {},
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
      final dbUr = row['UrduName']?.toString() ?? '';
      final nameUr = paraNames[juz]?.trim().isNotEmpty == true
          ? paraNames[juz]!.trim()
          : dbUr;
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

  /// Safe Juz lookup after [load]; null if not ready / out of range.
  static JuzMeta? juzOrNull(int juz) {
    final cached = _cache;
    if (cached == null || juz < 1 || juz > cached.juz.length) {
      return null;
    }
    return cached.juz[juz - 1];
  }

  /// Safe joined bismillah text after [load]; empty if not ready.
  static String bismillahTextOrEmpty({
    MushafScript script = MushafScript.indopak,
  }) {
    final words = _cache?.bismillahWordsFor(script);
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
    this.simpleEngName = '',
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

  /// Alias bag from `Sura.SimpleEngName` (romanized / English search tokens).
  final String simpleEngName;

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

  /// Introduction from `Sura.SurahIntro`.
  final String intro;

  /// Arabic name without harakat, for menus and search.
  String get plainNameAr {
    final source = nameAr.isNotEmpty ? nameAr : arabicNameDb;
    final stripped = _stripArabicDiacritics(source)
        .replaceAll(RegExp(r'\s+'), ' ');
    return stripped.trim();
  }

  /// Preferred title for lists / grids (English EngName first, no "Surah" prefix).
  String get listTitle {
    if (englishName.isNotEmpty) return stripSurahPrefix(englishName);
    if (arabicNameDb.isNotEmpty) return arabicNameDb;
    if (plainNameAr.isNotEmpty) return plainNameAr;
    return '$surah';
  }

  /// `EngName` in english_db is often `Surah Al-Baqarah`; grids show the raw name.
  static String stripSurahPrefix(String name) {
    final trimmed = name.trim();
    final stripped = trimmed
        .replaceFirst(RegExp(r'^surah\s+', caseSensitive: false), '')
        .trim();
    return stripped.isEmpty ? trimmed : stripped;
  }

  String get revelationLabel {
    return switch (revelationType) {
      'Meccan' => 'Meccan',
      'Medinan' => 'Medinan',
      _ => revelationType,
    };
  }

  /// Higher is a closer name match. `0` means no match. Empty query → `100`.
  int queryScore(String query) {
    final q = normalizeMetaQuery(query);
    if (q.isEmpty) return 100;
    final number = _westernDigits(q);
    if (number == '$surah') return 100;
    var best = 0;
    for (final field in <String>[
      plainNameAr,
      listTitle,
      englishName,
      englishNameTranslation,
      simpleEngName,
      revelationLabel,
    ]) {
      final score = metaQueryScore(field, q);
      if (score > best) best = score;
    }
    return best;
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
      simpleEngName: row['SimpleEngName']?.toString() ?? '',
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

  /// Preferred list / about title. `Juz.UrduName` first, then Arabic, then Eng.
  String get displayName {
    if (nameUr.isNotEmpty) return nameUr;
    if (nameAr.isNotEmpty) return nameAr;
    if (nameEn.isNotEmpty) return nameEn;
    return 'Para $juz';
  }

  /// Higher is a closer name match. `0` means no match. Empty query → `100`.
  int queryScore(String query) {
    final q = normalizeMetaQuery(query);
    if (q.isEmpty) return 100;
    final number = _westernDigits(q);
    if (number == '$juz') return 100;
    var best = 0;
    for (final field in <String>[nameUr, nameAr, nameEn]) {
      final score = metaQueryScore(field, q);
      if (score > best) best = score;
    }
    return best;
  }
}

final RegExp _metaPunctuation = RegExp(r"[ـ\-_'’`.,،؛:!?/\\|]+");
final RegExp _metaWhitespace = RegExp(r'\s+');
final RegExp _metaLabelPrefix = RegExp(
  r'^(surahs?|surat|سورة|سورۃ|سوره|paras?|juz|پارہ|پاره|الجزء|جزء)\s*',
);
final RegExp _metaLatinArticle = RegExp(r'^(al|ar|an|as|ad|adh|ath|az|el)-?');
final RegExp _metaArabicArticle = RegExp(r'^ال');
final RegExp _metaNonLatin = RegExp(r'[^a-z0-9]');
final RegExp _metaDoubleLetter = RegExp(r'(.)\1+');
final RegExp _metaLatinVowels = RegExp(r'[aeiou]');

/// Lowercase Latin + fold Arabic/Urdu letters; strip harakat and labels.
String normalizeMetaQuery(String input) {
  var s = _stripArabicDiacritics(input);
  s = _foldArabicLetters(s);
  s = _westernDigits(s);
  s = s.toLowerCase();
  s = s.replaceAll(_metaPunctuation, ' ');
  s = s.replaceAll(_metaWhitespace, ' ').trim();
  s = s.replaceFirst(_metaLabelPrefix, '').trim();
  return s;
}

/// Score how well [normalizedQuery] matches [haystack]. Query should already
/// be passed through [normalizeMetaQuery] when possible; raw is accepted too.
int metaQueryScore(String haystack, String normalizedQuery) {
  final q = normalizeMetaQuery(normalizedQuery);
  if (q.isEmpty) return 100;
  if (haystack.isEmpty) return 0;

  final h = normalizeMetaQuery(haystack);
  if (h.isEmpty) return 0;

  if (h == q) return 95;

  final queryCompact = q.replaceAll(' ', '');
  final hayCompact = h.replaceAll(' ', '');

  if (hayCompact == queryCompact) return 92;

  var best = 0;
  if (h.contains(q) || hayCompact.contains(queryCompact)) {
    best = 70;
  }
  if (queryCompact.length >= 2 &&
      (hayCompact.startsWith(queryCompact) ||
          queryCompact.startsWith(hayCompact))) {
    if (80 > best) best = 80;
  }

  final qTokens = _metaTokens(q);
  final hTokens = _metaTokens(h);
  for (final qt in qTokens) {
    for (final ht in hTokens) {
      final score = _tokenScore(qt, ht);
      if (score > best) best = score;
    }
  }

  final qSkel = _latinSkeleton(queryCompact);
  final hSkel = _latinSkeleton(hayCompact);
  if (qSkel.length >= 2 && hSkel.length >= 2) {
    if (qSkel == hSkel && 78 > best) best = 78;
    if ((hSkel.contains(qSkel) || qSkel.contains(hSkel)) && 55 > best) {
      best = 55;
    }
  }

  if (_arabicScriptRatio(q) > 0.4 || _arabicScriptRatio(h) > 0.4) {
    final qLetters = _arabicLettersOnly(queryCompact);
    final hLetters = _arabicLettersOnly(hayCompact);
    if (qLetters.isNotEmpty && hLetters.isNotEmpty) {
      if (_isLetterSubsequence(hLetters, qLetters) ||
          _isLetterSubsequence(qLetters, hLetters)) {
        final shortLen = qLetters.length < hLetters.length
            ? qLetters.length
            : hLetters.length;
        if (shortLen >= 2 && 60 > best) best = 60;
      }
    }
  }

  return best;
}

List<String> _metaTokens(String normalized) {
  return normalized
      .split(_metaWhitespace)
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .map(_stripLeadingArticle)
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
}

String _stripLeadingArticle(String token) {
  var t = token;
  if (_metaLatinArticle.hasMatch(t)) {
    t = t.replaceFirst(_metaLatinArticle, '');
  }
  if (_metaArabicArticle.hasMatch(t)) {
    t = t.replaceFirst(_metaArabicArticle, '');
  }
  return t;
}

int _tokenScore(String queryToken, String hayToken) {
  if (queryToken.isEmpty || hayToken.isEmpty) return 0;
  if (queryToken == hayToken) return 90;
  if (hayToken.startsWith(queryToken) || queryToken.startsWith(hayToken)) {
    return queryToken.length >= 2 ? 75 : 0;
  }
  if (hayToken.contains(queryToken) || queryToken.contains(hayToken)) {
    return queryToken.length >= 3 ? 65 : 0;
  }
  final qs = _latinSkeleton(queryToken);
  final hs = _latinSkeleton(hayToken);
  if (qs.length >= 2 && hs.length >= 2 && qs == hs) return 72;
  if (qs.length >= 3 && hs.length >= 3 && (hs.contains(qs) || qs.contains(hs))) {
    return 50;
  }
  return 0;
}

String _latinSkeleton(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(_metaNonLatin, '');
  if (s.isEmpty) return '';
  s = s.replaceAll('ee', 'i');
  s = s.replaceAll('oo', 'u');
  s = s.replaceAll('aa', 'a');
  s = s.replaceAll('ou', 'u');
  s = s.replaceAllMapped(_metaDoubleLetter, (m) => m.group(1)!);
  s = s.replaceFirst(RegExp(r'^(al|ar|an|as|ad|adh|ath|az|el)'), '');
  s = s.replaceAll(_metaLatinVowels, '');
  return s;
}

String _foldArabicLetters(String input) {
  final buffer = StringBuffer();
  for (final unit in input.runes) {
    switch (unit) {
      case 0x0622:
      case 0x0623:
      case 0x0625:
      case 0x0627:
      case 0x0671:
        buffer.writeCharCode(0x0627);
      case 0x0629:
      case 0x06C3:
        buffer.writeCharCode(0x0647);
      case 0x06C1:
      case 0x06D5:
        buffer.writeCharCode(0x0647);
      case 0x0649:
      case 0x06CC:
      case 0x06D2:
        buffer.writeCharCode(0x064A);
      case 0x06A9:
      case 0x06AA:
        buffer.writeCharCode(0x0643);
      case 0x06BA:
        buffer.writeCharCode(0x0646);
      case 0x0624:
        buffer.writeCharCode(0x0648);
      case 0x0626:
        buffer.writeCharCode(0x064A);
      default:
        buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

String _westernDigits(String input) {
  final buffer = StringBuffer();
  for (final unit in input.runes) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      buffer.writeCharCode(0x30 + (unit - 0x0660));
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      buffer.writeCharCode(0x30 + (unit - 0x06F0));
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

String _arabicLettersOnly(String input) {
  final buffer = StringBuffer();
  for (final unit in input.runes) {
    if (unit >= 0x0621 && unit <= 0x064A) {
      buffer.writeCharCode(unit);
    } else if (unit >= 0x0670 && unit <= 0x06D3) {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

double _arabicScriptRatio(String input) {
  if (input.isEmpty) return 0;
  var arabic = 0;
  var total = 0;
  for (final unit in input.runes) {
    if (unit == 0x20) continue;
    total++;
    if ((unit >= 0x0600 && unit <= 0x06FF) ||
        (unit >= 0x0750 && unit <= 0x077F)) {
      arabic++;
    }
  }
  if (total == 0) return 0;
  return arabic / total;
}

bool _isLetterSubsequence(String needle, String hay) {
  if (needle.isEmpty) return true;
  final needleRunes = needle.runes.toList(growable: false);
  final hayRunes = hay.runes.toList(growable: false);
  if (needleRunes.length > hayRunes.length) return false;
  var i = 0;
  for (final unit in hayRunes) {
    if (unit == needleRunes[i]) {
      i++;
      if (i >= needleRunes.length) return true;
    }
  }
  return false;
}
