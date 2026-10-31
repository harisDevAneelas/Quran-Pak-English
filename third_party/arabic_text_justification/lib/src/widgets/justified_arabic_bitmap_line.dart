import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../bundled_fonts.dart';
import '../justify/prepared_line.dart';
import '../models/models.dart';
import 'line_common.dart';

/// White coverage mask, tinted at paint time with [BlendMode.srcIn].
class _BitmapLayer {
  final ui.Image image;
  /// Null means use [JustifiedArabicBitmapLine.color] (body ink).
  final Color? spanColor;
  const _BitmapLayer({required this.image, this.spanColor});
}

/// Engine-rasterized line: white glyph bitmaps (tinted at paint time) plus the
/// word rects, in image-pixel space.
class _BitmapResult {
  final List<_BitmapLayer> layers;
  final int bmpWidth;
  final int bmpHeight;
  final List<Rect> wordRects;
  const _BitmapResult({
    required this.layers,
    required this.bmpWidth,
    required this.bmpHeight,
    required this.wordRects,
  });
}

class JustifiedArabicBitmapLine extends StatefulWidget
    implements JustifiedArabicLineConfig {
  @override
  final List<String> words;

  @override
  final bool justify;

  final Color color;

  final Set<int>? highlightedWordIndices;

  final Color highlightColor;

  @override
  final WordProgress? wordProgress;

  /// Text that identifies a word as a marker (e.g. '۝').
  /// When set, taps on a word containing this text fire [onMarkerTap]
  /// instead of [onWordTap].
  @override
  final String? marker;

  @override
  final void Function(int index, String word)? onWordTap;

  @override
  final void Function(int index, String word)? onMarkerTap;

  /// If null, the bundled [font] is loaded automatically.
  @override
  final String? fontPath;

  /// Bundled font to shape with when [fontPath] is null. Defaults to
  /// [JustificationFont.defaultFont].
  @override
  final JustificationFont font;

  /// If null, the size is auto-calculated to fill the available width.
  @override
  final double? fontSize;

  /// When set, ignores [fontSize] and auto-fits the line to this height.
  final double? height;

  final EdgeInsetsGeometry? padding;

  /// Alignment of the line within the available width. When null the widget
  /// reports its intrinsic size (tight to content for `justify=false`), so
  /// the caller picks the position via a parent (Row, Column, Align, etc).
  /// Set this when you want the widget itself to fill the width and place
  /// the content at the given alignment (e.g. [Alignment.centerRight]).
  final AlignmentGeometry? alignment;

  /// Per-character colors baked into the bitmap (tajweed). When set, the
  /// image is drawn as-is instead of tinting with [color].
  final List<WordColorSpan>? colorSpans;

  const JustifiedArabicBitmapLine({
    super.key,
    required this.words,
    this.justify = true,
    this.color = Colors.black,
    this.highlightedWordIndices,
    this.highlightColor = const Color(0x332196F3),
    this.wordProgress,
    this.marker,
    this.onWordTap,
    this.onMarkerTap,
    this.fontPath,
    this.font = JustificationFont.defaultFont,
    this.fontSize,
    this.height,
    this.padding,
    this.alignment,
    this.colorSpans,
  });

  @override
  State<JustifiedArabicBitmapLine> createState() =>
      _JustifiedArabicBitmapLineState();
}

class _JustifiedArabicBitmapLineState extends State<JustifiedArabicBitmapLine>
    with JustifiedLineStateMixin<JustifiedArabicBitmapLine> {
  _BitmapResult? _result;
  List<Rect>? _wordRects;

  @override
  void didUpdateWidget(JustifiedArabicBitmapLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.height != oldWidget.height ||
        widget.padding != oldWidget.padding ||
        !listEquals(widget.colorSpans, oldWidget.colorSpans)) {
      renderedWidth = null;
      _dropResult();
    }
    handleConfigChange(oldWidget);
  }

  @override
  void dispose() {
    _dropResult();
    super.dispose();
  }

  @override
  void resetRender() {
    _dropResult();
  }

  void _dropResult() {
    final layers = _result?.layers;
    if (layers != null) {
      for (final layer in layers) {
        layer.image.dispose();
      }
    }
    _result = null;
    _wordRects = null;
  }

  /// Shape + rasterize on this frame so the line reports a real height
  /// instead of collapsing to [SizedBox.shrink] for a frame.
  void _renderSync(double width) {
    final sh = shaper;
    if (sh == null) return;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final nativeWidth = width * dpr;
    final insets =
        widget.padding?.resolve(Directionality.of(context)) ?? EdgeInsets.zero;

    final nativeSize = resolveNativeSize(
      nativeWidth: nativeWidth,
      dpr: dpr,
      height: widget.height,
      insets: insets,
    );
    if (nativeSize == null) return;

    final prepared = prepareLine(
      sh,
      widget.words,
      nativeSize: nativeSize,
      nativeWidth: nativeWidth,
      justify: widget.justify,
    );
    if (prepared.paths.isEmpty) return;

    // Pad so antialiased ink is not clipped at the image edge.
    const pad = 2;
    final pw = prepared.width.ceil() + pad * 2;
    final ph = prepared.height.ceil() + pad * 2;
    if (pw <= 0 || ph <= 0) return;

    final groups = _coverageGroups(prepared);
    final layers = <_BitmapLayer>[];
    for (final group in groups) {
      layers.add(
        _BitmapLayer(
          image: rasterizePreparedLineSync(
            prepared,
            scaleX: 1,
            scaleY: 1,
            offsetX: -prepared.minX + pad,
            color: const ui.Color(0xFFFFFFFF),
            pixelWidth: pw,
            pixelHeight: ph,
            pathIndices: group.indices,
          ),
          spanColor: group.spanColor,
        ),
      );
    }

    final rects = [
      for (final r in prepared.wordRects)
        r.width > 0
            ? Rect.fromLTWH(
                r.left - prepared.minX + pad,
                r.top + pad,
                r.width,
                r.height,
              )
            : Rect.zero,
    ];

    _dropResult();
    _result = _BitmapResult(
      layers: layers,
      bmpWidth: pw,
      bmpHeight: ph,
      wordRects: rects,
    );
    _wordRects = rects;
    renderedWidth = width;
  }

  List<({List<int> indices, Color? spanColor})> _coverageGroups(
    PreparedLine prepared,
  ) {
    final pathColors = _spanColors(prepared);
    if (pathColors == null) {
      return [(indices: [for (var i = 0; i < prepared.paths.length; i++) i], spanColor: null)];
    }
    final buckets = <int, List<int>>{};
    final inkKey = widget.color.toARGB32();
    for (var i = 0; i < prepared.paths.length; i++) {
      final c = pathColors[i];
      final key = c?.toARGB32() ?? inkKey;
      buckets.putIfAbsent(key, () => []).add(i);
    }
    return [
      for (final entry in buckets.entries)
        (
          indices: entry.value,
          spanColor: entry.key == inkKey ? null : Color(entry.key),
        ),
    ];
  }

  List<Color?>? _spanColors(PreparedLine prepared) {
    final spans = widget.colorSpans;
    if (spans == null || spans.isEmpty || prepared.paths.isEmpty) return null;
    final byWord = <int, List<({int start, int end, Color color})>>{};
    for (final s in spans) {
      if (s.wordIndex < 0 || s.wordIndex >= widget.words.length) continue;
      final word = widget.words[s.wordIndex];
      final startClamped = s.start.clamp(0, word.length);
      final endClamped = s.end.clamp(startClamped, word.length);
      if (endClamped <= startClamped) continue;
      byWord
          .putIfAbsent(s.wordIndex, () => [])
          .add((start: startClamped, end: endClamped, color: s.color));
    }
    if (byWord.isEmpty) return null;
    final out = List<Color?>.filled(prepared.paths.length, null);
    var any = false;
    for (var i = 0; i < prepared.paths.length; i++) {
      final wIdx = prepared.pathWordIndices[i];
      final bucket = byWord[wIdx];
      if (bucket == null) continue;
      final charInWord = prepared.pathCharInWord[i];
      for (final s in bucket) {
        if (charInWord >= s.start && charInWord < s.end) {
          out[i] = s.color;
          any = true;
          break;
        }
      }
    }
    return any ? out : null;
  }

  void _handleTap(
    Offset localPosition,
    _BitmapResult result,
    double imageLeft,
    double displayWidth,
  ) {
    if (displayWidth <= 0) return;

    final sx = result.bmpWidth / displayWidth;
    final nativeX = (localPosition.dx - imageLeft) * sx;
    final hidden = widget.wordProgress?.hiddenWordIndices;

    for (int i = 0; i < result.wordRects.length; i++) {
      if (hidden != null && hidden.contains(i)) continue;
      final r = result.wordRects[i];
      if (r.width <= 0) continue;
      if (nativeX >= r.left && nativeX <= r.right) {
        dispatchTap(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (shaper == null) {
      return const SizedBox.shrink();
    }

    final insets =
        widget.padding?.resolve(Directionality.of(context)) ?? EdgeInsets.zero;

    return LayoutBuilder(
      builder: (context, constraints) {
        final outerWidth = constraints.maxWidth;
        final contentWidth = (outerWidth - insets.horizontal).clamp(
          0.0,
          double.infinity,
        );

        if (_result == null || renderedWidth != contentWidth) {
          _renderSync(contentWidth);
          if (_result == null) return const SizedBox.shrink();
        }

        final result = _result!;

        final double displayWidth;
        final double displayHeight;
        if (widget.justify) {
          final scale = contentWidth / result.bmpWidth;
          displayWidth = contentWidth;
          displayHeight = result.bmpHeight * scale;
        } else {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final naturalScale = 1 / dpr;
          final fitScale = contentWidth / result.bmpWidth;
          final scale = naturalScale < fitScale ? naturalScale : fitScale;
          displayWidth = result.bmpWidth * scale;
          displayHeight = result.bmpHeight * scale;
        }

        final widgetWidth =
            widget.justify ? outerWidth : displayWidth + insets.horizontal;
        final widgetHeight = displayHeight + insets.vertical;
        final imageLeft = insets.left;
        final imageTop = insets.top;

        final sx = displayWidth / result.bmpWidth;
        final wordRects = _wordRects!;

        final hidden = widget.wordProgress?.hiddenWordIndices;

        final imageArea = DisplayTransform(
          scale: sx,
          offsetX: imageLeft,
          top: imageTop,
          height: displayHeight,
          excluding: hidden,
        );
        final fullHeight = DisplayTransform(
          scale: sx,
          offsetX: imageLeft,
          top: 0,
          height: widgetHeight,
          excluding: hidden,
        );

        final hiddenRects = hidden == null || hidden.isEmpty
            ? const <Rect>[]
            : DisplayTransform(
                scale: sx,
                offsetX: imageLeft,
                top: imageTop,
                height: displayHeight,
              ).mapAll(hidden, wordRects);

        final highlights = fullHeight.mapMerged(
          widget.highlightedWordIndices ?? const <int>{},
          wordRects,
        );

        final progress = widget.wordProgress;
        var passedRects = const <Rect>[];
        Rect? activeRect;
        double activeProgress = 0;
        bool activeWhole = false;
        Color? passedColor;
        Color? passedHighlightColor;
        Color? activeColor;
        Color? activeHighlightColor;

        if (progress != null) {
          passedColor = progress.passedColor;
          passedHighlightColor = progress.passedHighlightColor;
          activeColor = progress.activeColor;
          activeHighlightColor = progress.activeHighlightColor;
          final active = activeState;
          activeWhole = active.whole;
          activeProgress = active.progress;

          final passed = progress.passedWordIndices;
          if (passed != null &&
              (passedHighlightColor != null || passedColor != null)) {
            passedRects = imageArea.mapMerged(passed, wordRects);
          }

          final activeIdx = progress.activeWordIndex;
          if (activeIdx != null) {
            activeRect = imageArea.mapSingleFilled(activeIdx, wordRects);
          }
        }

        final imageDst = Rect.fromLTWH(
          imageLeft,
          imageTop,
          displayWidth,
          displayHeight,
        );

        Widget content = CustomPaint(
          painter: _BitmapWordPainter(
            layers: result.layers,
            imageDst: imageDst,
            color: widget.color,
            highlights: highlights,
            highlightColor: widget.highlightColor,
            passedRects: passedRects,
            passedHighlightColor: passedHighlightColor,
            passedColor: passedColor,
            activeRect: activeRect,
            activeProgress: activeProgress,
            activeWhole: activeWhole,
            activeHighlightColor: activeHighlightColor,
            activeColor: activeColor,
            hiddenRects: hiddenRects,
          ),
        );

        if (widget.onWordTap != null || widget.onMarkerTap != null) {
          content = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(
              details.localPosition,
              result,
              imageLeft,
              displayWidth,
            ),
            child: content,
          );
        }

        final boundary = RepaintBoundary(
          child: SizedBox(
            width: widgetWidth,
            height: widgetHeight,
            child: content,
          ),
        );
        return widget.alignment == null
            ? boundary
            : Align(alignment: widget.alignment!, child: boundary);
      },
    );
  }
}

class _BitmapWordPainter extends CustomPainter {
  final List<_BitmapLayer> layers;
  final Rect imageDst;
  final Color color;

  final List<Rect> highlights;
  final Color highlightColor;

  final List<Rect> passedRects;
  final Color? passedHighlightColor;
  final Color? passedColor;

  final Rect? activeRect;
  final double activeProgress;
  final bool activeWhole;
  final Color? activeHighlightColor;
  final Color? activeColor;

  final List<Rect> hiddenRects;

  _BitmapWordPainter({
    required this.layers,
    required this.imageDst,
    required this.color,
    this.highlights = const [],
    this.highlightColor = const Color(0x00000000),
    this.passedRects = const [],
    this.passedHighlightColor,
    this.passedColor,
    this.activeRect,
    this.activeProgress = 0,
    this.activeWhole = false,
    this.activeHighlightColor,
    this.activeColor,
    this.hiddenRects = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (highlights.isNotEmpty) {
      final p = Paint()..color = highlightColor;
      for (final r in highlights) {
        canvas.drawRect(r, p);
      }
    }

    if (passedHighlightColor != null && passedRects.isNotEmpty) {
      final p = Paint()..color = passedHighlightColor!;
      for (final r in passedRects) {
        canvas.drawRect(r, p);
      }
    }

    final ar = activeRect;
    if (activeHighlightColor != null && ar != null) {
      if (activeWhole) {
        canvas.drawRect(ar, Paint()..color = activeHighlightColor!);
      } else if (activeProgress > 0) {
        final fillW = ar.width * activeProgress;
        canvas.drawRect(
          Rect.fromLTWH(ar.right - fillW, ar.top, fillW, ar.height),
          Paint()..color = activeHighlightColor!,
        );
      }
    }

    canvas.save();
    if (hiddenRects.isNotEmpty) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      for (final r in hiddenRects) {
        path.addRect(r);
      }
      canvas.clipPath(path);
    }

    void drawLayers(Color Function(_BitmapLayer layer) tintOf) {
      for (final layer in layers) {
        final src = Rect.fromLTWH(
          0,
          0,
          layer.image.width.toDouble(),
          layer.image.height.toDouble(),
        );
        canvas.drawImageRect(
          layer.image,
          src,
          imageDst,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..isAntiAlias = true
            ..colorFilter = ColorFilter.mode(tintOf(layer), BlendMode.srcIn),
        );
      }
    }

    drawLayers((layer) => layer.spanColor ?? color);

    if (passedColor != null && passedRects.isNotEmpty) {
      final clip = Path();
      for (final r in passedRects) {
        clip.addRect(r);
      }
      canvas.save();
      canvas.clipPath(clip);
      drawLayers((_) => passedColor!);
      canvas.restore();
    }

    if (activeColor != null && ar != null && activeProgress > 0) {
      final clip = activeWhole
          ? ar
          : Rect.fromLTWH(
              ar.right - ar.width * activeProgress,
              ar.top,
              ar.width * activeProgress,
              ar.height,
            );
      canvas.save();
      canvas.clipRect(clip);
      drawLayers((_) => activeColor!);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BitmapWordPainter old) =>
      !identical(layers, old.layers) ||
      imageDst != old.imageDst ||
      color != old.color ||
      highlightColor != old.highlightColor ||
      passedHighlightColor != old.passedHighlightColor ||
      passedColor != old.passedColor ||
      activeHighlightColor != old.activeHighlightColor ||
      activeColor != old.activeColor ||
      activeRect != old.activeRect ||
      activeProgress != old.activeProgress ||
      activeWhole != old.activeWhole ||
      !listEquals(highlights, old.highlights) ||
      !listEquals(passedRects, old.passedRects) ||
      !listEquals(hiddenRects, old.hiddenRects);
}
