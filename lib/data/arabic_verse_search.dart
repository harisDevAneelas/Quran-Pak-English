import 'quran_models.dart';
import 'quran_repository.dart';

/// One mushaf word occurrence that search can jump to.
class ArabicVerseHit {
  const ArabicVerseHit({
    required this.word,
    required this.surah,
    required this.ayah,
  });

  final String word;
  final int surah;
  final int ayah;
}

/// In-memory Arabic word index over the full mushaf (harakat stripped).
abstract final class ArabicVerseSearch {
  static List<_IndexedWord>? _index;
  static Future<List<_IndexedWord>>? _inFlight;

  static const int defaultLimit = 100;

  /// Ensures the full mushaf index is ready.
  static Future<void> ensureReady({
    QuranDataRepository? repository,
  }) async {
    if (_index != null) return;
    final existing = _inFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _build(repository ?? QuranDataRepository());
    _inFlight = future;
    try {
      _index = await future;
    } finally {
      _inFlight = null;
    }
  }

  static Future<List<_IndexedWord>> _build(QuranDataRepository repo) async {
    final mushaf = await repo.loadFull();
    final entries = <_IndexedWord>[];
    for (final item in mushaf.items) {
      if (item is! AyahItem) continue;
      final chunk = item.chunk;
      for (final word in chunk.words) {
        final text = word.text.trim();
        if (text.isEmpty) continue;
        final key = normalizeArabic(text);
        if (key.isEmpty) continue;
        entries.add(
          _IndexedWord(
            key: key,
            word: text,
            surah: chunk.surah,
            ayah: chunk.ayah,
          ),
        );
      }
    }
    return entries;
  }

  /// Substring match on normalized Arabic. Empty [query] → no hits.
  static List<ArabicVerseHit> search(
    String query, {
    int limit = defaultLimit,
  }) {
    final index = _index;
    if (index == null || index.isEmpty) return const [];
    final needle = normalizeArabic(query.trim());
    if (needle.isEmpty) return const [];

    final hits = <ArabicVerseHit>[];
    for (final entry in index) {
      if (!entry.key.contains(needle)) continue;
      hits.add(
        ArabicVerseHit(
          word: entry.word,
          surah: entry.surah,
          ayah: entry.ayah,
        ),
      );
      if (hits.length >= limit) break;
    }
    return hits;
  }

  /// Letters only — drop harakat, Quranic marks, and tatweel.
  static String normalizeArabic(String input) {
    final buffer = StringBuffer();
    for (final unit in input.runes) {
      if (_isSkippableMark(unit)) continue;
      buffer.writeCharCode(_foldLetter(unit));
    }
    return buffer.toString();
  }

  static bool _isSkippableMark(int unit) {
    // Tatweel
    if (unit == 0x0640) return true;
    // Harakat / Quranic annotation marks commonly in mushaf text
    if (unit >= 0x064B && unit <= 0x065F) return true;
    if (unit == 0x0670) return true; // superscript alef
    if (unit >= 0x06D6 && unit <= 0x06ED) return true;
    if (unit >= 0x08D3 && unit <= 0x08FF) return true;
    return false;
  }

  static int _foldLetter(int unit) {
    // Common alef / ya / ta marbuta folds for looser typing.
    return switch (unit) {
      0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627, // آ أ إ ٱ → ا
      0x0649 => 0x064A, // ى → ي
      0x0629 => 0x0647, // ة → ه
      _ => unit,
    };
  }
}

class _IndexedWord {
  const _IndexedWord({
    required this.key,
    required this.word,
    required this.surah,
    required this.ayah,
  });

  final String key;
  final String word;
  final int surah;
  final int ayah;
}
