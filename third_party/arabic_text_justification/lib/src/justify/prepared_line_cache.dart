import 'package:flutter/scheduler.dart';

import 'hb_shaper.dart';
import 'prepared_line.dart';

/// One shaped line, ready for [JustifiedArabicLine] to paint.
class PreparedLineRequest {
  const PreparedLineRequest({
    required this.shaper,
    required this.words,
    required this.fontSize,
    required this.devicePixelRatio,
    required this.fontPath,
    this.justify = false,
    this.nativeWidth = 0,
  });

  final HbShaper shaper;
  final List<String> words;
  final double fontSize;
  final double devicePixelRatio;
  final String? fontPath;
  final bool justify;

  /// Content width in device pixels. Used only when [justify] is true.
  final double nativeWidth;

  String get key => preparedLineCacheKey(
        fontPath: fontPath,
        fontSize: fontSize,
        devicePixelRatio: devicePixelRatio,
        justify: justify,
        nativeWidth: nativeWidth,
        words: words,
      );
}

String preparedLineCacheKey({
  required String? fontPath,
  required double fontSize,
  required double devicePixelRatio,
  required bool justify,
  required double nativeWidth,
  required List<String> words,
}) {
  final size = (fontSize * devicePixelRatio).round();
  final width = justify ? nativeWidth.round() : 0;
  return '$fontPath|$size|$width|${justify ? 1 : 0}|${words.join('\u0001')}';
}

/// LRU of shaped lines, filled a few lines per frame so a fling never runs
/// HarfBuzz inside the scroll build.
class PreparedLineCache {
  PreparedLineCache._();

  static const int maxEntries = 1200;

  /// How many HarfBuzz lines to prepare each frame while the queue is hot.
  static const int linesPerFrame = 6;

  /// When true, a cache miss must not shape during build.
  static bool deferMisses = false;

  static final Map<String, PreparedLine> _entries = <String, PreparedLine>{};
  static final List<PreparedLineRequest> _urgent = <PreparedLineRequest>[];
  static final List<PreparedLineRequest> _ahead = <PreparedLineRequest>[];
  static final Map<String, List<void Function(PreparedLine line)>> _listeners =
      <String, List<void Function(PreparedLine line)>>{};
  static final Set<String> _queued = <String>{};
  static bool _scheduled = false;

  static void remember(PreparedLineRequest request, PreparedLine line) {
    _store(request.key, line);
  }

  static PreparedLine? peek(String key) {
    final hit = _entries.remove(key);
    if (hit == null) return null;
    _entries[key] = hit;
    return hit;
  }

  static bool contains(String key) => _entries.containsKey(key);

  /// Shape [request] on a later frame. [onReady] runs on the UI isolate.
  static void enqueue(
    PreparedLineRequest request, {
    required bool urgent,
    void Function(PreparedLine line)? onReady,
  }) {
    final key = request.key;
    final cached = peek(key);
    if (cached != null) {
      onReady?.call(cached);
      return;
    }
    if (onReady != null) {
      _listeners.putIfAbsent(key, () => []).add(onReady);
    }
    if (_queued.contains(key)) {
      if (urgent) _promote(key);
      return;
    }
    _queued.add(key);
    (urgent ? _urgent : _ahead).add(request);
    _schedule();
  }

  static void _promote(String key) {
    final index = _ahead.indexWhere((job) => job.key == key);
    if (index < 0) return;
    _urgent.insert(0, _ahead.removeAt(index));
  }

  static void _schedule() {
    if (_scheduled) return;
    if (_urgent.isEmpty && _ahead.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduled = false;
      var shaped = 0;
      while (shaped < linesPerFrame &&
          (_urgent.isNotEmpty || _ahead.isNotEmpty)) {
        _pumpOne();
        shaped++;
      }
      if (_urgent.isNotEmpty || _ahead.isNotEmpty) _schedule();
    });
  }

  static void _pumpOne() {
    final request = _urgent.isNotEmpty
        ? _urgent.removeAt(0)
        : _ahead.removeAt(0);
    _queued.remove(request.key);
    final existing = peek(request.key);
    final line = existing ??
        prepareLine(
          request.shaper,
          request.words,
          nativeSize: request.fontSize * request.devicePixelRatio,
          nativeWidth: request.justify ? request.nativeWidth : 1,
          justify: request.justify,
        );
    if (existing == null) _store(request.key, line);
    final listeners = _listeners.remove(request.key);
    if (listeners == null) return;
    for (final listener in listeners) {
      listener(line);
    }
  }

  static void _store(String key, PreparedLine line) {
    _entries.remove(key);
    _entries[key] = line;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
