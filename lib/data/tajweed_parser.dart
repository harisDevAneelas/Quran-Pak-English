import 'dart:convert';

import 'ayah_ref.dart';
import 'quran_metadata.dart';
import 'quran_models.dart';
import 'tajweed_span_builder.dart';

/// Parses `quran.colored.json` (or a window subset) into [ProcessedQuran].
class TajweedParser {
  const TajweedParser({
    this.validateInDebug = true,
    this.spanBuilder = const TajweedSpanBuilder(),
  });

  final bool validateInDebug;
  final TajweedSpanBuilder spanBuilder;

  static ProcessedQuran parseJsonString(
    String jsonString, {
    AyahWindow? window,
  }) {
    return TajweedParser().parse(
      json.decode(jsonString) as Map<String, dynamic>,
      window: window,
    );
  }

  /// When [window] is set, only ayahs inside that inclusive range are built.
  ProcessedQuran parse(Map<String, dynamic> raw, {AyahWindow? window}) {
    final items = <QuranReaderItem>[];
    final surahToItemIndex = <int, int>{};
    final ayahToItemIndex = <String, int>{};

    var wordCount = 0;
    var ayahCount = 0;
    var lastSurah = 0;
    var lastAyah = 0;

    var currentSurah = 0;
    var currentAyah = 0;
    final words = <({String text, List<Map<String, dynamic>> highlights})>[];

    void flushAyah() {
      if (words.isEmpty) return;

      final chunk = QuranAyahChunk(
        surah: currentSurah,
        ayah: currentAyah,
        words: List<QuranWord>.unmodifiable([
          for (final w in words)
            QuranWord(
              text: w.text,
              colorRanges: List<QuranWordColorRange>.unmodifiable(
                spanBuilder.buildWordColorRanges(
                  text: w.text,
                  highlights: w.highlights,
                ),
              ),
            ),
        ]),
      );

      final index = items.length;
      items.add(AyahItem(chunk));
      ayahToItemIndex['$currentSurah:$currentAyah'] = index;
      ayahCount++;
      wordCount += words.length;
      words.clear();
    }

    for (final entry in raw.entries) {
      final parts = entry.key.split(':');
      if (parts.length != 3) {
        throw FormatException('Invalid word key: ${entry.key}');
      }

      final surah = int.parse(parts[0]);
      final ayah = int.parse(parts[1]);
      final wordIndex = int.parse(parts[2]);

      if (window != null) {
        final ref = AyahRef(surah, ayah);
        if (ref.absoluteIndex > window.end.absoluteIndex) {
          break;
        }
        if (!window.contains(surah, ayah)) {
          continue;
        }
      }

      final value = entry.value as Map<String, dynamic>;
      final text = value['text'] as String;
      final highlights = (value['highlights'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

      if (text.isEmpty) {
        throw FormatException('Empty text at ${entry.key}');
      }

      if (surah != currentSurah || ayah != currentAyah) {
        flushAyah();

        if (surah != lastSurah) {
          if (surah < lastSurah) {
            throw FormatException('Surah out of order at ${entry.key}');
          }
          surahToItemIndex[surah] = items.length;
          items.add(
            SurahHeaderItem(
              QuranSurahHeader(
                surah: surah,
                nameAr: QuranMetadata.nameArOrEmpty(surah),
              ),
            ),
          );
          lastSurah = surah;
        } else if (ayah < lastAyah && currentSurah == surah) {
          throw FormatException('Ayah out of order at ${entry.key}');
        }

        currentSurah = surah;
        currentAyah = ayah;
        lastAyah = ayah;
      }

      assert(() {
        if (words.length + 1 != wordIndex) {
          throw AssertionError(
            'Expected word $surah:$ayah:${words.length + 1}, got ${entry.key}',
          );
        }
        return true;
      }());

      assert(() {
        if (validateInDebug) {
          validateHighlightEntry(
            text: text,
            highlights: highlights,
            key: entry.key,
          );
        }
        return true;
      }());

      words.add((text: text, highlights: highlights));
    }

    flushAyah();

    assert(() {
      if (validateInDebug) {
        _debugValidate(items, wordCount, ayahCount);
      }
      return true;
    }());

    return ProcessedQuran(
      items: List<QuranReaderItem>.unmodifiable(items),
      surahToItemIndex: Map<int, int>.unmodifiable(surahToItemIndex),
      ayahToItemIndex: Map<String, int>.unmodifiable(ayahToItemIndex),
      surahCount: surahToItemIndex.length,
      ayahCount: ayahCount,
      wordCount: wordCount,
    );
  }

  static void _debugValidate(
    List<QuranReaderItem> items,
    int wordCount,
    int ayahCount,
  ) {
    var seenAyahs = 0;
    var reconstructedWords = 0;
    for (final item in items) {
      switch (item) {
        case SurahHeaderItem():
          break;
        case AyahItem(:final chunk):
          seenAyahs++;
          reconstructedWords += chunk.wordCount;
          for (final word in chunk.words) {
            for (final range in word.colorRanges) {
              if (range.start < 0 ||
                  range.end > word.text.length ||
                  range.start >= range.end) {
                throw StateError(
                  'Color range out of bounds at ${chunk.surah}:${chunk.ayah}',
                );
              }
            }
          }
      }
    }
    if (seenAyahs != ayahCount || reconstructedWords != wordCount) {
      throw StateError('Validation counters mismatch');
    }
  }
}
