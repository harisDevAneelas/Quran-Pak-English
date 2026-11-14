import 'dart:convert';

import '../core/mushaf_script.dart';
import 'ayah_ref.dart';
import 'quran_database.dart';
import 'quran_models.dart';
import 'quran_repository.dart';
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

  /// Maps seeded IndoPak [VerseCollection.verses] onto [script] orthography.
  ///
  /// `DuaWords` stores IndoPak spans (sometimes mid-ayah). Word counts match
  /// Uthmani, so the same start/length slice is taken from the active mushaf.
  static Future<VerseCollection> forScript(
    VerseCollection base,
    MushafScript script,
  ) async {
    if (script == MushafScript.indopak) return base;

    final target = await QuranDataRepository.forScript(script).loadFull();
    final indopak =
        await QuranDataRepository.forScript(MushafScript.indopak).loadFull();

    final groups = <VerseGroup>[
      for (final group in base.groups)
        VerseGroup(
          number: group.number,
          ayahs: group.ayahs,
          verses: [
            for (var i = 0; i < group.ayahs.length; i++)
              _verseForScript(
                ref: group.ayahs[i],
                stored: i < group.verses.length
                    ? group.verses[i]
                    : const <QuranWord>[],
                indopak: indopak,
                target: target,
              ),
          ],
        ),
    ];
    return VerseCollection(id: base.id, title: base.title, groups: groups);
  }

  static List<QuranWord> _verseForScript({
    required AyahRef ref,
    required List<QuranWord> stored,
    required ProcessedQuran indopak,
    required ProcessedQuran target,
  }) {
    final fullTarget = target.ayahAt(ref.surah, ref.ayah)?.words ?? const [];
    if (stored.isEmpty) return fullTarget;
    if (stored.length == fullTarget.length) return fullTarget;

    final fullIndo = indopak.ayahAt(ref.surah, ref.ayah)?.words ?? const [];
    final start = _spanStart(fullIndo, stored);
    if (start == null || start + stored.length > fullTarget.length) {
      return fullTarget;
    }
    return fullTarget.sublist(start, start + stored.length);
  }

  static int? _spanStart(List<QuranWord> full, List<QuranWord> span) {
    if (span.isEmpty || span.length > full.length) return null;
    for (var i = 0; i <= full.length - span.length; i++) {
      var match = true;
      for (var j = 0; j < span.length; j++) {
        if (full[i + j].text != span[j].text) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return null;
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
