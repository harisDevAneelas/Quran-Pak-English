library;

import '../bundled_fonts.dart';
import '../ffi/ffi_shaper.dart';
import '../justify/hb_shaper.dart';

final Map<String, Future<HbShaper>> _cache = {};
final Map<String, HbShaper> _ready = {};

String _key(String? fontPath, JustificationFont font) =>
    fontPath ?? font.assetKey;

/// Synchronously returns a shaper if [warmJustificationShaper] / a prior load
/// already completed for this font.
HbShaper? peekJustificationShaper(
  String? fontPath, {
  JustificationFont font = JustificationFont.defaultFont,
}) =>
    _ready[_key(fontPath, font)];

Future<HbShaper> resolveShaper(
  String? fontPath, {
  JustificationFont font = JustificationFont.defaultFont,
}) {
  final key = _key(fontPath, font);
  return _cache.putIfAbsent(key, () async {
    final HbShaper shaper;
    if (fontPath != null) {
      shaper = await FfiShaper.load(fontPath);
    } else {
      final bytes = await font.loadBytes();
      shaper = await FfiShaper.loadBytes(bytes);
    }
    _ready[key] = shaper;
    return shaper;
  });
}

/// Ensures the font/shaper is loaded before reading begins.
Future<HbShaper> warmJustificationShaper(
  String? fontPath, {
  JustificationFont font = JustificationFont.defaultFont,
}) =>
    resolveShaper(fontPath, font: font);
