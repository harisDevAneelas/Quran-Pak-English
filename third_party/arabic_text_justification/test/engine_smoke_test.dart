import 'package:arabic_text_justification/src/justify/engine.dart';
import 'package:arabic_text_justification/src/justify/hb_shaper.dart';
import 'package:arabic_text_justification/src/justify/line_analyzer.dart';
import 'package:arabic_text_justification/src/justify/types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic shaper: one glyph per code unit, fixed advance, features
/// ignored. Enough to exercise the engine's control flow and width math without
/// a real font. (Kashida *correctness* is validated separately by the golden
/// test against the website's output.)
class FakeShaper extends HbShaper {
  final int adv;
  FakeShaper([this.adv = 600]);

  @override
  int get unitsPerEm => 1000;

  @override
  List<HbGlyph> shape(String text, List<HbFeature> features) => [
        for (var i = 0; i < text.length; i++)
          HbGlyph(text.codeUnitAt(i), i, adv, 0, 0, 0),
      ];

  @override
  List<OutlineCommand> glyphOutline(int glyphId) => const [];

  @override
  ({int ascender, int descender}) get fontMetrics =>
      (ascender: 800, descender: -200);
}

void main() {
  final shaper = FakeShaper();
  const line = 'بسم الله الرحمن الرحيم';

  test('stretch path: distributes extra width to spaces without throwing', () {
    final info = analyzeLineForJust(line);
    // Small ratio → large desiredWidth → line must stretch.
    final result = justifyLine(info, shaper, 0.02, 300);

    expect(result.xScale, 1.0); // no horizontal scaling when stretching
    expect(result.simpleSpacing, greaterThanOrEqualTo(300));
    expect(result.ayaSpacing, greaterThanOrEqualTo(300));
  });

  test('shrink path: applies xScale < 1 when the line is too wide', () {
    final info = analyzeLineForJust(line);
    // Large ratio → small desiredWidth → line must shrink.
    final result = justifyLine(info, shaper, 5.0, 300);

    expect(result.xScale, lessThan(1.0));
    expect(result.xScale, greaterThan(0));
  });

  test('runs the experimental (madina) pass without throwing', () {
    final info = analyzeLineForJust(line);
    final result = justifyLine(info, shaper, 0.02, 300,
        mushafType: MushafLayoutType.newMadinah);
    expect(result, isNotNull);
  });

  test('runs the simple (indopak) pass without throwing', () {
    final info = analyzeLineForJust(line);
    final result = justifyLine(info, shaper, 0.02, 300,
        mushafType: MushafLayoutType.indoPak15Lines);
    expect(result, isNotNull);
  });
}
