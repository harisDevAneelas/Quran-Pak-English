import 'package:flutter/material.dart';

import '../data/quran_models.dart';

/// Maps JSON color names to paint colors at render time.
///
/// IndoPak colored JSON uses green / red / blue.
/// Uthmani: gray / light-orange (separated madd) / red / maroon / green / cyan /
/// purple→indigo tafkhim. Natural two-count madd is left uncolored.
abstract final class TajweedPalette {
  /// Ghunna / ikhfa’ (legend green).
  static const Color green = Color(0xFF1E9A11);

  /// Connected madd 4/5 (legend bright red). IndoPak madd also uses this.
  static const Color red = Color(0xFFD40302);

  /// IndoPak third color (unchanged role).
  static const Color blue = Color(0xFF309CE3);

  /// Qalqala / echo (legend light blue).
  static const Color cyan = Color(0xFF3098DE);

  /// Tafkhim / heavy — JSON name stays `purple`; paint is legend indigo.
  static const Color purple = Color(0xFF3942C9);

  /// Silent letter (legend grey), including U+06DF sifr mustadir.
  static const Color gray = Color(0xFF888888);

  /// Unused for Uthmani paint (two-count madd stays ink).
  static const Color gold = Color(0xFFB58B0E);

  /// Separated / arid madd — light orange.
  static const Color orange = Color(0xFFF0A83A);

  /// Necessary madd (6).
  static const Color maroon = Color(0xFF9F0D0F);

  static Color resolve(TajweedColorName name, Color fallback) {
    switch (name) {
      case TajweedColorName.none:
        return fallback;
      case TajweedColorName.green:
        return green;
      case TajweedColorName.red:
        return red;
      case TajweedColorName.blue:
        return blue;
      case TajweedColorName.cyan:
        return cyan;
      case TajweedColorName.purple:
        return purple;
      case TajweedColorName.gray:
        return gray;
      case TajweedColorName.gold:
        return gold;
      case TajweedColorName.orange:
        return orange;
      case TajweedColorName.maroon:
        return maroon;
    }
  }

  static TajweedColorName fromJsonName(String? raw) {
    switch (raw) {
      case 'green':
        return TajweedColorName.green;
      case 'red':
        return TajweedColorName.red;
      case 'blue':
        return TajweedColorName.blue;
      case 'cyan':
        return TajweedColorName.cyan;
      case 'purple':
        return TajweedColorName.purple;
      case 'gray':
      case 'grey':
        return TajweedColorName.gray;
      case 'gold':
      case 'yellow':
        return TajweedColorName.gold;
      case 'orange':
        return TajweedColorName.orange;
      case 'maroon':
      case 'darkRed':
        return TajweedColorName.maroon;
      default:
        return TajweedColorName.none;
    }
  }
}
