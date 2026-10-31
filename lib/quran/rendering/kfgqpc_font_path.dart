import 'package:flutter/foundation.dart' show kIsWeb;

import 'kfgqpc_font_path_io.dart'
    if (dart.library.html) 'kfgqpc_font_path_web.dart'
    as io_impl;

/// Path or asset key for KFGQPC Nastaleeq (never Madinah / DigitalKhatt).
abstract final class KfgqpcFontPath {
  static const assetKey = 'assets/fonts/KFGQPCNastaleeq-Regular.ttf';

  static Future<String> resolve() async {
    if (kIsWeb) {
      return assetKey;
    }
    return io_impl.resolveFilesystemPath(assetKey);
  }

  /// Official FFI: Android + iOS. Web works with our patched loader.
  /// macOS/Windows/Linux desktop are not supported by upstream.
  static bool get isSupportedPlatform => io_impl.isSupportedPlatform;
}
