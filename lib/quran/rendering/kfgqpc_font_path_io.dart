import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

final Map<String, String> _cachedIoPaths = {};

Future<String> resolveFilesystemPath(String assetKey) async {
  final cached = _cachedIoPaths[assetKey];
  if (cached != null && File(cached).existsSync()) {
    return cached;
  }

  final data = await rootBundle.load(assetKey);
  final bytes = data.buffer.asUint8List();
  final fileName = p.basename(assetKey);
  final dir = await Directory.systemTemp.createTemp('mushaf_font_');
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  _cachedIoPaths[assetKey] = file.path;
  return file.path;
}

bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;
