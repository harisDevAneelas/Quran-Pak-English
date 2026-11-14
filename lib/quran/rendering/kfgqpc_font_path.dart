import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/mushaf_script.dart';
import 'kfgqpc_font_path_io.dart'
    if (dart.library.html) 'kfgqpc_font_path_web.dart'
    as io_impl;

/// Path or asset key for the active mushaf face (KFGQPC or DigitalKhatt V2).
abstract final class KfgqpcFontPath {
  /// IndoPak / KFGQPC asset (kept for call-site compatibility).
  static const assetKey = 'assets/fonts/KFGQPCNastaleeq-Regular.ttf';

  static String assetKeyFor(MushafScript script) => script.fontAssetKey;

  static Future<String> resolve([MushafScript script = MushafScript.indopak]) async {
    final key = assetKeyFor(script);
    if (kIsWeb) {
      return key;
    }
    return io_impl.resolveFilesystemPath(key);
  }

  /// Resolves and warms HarfBuzz for every mushaf face (no-op reload later).
  static Future<Map<MushafScript, String>> resolveAll() async {
    final entries = await Future.wait([
      for (final script in MushafScript.values)
        resolve(script).then((path) => MapEntry(script, path)),
    ]);
    return Map<MushafScript, String>.fromEntries(entries);
  }

  /// Official FFI: Android + iOS. Web works with our patched loader.
  /// macOS/Windows/Linux desktop are not supported by upstream.
  static bool get isSupportedPlatform => io_impl.isSupportedPlatform;
}
