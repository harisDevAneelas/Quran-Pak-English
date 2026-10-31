import 'package:arabic_text_justification/arabic_text_justification.dart';
import 'package:flutter/painting.dart';

import '../../core/tajweed_palette.dart';
import '../../data/quran_models.dart';

/// Maps precomputed word ranges to HarfBuzz [WordColorSpan]s.
abstract final class TajweedWordColorSpans {
  static List<WordColorSpan> fromPrecomputed({
    required int wordIndex,
    required List<QuranWordColorRange> ranges,
    required Color ink,
  }) {
    if (ranges.isEmpty) return const [];
    return [
      for (final r in ranges)
        WordColorSpan(
          wordIndex: wordIndex,
          start: r.start,
          end: r.end,
          color: TajweedPalette.resolve(r.color, ink),
        ),
    ];
  }
}
