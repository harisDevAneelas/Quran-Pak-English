import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ayah_audio_cache_policy.dart';

const _subdir = 'ayah_audio';

Directory? _dir;
final Map<String, Future<String>> _inflight = {};
int _prefetchGen = 0;
bool _maintenanceQueued = false;

Future<String> resolve(String url) async {
  final file = await _fileFor(url);
  if (await file.exists() && await file.length() > 0) {
    return file.uri.toString();
  }
  return url;
}

/// Cached file, or the in-flight prefetch if this ayah is already downloading.
/// Otherwise the CDN URL so the current ayah can start without waiting.
Future<String> playable(String url) async {
  final cached = await resolve(url);
  if (cached != url) return cached;
  final pending = _inflight[url];
  if (pending != null) return pending;
  return resolve(url);
}

Future<String> ensure(String url) async {
  final existing = _inflight[url];
  if (existing != null) return existing;

  final future = _ensureIo(url);
  _inflight[url] = future;
  try {
    return await future;
  } finally {
    _inflight.remove(url);
  }
}

/// Download in list order (next ayah first) so slow networks fill N+1 before N+5.
void prefetch(Iterable<String> urls) {
  final gen = ++_prefetchGen;
  final list = urls.toList();
  debugPrint('Ayah audio prefetch ${list.length} urls');
  unawaited(_prefetchSerial(gen, list));
}

Future<void> _prefetchSerial(int gen, List<String> urls) async {
  for (final url in urls) {
    if (gen != _prefetchGen) return;
    try {
      await ensure(url);
    } catch (e, st) {
      debugPrint('Ayah audio prefetch failed: $url ($e)\n$st');
    }
  }
}

Future<String> _ensureIo(String url) async {
  final file = await _fileFor(url);
  if (await file.exists() && await file.length() > 0) {
    return file.uri.toString();
  }

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return url;
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(response.bodyBytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
    _scheduleMaintenance();
    return file.uri.toString();
  } catch (e, st) {
    debugPrint('Ayah audio download failed: $url ($e)\n$st');
    return url;
  }
}

Future<File> _fileFor(String url) async {
  final dir = await _cacheDir();
  final name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
  return File(p.join(dir.path, '$name.mp3'));
}

Future<Directory> _cacheDir() async {
  final cached = _dir;
  if (cached != null) return cached;
  final root = await getTemporaryDirectory();
  final dir = Directory(p.join(root.path, _subdir));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _dir = dir;
  _scheduleMaintenance();
  return dir;
}

void _scheduleMaintenance() {
  if (_maintenanceQueued) return;
  _maintenanceQueued = true;
  unawaited(_runMaintenance().whenComplete(() {
    _maintenanceQueued = false;
  }));
}

Future<void> _runMaintenance() async {
  try {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return;

    final entries = <AyahAudioCacheEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.mp3')) continue;
      try {
        final stat = await entity.stat();
        if (stat.size <= 0) continue;
        entries.add(
          AyahAudioCacheEntry(
            path: path,
            modified: stat.modified,
            size: stat.size,
          ),
        );
      } catch (_) {}
    }

    final doomed = ayahAudioCachePathsToDelete(
      entries: entries,
      now: DateTime.now(),
    );
    for (final path in doomed) {
      try {
        await File(path).delete();
      } catch (e, st) {
        debugPrint('Ayah audio cache delete failed: $path ($e)\n$st');
      }
    }
    if (doomed.isNotEmpty) {
      debugPrint('Ayah audio cache pruned ${doomed.length} files');
    }
  } catch (e, st) {
    debugPrint('Ayah audio cache maintenance failed: $e\n$st');
  }
}
