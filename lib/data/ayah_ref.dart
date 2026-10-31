import '../core/surah_ayah_counts.dart';

/// One ayah position in the mushaf (`surah` + `ayah`, both 1-based).
class AyahRef implements Comparable<AyahRef> {
  const AyahRef(this.surah, this.ayah);

  final int surah;
  final int ayah;

  static const first = AyahRef(1, 1);
  static const last = AyahRef(114, 6);

  /// 0-based index across the whole mushaf (0 … [SurahAyahCounts.totalAyahs]-1).
  int get absoluteIndex {
    var index = ayah - 1;
    for (var s = 1; s < surah; s++) {
      index += SurahAyahCounts.of(s);
    }
    return index;
  }

  static AyahRef fromAbsolute(int absolute) {
    assert(absolute >= 0 && absolute < SurahAyahCounts.totalAyahs);
    var remaining = absolute;
    for (var s = 1; s <= 114; s++) {
      final count = SurahAyahCounts.of(s);
      if (remaining < count) {
        return AyahRef(s, remaining + 1);
      }
      remaining -= count;
    }
    return last;
  }

  /// Inclusive window around [center], [radius] ayahs each direction.
  static (AyahRef start, AyahRef end) windowAround(
    AyahRef center, {
    required int radius,
  }) {
    final c = center.absoluteIndex;
    final start = (c - radius).clamp(0, SurahAyahCounts.totalAyahs - 1);
    final end = (c + radius).clamp(0, SurahAyahCounts.totalAyahs - 1);
    return (fromAbsolute(start), fromAbsolute(end));
  }

  AyahRef clampToSurah() {
    final maxAyah = SurahAyahCounts.of(surah);
    final a = ayah.clamp(1, maxAyah);
    return AyahRef(surah, a);
  }

  @override
  int compareTo(AyahRef other) => absoluteIndex.compareTo(other.absoluteIndex);

  @override
  bool operator ==(Object other) =>
      other is AyahRef && other.surah == surah && other.ayah == ayah;

  @override
  int get hashCode => Object.hash(surah, ayah);

  @override
  String toString() => '$surah:$ayah';
}

/// Inclusive ayah range used for lazy mushaf windows.
class AyahWindow {
  const AyahWindow({required this.start, required this.end});

  final AyahRef start;
  final AyahRef end;

  bool contains(int surah, int ayah) {
    final ref = AyahRef(surah, ayah);
    return ref.absoluteIndex >= start.absoluteIndex &&
        ref.absoluteIndex <= end.absoluteIndex;
  }

  AyahWindow expandToInclude(AyahWindow other) {
    final s = start.absoluteIndex <= other.start.absoluteIndex
        ? start
        : other.start;
    final e =
        end.absoluteIndex >= other.end.absoluteIndex ? end : other.end;
    return AyahWindow(start: s, end: e);
  }

  @override
  bool operator ==(Object other) =>
      other is AyahWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
