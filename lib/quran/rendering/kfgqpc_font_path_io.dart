import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

String? _cachedIoPath;

Future<String> resolveFilesystemPath(String assetKey) async {
  if (_cachedIoPath != null && File(_cachedIoPath!).existsSync()) {
    return _cachedIoPath!;
  }

  final data = await rootBundle.load(assetKey);
  final bytes = data.buffer.asUint8List();
  final dir = await Directory.systemTemp.createTemp('kfgqpc_nastaleeq_');
  final file = File('${dir.path}/KFGQPCNastaleeq-Regular.ttf');
  await file.writeAsBytes(bytes, flush: true);
  _cachedIoPath = file.path;
  return _cachedIoPath!;
}

bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;
