import 'package:flutter/painting.dart';

import 'mushaf_script.dart';

/// Mushaf face follows [MushafScript]; word-by-word Arabic is [wordByWordFamily].
/// Keep line height at or above [recommendedLineHeight] so tall ink is not clipped.
abstract final class QuranFont {
  /// Default mushaf family (IndoPak / KFGQPC). Prefer [familyFor].
  static const String family = 'KFGQPCNastaleeq';

  static const String digitalKhattFamily = 'DigitalKhattV2';

  /// Word-by-word Arabic (`AlQuranIndoPak.ttf`).
  static const String wordByWordFamily = 'AlQuranIndoPak';

  static const double wordByWordLineHeight = 2.0;

  static const double recommendedLineHeight = 2.0;

  static String familyFor(MushafScript script) => script.fontFamily;

  static TextStyle baseFor(MushafScript script) => TextStyle(
        fontFamily: familyFor(script),
        fontFamilyFallback: const <String>[],
        letterSpacing: 0,
        wordSpacing: 2,
      );

  static const TextStyle base = TextStyle(
    fontFamily: family,
    fontFamilyFallback: <String>[],
    letterSpacing: 0,
    wordSpacing: 2,
  );
}
