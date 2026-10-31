import 'package:flutter/material.dart';

import '../data/quran_models.dart';

/// Maps JSON color names to paint colors at render time.
abstract final class TajweedPalette {
  static const Color green = Color(0xFF30A35B);
  static const Color red = Color(0xFFF30A3C);
  static const Color blue = Color(0xFF309CE3);

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
      default:
        return TajweedColorName.none;
    }
  }
}
