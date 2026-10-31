import 'package:flutter/painting.dart';

/// Mushaf face is [family]; word-by-word Arabic is [wordByWordFamily].
/// Keep line height at or above [recommendedLineHeight] so KFGQPC ink is not clipped.
abstract final class QuranFont {
  static const String family = 'KFGQPCNastaleeq';

  /// Word-by-word Arabic (`AlQuranIndoPak.ttf`).
  static const String wordByWordFamily = 'AlQuranIndoPak';

  static const double wordByWordLineHeight = 2.0;

  static const double recommendedLineHeight = 2.0;

  static const TextStyle base = TextStyle(
    fontFamily: family,
    fontFamilyFallback: <String>[],
    letterSpacing: 0,
    wordSpacing: 2,
  );
}
