import 'ayah_ref.dart';
import 'db_ayah.dart';
import 'quran_database.dart';

/// Stacked Indo-Pak ruku mark facts for one ruku end.
class RukuMarkInfo {
  const RukuMarkInfo({
    required this.end,
    required this.indexInPara,
    required this.indexInSurah,
    required this.ayahCount,
  });

  final AyahRef end;

  /// 1-based ruku number inside the para (`ParaStart`).
  final int indexInPara;

  /// 1-based ruku number inside the surah.
  final int indexInSurah;

  /// How many app ayahs are in this ruku.
  final int ayahCount;
}

/// 15-line page, ruku, para, and para-quarter ends from `english_db.sqlite`.
///
/// Each list is the last app ayah of that unit, in mushaf order. Fatiha
/// bismillah is a database row only, so it is not an end ayah.
class MushafDivisions {
  MushafDivisions({
    required this.pageEnds,
    required this.rukuEnds,
    required this.paraEnds,
    required this.quarterEnds,
    required Map<int, RukuMarkInfo> rukuMarks,
  }) : _rukuMarks = rukuMarks,
       _rukuEndKeys = rukuMarks.keys.toSet(),
       _quarterEndKeys = {for (final end in quarterEnds) _key(end)};

  /// Last ayah of each `PageNum1` page. Index 0 is page 1.
  final List<AyahRef> pageEnds;

  /// Last ayah of each `RukuStart` ruku.
  final List<AyahRef> rukuEnds;

  /// Last ayah of each `ParaStart` para.
  final List<AyahRef> paraEnds;

  /// Last ayah of each `ParaRubaStart` quarter-section.
  final List<AyahRef> quarterEnds;

  final Map<int, RukuMarkInfo> _rukuMarks;
  final Set<int> _rukuEndKeys;
  final Set<int> _quarterEndKeys;

  static MushafDivisions? _cache;
  static Future<MushafDivisions>? _inFlight;

  /// In-memory divisions if [load] has already finished; otherwise `null`.
  static MushafDivisions? get cached => _cache;

  static Future<MushafDivisions> load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= () async {
      final db = await QuranDatabase.instance;
      final rows = await db.rawQuery(
        'SELECT SuraNum, AyaNum, PageNum1, RukuStart, ParaStart, ParaRubaStart '
        'FROM Quran ORDER BY SuraNum, AyaNum',
      );
      final built = MushafDivisions.fromRows(rows);
      _cache = built;
      _inFlight = null;
      return built;
    }();
  }

  factory MushafDivisions.fromRows(List<Map<String, Object?>> rows) {
    final rukuMarks = _rukuMarksFromRows(rows);
    return MushafDivisions(
      pageEnds: _ends(rows, 'PageNum1'),
      rukuEnds: [for (final mark in rukuMarks.values) mark.end],
      paraEnds: _ends(rows, 'ParaStart'),
      quarterEnds: _ends(rows, 'ParaRubaStart'),
      rukuMarks: rukuMarks,
    );
  }

  bool isRukuEnd(int surah, int ayah) =>
      _rukuEndKeys.contains(_keyOf(surah, ayah));

  bool isQuarterEnd(int surah, int ayah) =>
      _quarterEndKeys.contains(_keyOf(surah, ayah));

  RukuMarkInfo? rukuMarkAt(int surah, int ayah) =>
      _rukuMarks[_keyOf(surah, ayah)];

  /// 1-based para (`ParaStart`) that contains this ayah.
  int? paraOf(int surah, int ayah) {
    if (paraEnds.isEmpty) return null;
    final ref = AyahRef(surah, ayah);
    for (var i = 0; i < paraEnds.length; i++) {
      if (ref.compareTo(paraEnds[i]) <= 0) return i + 1;
    }
    return paraEnds.length;
  }

  static int _key(AyahRef ref) => _keyOf(ref.surah, ref.ayah);

  static int _keyOf(int surah, int ayah) => (surah << 16) | ayah;

  static List<AyahRef> _ends(List<Map<String, Object?>> rows, String column) {
    final ends = <AyahRef>[];
    int? key;
    AyahRef? last;
    for (final row in rows) {
      final surah = (row['SuraNum'] as num).toInt();
      final dbAyah = (row['AyaNum'] as num).toInt();
      final appAyah = DbAyah.toApp(surah, dbAyah);
      if (appAyah == null) continue;
      final id = (row[column] as num).toInt();
      if (key != null && id != key && last != null) {
        ends.add(last);
      }
      key = id;
      last = AyahRef(surah, appAyah);
    }
    if (last != null) ends.add(last);
    return ends;
  }

  static Map<int, RukuMarkInfo> _rukuMarksFromRows(
    List<Map<String, Object?>> rows,
  ) {
    final marks = <int, RukuMarkInfo>{};
    int? rukuId;
    AyahRef? last;
    var ayahCount = 0;
    var indexInPara = 0;
    var indexInSurah = 0;
    var lastPara = 0;
    var lastSurah = 0;

    void flush() {
      final end = last;
      if (end == null || ayahCount < 1) return;
      marks[_key(end)] = RukuMarkInfo(
        end: end,
        indexInPara: indexInPara,
        indexInSurah: indexInSurah,
        ayahCount: ayahCount,
      );
    }

    for (final row in rows) {
      final rowSurah = (row['SuraNum'] as num).toInt();
      final dbAyah = (row['AyaNum'] as num).toInt();
      final appAyah = DbAyah.toApp(rowSurah, dbAyah);
      if (appAyah == null) continue;
      final rowRuku = (row['RukuStart'] as num).toInt();
      final rowPara = (row['ParaStart'] as num).toInt();

      if (rukuId != null && rowRuku != rukuId) {
        flush();
        ayahCount = 0;
      }

      if (rukuId == null || rowRuku != rukuId) {
        if (rowPara != lastPara) {
          lastPara = rowPara;
          indexInPara = 1;
        } else {
          indexInPara++;
        }
        if (rowSurah != lastSurah) {
          lastSurah = rowSurah;
          indexInSurah = 1;
        } else {
          indexInSurah++;
        }
        rukuId = rowRuku;
      }

      ayahCount++;
      last = AyahRef(rowSurah, appAyah);
    }
    flush();
    return marks;
  }
}
