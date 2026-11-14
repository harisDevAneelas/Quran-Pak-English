import '../core/tajweed_palette.dart';
import 'quran_models.dart';

/// Builds precomputed Tajweed color ranges from JSON highlights.
class TajweedSpanBuilder {
  const TajweedSpanBuilder();

  List<TajweedColorName> buildColorMask({
    required String text,
    required List<Map<String, dynamic>> highlights,
    String? debugKey,
  }) {
    final mask = List<TajweedColorName>.filled(
      text.length,
      TajweedColorName.none,
    );

    for (final raw in highlights) {
      final index = raw['index'] as int;
      final expectedChar = raw['char'] as String;
      final color = TajweedPalette.fromJsonName(raw['color'] as String?);

      validateHighlight(
        text: text,
        index: index,
        jsonChar: expectedChar,
        debugKey: debugKey,
      );

      mask[index] = color;
    }

    return mask;
  }

  static void validateHighlight({
    required String text,
    required int index,
    required String jsonChar,
    String? debugKey,
  }) {
    if (index < 0 || index >= text.length) {
      throw FormatException(
        'Highlight index $index out of range '
        '(len=${text.length}${debugKey != null ? ', key=$debugKey' : ''})',
      );
    }
    final sourceChar = text[index];
    if (sourceChar != jsonChar) {
      throw FormatException(
        'Highlight char mismatch'
        '${debugKey != null ? ' at $debugKey' : ''}: '
        'index=$index jsonChar=$jsonChar sourceChar=$sourceChar',
      );
    }
  }

  List<QuranWordColorRange> buildWordColorRanges({
    required String text,
    required List<Map<String, dynamic>> highlights,
    String? debugKey,
  }) {
    if (highlights.isEmpty || text.isEmpty) return const [];
    final mask = buildColorMask(
      text: text,
      highlights: highlights,
      debugKey: debugKey,
    );
    final out = <QuranWordColorRange>[];
    var i = 0;
    while (i < mask.length) {
      final c = mask[i];
      var j = i + 1;
      while (j < mask.length && mask[j] == c) {
        j++;
      }
      if (c != TajweedColorName.none) {
        out.add(QuranWordColorRange(start: i, end: j, color: c));
      }
      i = j;
    }
    return out;
  }
}

void validateHighlightEntry({
  required String text,
  required List<Map<String, dynamic>> highlights,
  String? key,
}) {
  for (final h in highlights) {
    TajweedSpanBuilder.validateHighlight(
      text: text,
      index: h['index'] as int,
      jsonChar: h['char'] as String,
      debugKey: key,
    );
  }
}
