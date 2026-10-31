import 'surah_ayah_counts.dart';
import '../data/quran_metadata.dart';
import '../data/quran_models.dart';

/// Stable list layout for the whole mushaf (114 headers + all ayahs).
///
/// Indices never change between the fast window and the full JSON load, so the
/// scroll position does not jump when background parsing finishes.
abstract final class MushafLayout {
  /// Prefetched header list-index for surah 1…114.
  static final List<int> _headerIndex = _buildHeaderIndex();

  static List<int> _buildHeaderIndex() {
    final headers = List<int>.filled(115, 0);
    var index = 0;
    for (var surah = 1; surah <= 114; surah++) {
      headers[surah] = index;
      index += 1 + SurahAyahCounts.of(surah);
    }
    return headers;
  }

  /// Total [ScrollablePositionedList] items: one header + all ayahs per surah.
  static final int itemCount = () {
    var count = 0;
    for (var surah = 1; surah <= 114; surah++) {
      count += 1 + SurahAyahCounts.of(surah);
    }
    return count;
  }();

  static int indexOfSurahHeader(int surah) {
    assert(surah >= 1 && surah <= 114);
    return _headerIndex[surah];
  }

  static int indexOfAyah(int surah, int ayah) {
    assert(surah >= 1 && surah <= 114);
    assert(ayah >= 1 && ayah <= SurahAyahCounts.of(surah));
    return _headerIndex[surah] + ayah;
  }

  /// Resolves a list index to a header or ayah slot.
  static MushafSlot slotAt(int itemIndex) {
    assert(itemIndex >= 0 && itemIndex < itemCount);
    // Binary search the surah whose header index is <= itemIndex.
    var lo = 1;
    var hi = 114;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_headerIndex[mid] <= itemIndex) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final surah = lo;
    final header = _headerIndex[surah];
    if (itemIndex == header) {
      return MushafSlot.header(surah);
    }
    return MushafSlot.ayah(surah, itemIndex - header);
  }

  static QuranSurahHeader headerFor(int surah) {
    return QuranSurahHeader(
      surah: surah,
      nameAr: QuranMetadata.nameArOrEmpty(surah),
    );
  }
}

/// One row in the stable mushaf list.
sealed class MushafSlot {
  const MushafSlot();

  factory MushafSlot.header(int surah) = MushafHeaderSlot;
  factory MushafSlot.ayah(int surah, int ayah) = MushafAyahSlot;
}

final class MushafHeaderSlot extends MushafSlot {
  const MushafHeaderSlot(this.surah);
  final int surah;
}

final class MushafAyahSlot extends MushafSlot {
  const MushafAyahSlot(this.surah, this.ayah);
  final int surah;
  final int ayah;
}
