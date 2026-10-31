import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../bundled_fonts.dart';
import '../justify/hb_shaper.dart';
import '../models/models.dart';
import '../platform/shaper_loader.dart';

typedef ResolvedActiveState = ({double progress, bool whole});

class DisplayTransform {
  final double scale;
  final double offsetX;
  final double top;
  final double height;
  final Set<int>? excluding;

  const DisplayTransform({
    required this.scale,
    required this.offsetX,
    required this.top,
    required this.height,
    this.excluding,
  });

  Rect? mapSingle(int index, List<Rect> wordRects) {
    if (index < 0 || index >= wordRects.length) return null;
    if (excluding != null && excluding!.contains(index)) return null;
    final r = wordRects[index];
    if (r.width <= 0) return null;
    return Rect.fromLTWH(
      offsetX + scale * r.left,
      top,
      scale * r.width,
      height,
    );
  }

  List<Rect> mapAll(Iterable<int> indices, List<Rect> wordRects) {
    final out = <Rect>[];
    for (final i in indices) {
      final rect = mapSingle(i, wordRects);
      if (rect != null) out.add(rect);
    }
    return out;
  }

  ({double left, double right})? _filledExtent(
      int index, List<Rect> wordRects) {
    if (index < 0 || index >= wordRects.length) return null;
    if (excluding != null && excluding!.contains(index)) return null;
    final r = wordRects[index];
    if (r.width <= 0) return null;
    var left = r.left;
    var right = r.right;
    for (final n in [index - 1, index + 1]) {
      if (n < 0 || n >= wordRects.length) continue;
      if (excluding != null && excluding!.contains(n)) continue;
      final nr = wordRects[n];
      if (nr.width <= 0) continue;
      if (nr.left >= r.right) {
        final mid = (r.right + nr.left) / 2;
        if (mid > right) right = mid;
      } else if (nr.right <= r.left) {
        final mid = (r.left + nr.right) / 2;
        if (mid < left) left = mid;
      }
    }
    return (left: left, right: right);
  }

  Rect? mapSingleFilled(int index, List<Rect> wordRects) {
    final e = _filledExtent(index, wordRects);
    if (e == null) return null;
    return Rect.fromLTWH(
      offsetX + scale * e.left,
      top,
      scale * (e.right - e.left),
      height,
    );
  }

  List<Rect> mapMerged(Iterable<int> indices, List<Rect> wordRects) {
    final sorted = indices.toList()..sort();
    final out = <Rect>[];
    double? runLeft, runRight;
    int? prev;
    void flush() {
      if (runLeft != null && runRight != null) {
        out.add(Rect.fromLTWH(
          offsetX + scale * runLeft!,
          top,
          scale * (runRight! - runLeft!),
          height,
        ));
      }
      runLeft = null;
      runRight = null;
    }

    for (final i in sorted) {
      final e = _filledExtent(i, wordRects);
      if (e == null) continue;
      if (runLeft != null && prev != null && i == prev + 1) {
        if (e.left < runLeft!) runLeft = e.left;
        if (e.right > runRight!) runRight = e.right;
      } else {
        flush();
        runLeft = e.left;
        runRight = e.right;
      }
      prev = i;
    }
    flush();
    return out;
  }
}

/// Fields the mixin reads off the owning widget. Both [JustifiedArabicLine]
/// and [JustifiedArabicBitmapLine] implement this.
abstract interface class JustifiedArabicLineConfig {
  List<String> get words;

  bool get justify;

  String? get fontPath;

  JustificationFont get font;

  double? get fontSize;

  String? get marker;

  void Function(int index, String word)? get onWordTap;

  void Function(int index, String word)? get onMarkerTap;

  WordProgress? get wordProgress;
}

/// Shared lifecycle and helpers for the line widgets: resolves the font path
/// (bundled or user-supplied), invalidates the render when inputs change,
/// and routes taps to the caller's callbacks. Subclasses implement
/// [resetRender] to drop their cached render result.
mixin JustifiedLineStateMixin<T extends StatefulWidget> on State<T> {
  String? fontPath;
  double? renderedWidth;
  HbShaper? _shaper;

  JustifiedArabicLineConfig get _cfg => widget as JustifiedArabicLineConfig;

  /// The engine shaper, or null until the font has loaded.
  HbShaper? get shaper => _shaper;

  @override
  void initState() {
    super.initState();
    fontPath = _cfg.fontPath;
    final peeked = peekJustificationShaper(fontPath, font: _cfg.font);
    if (peeked != null) {
      _shaper = peeked;
    } else {
      _loadShaper();
    }
  }

  /// Call from [didUpdateWidget] with the old widget (which must implement
  /// [JustifiedArabicLineConfig]).
  void handleConfigChange(JustifiedArabicLineConfig oldCfg) {
    final cfg = _cfg;
    if (cfg.fontPath != oldCfg.fontPath || cfg.font != oldCfg.font) {
      fontPath = cfg.fontPath;
      renderedWidth = null;
      resetRender();
      _loadShaper();
    }
    if (!listEquals(cfg.words, oldCfg.words) ||
        cfg.justify != oldCfg.justify ||
        cfg.fontSize != oldCfg.fontSize) {
      renderedWidth = null;
      resetRender();
    }
  }

  /// Resolves the native font size: either the caller's [fontSize] scaled
  /// by [dpr], or auto-fit to [nativeWidth] via shaping.
  double resolveFontSize({
    required double nativeWidth,
    required double dpr,
  }) {
    final fs = _cfg.fontSize;
    if (fs != null) return fs * dpr;
    // Auto-fit: native font size that makes the natural (unjustified) line
    // exactly nativeWidth wide.
    final sh = shaper!;
    final naturalFu = sh.measure(_cfg.words.join(' '), const []).toDouble();
    if (naturalFu <= 0) return 16 * dpr;
    return nativeWidth * sh.unitsPerEm / naturalFu;
  }

  double? resolveNativeSize({
    required double nativeWidth,
    required double dpr,
    required double? height,
    required EdgeInsets insets,
  }) {
    if (height == null) {
      return resolveFontSize(nativeWidth: nativeWidth, dpr: dpr);
    }
    final nativeHeightBudget = (height - insets.vertical) * dpr;
    if (nativeHeightBudget <= 0) return null;

    final sh = shaper!;
    final m = sh.fontMetrics;
    final metric = (m.ascender - m.descender).toDouble();
    if (metric <= 0) return null;

    var nativeSize = nativeHeightBudget * sh.unitsPerEm / metric;
    final minNative = 8 * dpr;
    if (nativeSize < minNative) nativeSize = minNative;
    return nativeSize;
  }

  /// Routes a word tap to either [JustifiedArabicLineConfig.onWordTap] or
  /// [JustifiedArabicLineConfig.onMarkerTap]. A marker is a word whose text
  /// contains [JustifiedArabicLineConfig.marker] (non-null, non-empty).
  void dispatchTap(int wordIndex) {
    final cfg = _cfg;
    if (wordIndex < 0 || wordIndex >= cfg.words.length) return;

    final word = cfg.words[wordIndex];
    final marker = cfg.marker;
    final isMarker =
        marker != null && marker.isNotEmpty && word.contains(marker);

    if (isMarker) {
      cfg.onMarkerTap?.call(wordIndex, word);
    } else {
      cfg.onWordTap?.call(wordIndex, word);
    }
  }

  ResolvedActiveState get activeState {
    final p = _cfg.wordProgress;
    if (p == null) return (progress: 0.0, whole: false);
    final whole = p.style == WordProgressStyle.whole;
    final progress = switch (p.style) {
      WordProgressStyle.whole => p.activeWordIndex != null ? 1.0 : 0.0,
      WordProgressStyle.sweep => p.activeProgress.clamp(0.0, 1.0),
    };
    return (progress: progress, whole: whole);
  }

  /// Drop the cached render so the next layout pass re-renders.
  @protected
  void resetRender();

  Future<void> _loadShaper() async {
    final sh = await resolveShaper(_cfg.fontPath, font: _cfg.font);
    if (mounted) setState(() => _shaper = sh);
  }
}
