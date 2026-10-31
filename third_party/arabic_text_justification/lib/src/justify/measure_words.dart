import '../bundled_fonts.dart';
import '../platform/shaper_loader.dart';
import 'hb_shaper.dart';

/// Logical-pixel width of [words] joined with spaces, shaped the same way as
/// [JustifiedArabicLine] (`justify: false`).
///
/// Returns null when the HarfBuzz shaper is not ready yet — callers should
/// fall back to another measure and rebuild after [warmJustificationShaper].
double? measureJustificationWordsWidth({
  required List<String> words,
  required double fontSize,
  String? fontPath,
  JustificationFont font = JustificationFont.defaultFont,
}) {
  if (words.isEmpty || fontSize <= 0) return 0;
  final shaper = peekJustificationShaper(fontPath, font: font);
  if (shaper == null) return null;
  return _widthOf(shaper, words.join(' '), fontSize);
}

double _widthOf(HbShaper shaper, String text, double fontSize) {
  shaper.setTatweel(0);
  final fu = shaper.measure(text, const []).toDouble();
  if (fu <= 0) return 0;
  return fu / shaper.unitsPerEm * fontSize;
}
