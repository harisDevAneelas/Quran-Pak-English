import 'dart:convert';

import 'ayah_ref.dart';
import 'quran_database.dart';
import 'quran_models.dart';
import 'tajweed_span_builder.dart';
import 'verse_collections.dart';

abstract final class VerseCollectionRepository {
  static const _spanBuilder = TajweedSpanBuilder();

  static Future<VerseCollection?> load(String duaId) async {
    final db = await QuranDatabase.instance;
    final rows = await db.rawQuery(
      'SELECT DuaId, DuaNumber, SuraNum, AyaFrom, AyaTo, DuaWords '
      'FROM QuraniDua WHERE DuaId = ? ORDER BY DuaNumber, QuraniDuaId',
      [duaId],
    );
    return fromRows(rows);
  }

  static VerseCollection? fromRows(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return null;

    final id = rows.first['DuaId'] as String;
    final title = VerseCollectionIds.titleOf(id);
    if (title == null) return null;
    final groups = <VerseGroup>[];
    VerseGroup? current;

    for (final row in rows) {
      final number = _asInt(row['DuaNumber']);
      final surah = _asInt(row['SuraNum']);
      final from = _asInt(row['AyaFrom']);
      final to = _asInt(row['AyaTo']);
      final ayahs = [
        for (var ayah = from; ayah <= to; ayah++) AyahRef(surah, ayah),
      ];
      final verses = versesFromJson(row['DuaWords'] as String?);
      if (current == null || current.number != number) {
        current = VerseGroup(number: number, ayahs: ayahs, verses: verses);
        groups.add(current);
      } else {
        current = VerseGroup(
          number: number,
          ayahs: [...current.ayahs, ...ayahs],
          verses: [...current.verses, ...verses],
        );
        groups[groups.length - 1] = current;
      }
    }

    return VerseCollection(id: id, title: title, groups: groups);
  }

  /// `DuaWords` is a list of ayahs, each an array of `{text, highlights}`.
  static List<List<QuranWord>> versesFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final parsed = jsonDecode(raw);
    if (parsed is! List || parsed.isEmpty) return const [];
    if (parsed.first is List) {
      return [
        for (final verse in parsed)
          if (verse is List) _wordsFromList(verse),
      ];
    }
    return [_wordsFromList(parsed)];
  }

  static List<QuranWord> _wordsFromList(List<dynamic> items) {
    return [
      for (final item in items)
        if (item is Map)
          QuranWord(
            text: '${item['text'] ?? ''}',
            colorRanges: _spanBuilder.buildWordColorRanges(
              text: '${item['text'] ?? ''}',
              highlights: [
                for (final h in item['highlights'] as List? ?? const [])
                  if (h is Map) Map<String, dynamic>.from(h),
              ],
            ),
          ),
    ];
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.parse('$value');
  }
}
