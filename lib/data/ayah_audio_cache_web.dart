import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

final Map<String, Future<String>> _inflight = {};
final Map<String, html.AudioElement> _nodes = {};
int _prefetchGen = 0;

Future<String> resolve(String url) async => url;

Future<String> playable(String url) async {
  final pending = _inflight[url];
  if (pending != null) return pending;
  return url;
}

Future<String> ensure(String url) {
  return _inflight.putIfAbsent(url, () => _preload(url));
}

/// Browser media preload — `http.get` cannot cache these MP3s (no CORS).
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

Future<String> _preload(String url) {
  final existing = _nodes[url];
  if (existing != null && existing.readyState >= 3) {
    return Future.value(url);
  }

  final audio = html.AudioElement()
    ..preload = 'auto'
    ..src = url;
  _nodes[url] = audio;

  final done = Completer<String>();
  void complete() {
    if (!done.isCompleted) done.complete(url);
  }

  audio.onCanPlayThrough.listen((_) => complete());
  audio.onLoadedData.listen((_) => complete());
  audio.onError.listen((_) {
    debugPrint('Ayah audio preload error: $url');
    complete();
  });
  audio.load();

  return done.future.timeout(
    const Duration(seconds: 45),
    onTimeout: () => url,
  );
}
