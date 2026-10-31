library;

import 'package:flutter/services.dart' show rootBundle;

import '../bundled_fonts.dart';
import '../justify/hb_shaper.dart';
import '../web/web_shaper.dart';

final Map<String, Future<HbShaper>> _cache = {};
final Map<String, HbShaper> _ready = {};

String _normalizePath(String fontPath) => fontPath.startsWith('asset:')
    ? fontPath.substring('asset:'.length)
    : fontPath;

String _key(String? fontPath, JustificationFont font) {
  if (fontPath != null && fontPath.isNotEmpty) {
    return _normalizePath(fontPath);
  }
  return font.assetKey;
}

/// Synchronously returns a shaper if already warmed/loaded.
HbShaper? peekJustificationShaper(
  String? fontPath, {
  JustificationFont font = JustificationFont.defaultFont,
}) =>
    _ready[_key(fontPath, font)];

/// Web shaper resolver.
///
/// Upstream ignores [fontPath] and always loads a bundled font. This fork
/// honors [fontPath] as a Flutter **asset key** so callers can shape with
/// KFGQPC Nastaleeq (or any other TTF/OTF) via [WebShaper.load].
Future<HbShaper> resolveShaper(
  String? fontPath, {
  JustificationFont font = JustificationFont.defaultFont,
}) {
  final key = _key(fontPath, font);
  return _cache.putIfAbsent(key, () async {
    final HbShaper shaper;
    if (fontPath != null && fontPath.isNotEmpty) {
      final data = await rootBundle.load(_normalizePath(fontPath));
      shaper = await WebShaper.load(data.buffer.asUint8List());
    } else {
      final bytes = await font.loadBytes();
      shaper = await WebShaper.load(bytes);
    }
    _ready[key] = shaper;
    return shaper;
  });
}

Future<HbShaper> warmJustificationShaper(
  String? fontPath, {
  JustificationFont font = JustificationFont.defaultFont,
}) =>
    resolveShaper(fontPath, font: font);
