/// Immutable Quran + Tajweed models from [TajweedParser].
///
/// Colored JSON keys are `"surah:ayah:word"`. Highlight `index` values are
/// UTF-16 code units, half-open `[start, end)`.
library;

enum TajweedColorName { none, green, red, blue }

/// Precomputed UTF-16 half-open color range inside one word.
class QuranWordColorRange {
  const QuranWordColorRange({
    required this.start,
    required this.end,
    required this.color,
  });

  final int start;
  final int end;
  final TajweedColorName color;
}

class QuranAyahChunk {
  const QuranAyahChunk({
    required this.surah,
    required this.ayah,
    required this.words,
  });

  final int surah;
  final int ayah;
  final List<QuranWord> words;

  int get wordCount => words.length;
}

class QuranWord {
  const QuranWord({
    required this.text,
    this.colorRanges = const [],
  });

  final String text;
  final List<QuranWordColorRange> colorRanges;
}

class QuranSurahHeader {
  const QuranSurahHeader({required this.surah, required this.nameAr});

  final int surah;
  final String nameAr;
}

sealed class QuranReaderItem {
  const QuranReaderItem();
}

class SurahHeaderItem extends QuranReaderItem {
  const SurahHeaderItem(this.header);
  final QuranSurahHeader header;
}

class AyahItem extends QuranReaderItem {
  const AyahItem(this.chunk);
  final QuranAyahChunk chunk;
}

class ProcessedQuran {
  const ProcessedQuran({
    required this.items,
    required this.surahToItemIndex,
    required this.ayahToItemIndex,
    required this.surahCount,
    required this.ayahCount,
    required this.wordCount,
  });

  final List<QuranReaderItem> items;
  final Map<int, int> surahToItemIndex;
  final Map<String, int> ayahToItemIndex;
  final int surahCount;
  final int ayahCount;
  final int wordCount;

  int? indexOfAyah(int surah, int ayah) => ayahToItemIndex['$surah:$ayah'];

  QuranAyahChunk? ayahAt(int surah, int ayah) {
    final index = indexOfAyah(surah, ayah);
    if (index == null || index < 0 || index >= items.length) return null;
    final item = items[index];
    return item is AyahItem ? item.chunk : null;
  }
}
