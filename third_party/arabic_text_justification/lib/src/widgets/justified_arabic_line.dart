import 'dart:developer' show Timeline;

import 'package:flutter/material.dart';

import '../bundled_fonts.dart';
import '../justify/prepared_line.dart';
import '../justify/prepared_line_cache.dart';
import '../models/models.dart';
import 'line_common.dart';
import 'painter.dart';

/// A single line of Arabic, kashida-justified to fill the available width via
/// the DigitalKhatt justification engine, rendered as crisp vector outlines.
class JustifiedArabicLine extends StatefulWidget
    implements JustifiedArabicLineConfig {
  @override
  final List<String> words;

  @override
  final bool justify;

  final Color color;

  /// Word indices (into [words]) to render with a highlight background.
  final Set<int>? highlightedWordIndices;

  /// Background color for highlighted words.
  final Color highlightColor;

  @override
  final WordProgress? wordProgress;

  /// Per-character color spans. Each span paints the glyphs that belong
  /// to a character range (UTF-16 offsets) inside a word. Takes priority over
  /// the widget's default [color] but is overridden by [WordProgress] tints
  /// when both apply. Useful for tajweed coloring, etc.
  final List<WordColorSpan>? colorSpans;

  /// Text that identifies a word as a marker (e.g. '۝').
  /// When set, taps on a word containing this text fire [onMarkerTap]
  /// instead of [onWordTap].
  @override
  final String? marker;

  /// Called when the user taps a word that does not contain [marker].
  @override
  final void Function(int index, String word)? onWordTap;

  /// Called when the user taps a word that contains [marker].
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

  /// Fixed height (display px) of the line's row box. When set, the row always
  /// occupies this height and the glyph box is centered vertically within it,
  /// independent of [fontSize]. Unlike [height] (which derives the font size
  /// from a target height), this leaves the glyph size to [fontSize] and only
  /// fixes the surrounding box — letting the font size change while the line
  /// height stays put. [JustifiedArabicBlock] uses this to keep rows locked to
  /// a grid. When null, the row is exactly as tall as the glyph box.
  final double? lineBoxHeight;

  /// When set, words containing [marker] render at this fixed display size
  /// instead of scaling with [fontSize]. Keeps ayah markers a constant size
  /// while the body text resizes. No effect when [marker] is null.
  final double? markerFontSize;

  /// Extra outline thickness in logical pixels. Zero keeps a plain fill.
  final double strokeWidth;

  final EdgeInsetsGeometry? padding;

  /// Alignment of the line within the available width. When null the widget
  /// reports its intrinsic size (tight to content for `justify=false`).
  final AlignmentGeometry? alignment;

  const JustifiedArabicLine({
    super.key,
    required this.words,
    this.justify = true,
    this.color = Colors.black,
    this.highlightedWordIndices,
    this.highlightColor = const Color(0x332196F3),
    this.wordProgress,
    this.colorSpans,
    this.marker,
    this.onWordTap,
    this.onMarkerTap,
    this.fontPath,
    this.font = JustificationFont.defaultFont,
    this.fontSize,
    this.height,
    this.lineBoxHeight,
    this.markerFontSize,
    this.strokeWidth = 0,
    this.padding,
    this.alignment,
  });

  @override
  State<JustifiedArabicLine> createState() => _JustifiedArabicLineState();
}

class _JustifiedArabicLineState extends State<JustifiedArabicLine>
    with JustifiedLineStateMixin<JustifiedArabicLine> {
  PreparedLine? _prepared;
  bool _shapeQueued = false;

  /// Effective body font size (display px) the last render used — the basis the
  /// marker counter-scales against when [JustifiedArabicLine.fontSize] is null.
  double? _renderedDisplaySize;

  PreparedLine? _spanColorsPrepared;
  List<WordColorSpan>? _spanColorsInput;
  List<Color?>? _spanColorsCache;

  @override
  void didUpdateWidget(JustifiedArabicLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.height != oldWidget.height ||
        widget.padding != oldWidget.padding) {
      renderedWidth = null;
      _prepared = null;
      _invalidateSpanColors();
    }
    handleConfigChange(oldWidget);
  }

  @override
  void resetRender() {
    _prepared = null;
    _shapeQueued = false;
    _invalidateSpanColors();
  }

  double _metricLineHeight() {
    final fs = widget.fontSize;
    final sh = shaper;
    if (fs == null || sh == null || fs <= 0) return 0;
    final metrics = sh.fontMetrics;
    final metric = (metrics.ascender - metrics.descender).toDouble();
    if (metric <= 0 || sh.unitsPerEm <= 0) return fs;
    return metric / sh.unitsPerEm * fs;
  }

  void _invalidateSpanColors() {
    _spanColorsPrepared = null;
    _spanColorsInput = null;
    _spanColorsCache = null;
  }

  PreparedLine? _renderSync(double width) {
    final sh = shaper;
    if (sh == null) return null;

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
    if (nativeSize == null) return null;
    _renderedDisplaySize = nativeSize / dpr;

    // ignore: unnecessary_import — Timeline used for PROFILE DevTools.
    return Timeline.timeSync(
      'JustifiedArabicLine.prepareLine',
      () => prepareLine(
        sh,
        widget.words,
        nativeSize: nativeSize,
        nativeWidth: nativeWidth,
        justify: widget.justify,
      ),
    );
  }

  double _computeScale(double width, PreparedLine prepared) {
    if (widget.justify) return width / prepared.width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final naturalScale = 1 / dpr;
    final fitScale = width / prepared.width;
    return naturalScale < fitScale ? naturalScale : fitScale;
  }

  void _handleTap(Offset localPosition, double offsetX) {
    final prepared = _prepared;
    final width = renderedWidth;
    if (prepared == null || width == null) return;
    if (prepared.paths.isEmpty) return;

    final scale = _computeScale(width, prepared);
    final glyphX = (localPosition.dx - offsetX) / scale;
    final hidden = widget.wordProgress?.hiddenWordIndices;

    for (int i = 0; i < prepared.wordRects.length; i++) {
      if (hidden != null && hidden.contains(i)) continue;
      final r = prepared.wordRects[i];
      if (r.width <= 0) continue;
      if (glyphX >= r.left && glyphX <= r.right) {
        dispatchTap(i);
        return;
      }
    }
  }

  List<Color?>? _buildSpanColors(PreparedLine prepared) {
    final spans = widget.colorSpans;
    if (identical(prepared, _spanColorsPrepared) &&
        identical(spans, _spanColorsInput)) {
      return _spanColorsCache;
    }
    _spanColorsPrepared = prepared;
    _spanColorsInput = spans;
    _spanColorsCache = _computeSpanColors(prepared, spans);
    return _spanColorsCache;
  }

  List<Color?>? _computeSpanColors(
    PreparedLine prepared,
    List<WordColorSpan>? spans,
  ) {
    if (spans == null || spans.isEmpty || prepared.paths.isEmpty) return null;

    // Spans are described in UTF-16 char offsets; glyph clusters are too, so we
    // compare directly (no UTF-8 conversion).
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

        final widthChanged = renderedWidth != contentWidth;
        if (_prepared != null && widthChanged && !widget.justify) {
          renderedWidth = contentWidth;
        } else if (_prepared == null || widthChanged) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final fontSize = widget.fontSize;
          final request = fontSize == null
              ? null
              : PreparedLineRequest(
                  shaper: shaper!,
                  words: widget.words,
                  fontSize: fontSize,
                  devicePixelRatio: dpr,
                  fontPath: widget.fontPath,
                  justify: widget.justify,
                  nativeWidth: contentWidth * dpr,
                );
          final cached = request == null
              ? null
              : PreparedLineCache.peek(request.key);
          if (cached != null) {
            _prepared = cached;
            renderedWidth = contentWidth;
            _shapeQueued = false;
          } else if (request != null && PreparedLineCache.deferMisses) {
            if (!_shapeQueued) {
              _shapeQueued = true;
              final width = contentWidth;
              PreparedLineCache.enqueue(
                request,
                urgent: true,
                onReady: (line) {
                  if (!mounted) return;
                  setState(() {
                    _prepared = line;
                    renderedWidth = width;
                    _shapeQueued = false;
                  });
                },
              );
            }
            return SizedBox(
              width: outerWidth,
              height: _metricLineHeight(),
            );
          } else {
            final prepared = _renderSync(contentWidth);
            if (prepared == null) return const SizedBox.shrink();
            _prepared = prepared;
            renderedWidth = contentWidth;
            if (request != null) {
              PreparedLineCache.remember(request, prepared);
            }
          }
        }

        final prepared = _prepared!;
        if (prepared.paths.isEmpty) return const SizedBox.shrink();

        final dpr = MediaQuery.devicePixelRatioOf(context);
        final scaleX = _computeScale(contentWidth, prepared);
        final scaleY = 1 / dpr;

        final glyphW = widget.justify ? contentWidth : prepared.width * scaleX;
        final glyphH = prepared.height * scaleY;

        // When a fixed line-box height is supplied,
        // the row keeps that height and the glyph box is
        // centered vertically within it. Otherwise the row is exactly the
        // glyph box height.
        final boxH = widget.lineBoxHeight ?? glyphH;
        final leadingY = (boxH - glyphH) / 2;

        final widgetWidth =
            widget.justify ? outerWidth : glyphW + insets.horizontal;
        final widgetHeight = boxH + insets.vertical;

        final offsetX = insets.left - prepared.minX * scaleX;
        final offsetY = insets.top + leadingY - prepared.minY * scaleY;

        final hidden = widget.wordProgress?.hiddenWordIndices;

        final fullHeight = DisplayTransform(
          scale: scaleX,
          offsetX: offsetX,
          top: 0,
          height: widgetHeight,
          excluding: hidden,
        );

        final highlights = fullHeight.mapMerged(
          widget.highlightedWordIndices ?? const <int>{},
          prepared.wordRects,
        );

        final progress = widget.wordProgress;
        var passedRects = const <Rect>[];
        Rect? activeRect;
        double activeProgress = 0;
        int? activeIdx;
        bool activeWhole = false;
        Set<int>? passedIndices;
        Color? passedColor;
        Color? passedHighlightColor;
        Color? activeColor;
        Color? activeHighlightColor;

        if (progress != null) {
          passedColor = progress.passedColor;
          passedHighlightColor = progress.passedHighlightColor;
          activeColor = progress.activeColor;
          activeHighlightColor = progress.activeHighlightColor;
          passedIndices = progress.passedWordIndices;
          final active = activeState;
          activeWhole = active.whole;
          activeProgress = active.progress;

          if (passedIndices != null && passedHighlightColor != null) {
            passedRects =
                fullHeight.mapMerged(passedIndices, prepared.wordRects);
          }

          final ai = progress.activeWordIndex;
          if (ai != null) {
            final rect = fullHeight.mapSingleFilled(ai, prepared.wordRects);
            if (rect != null) {
              activeIdx = ai;
              activeRect = rect;
            }
          }
        }

        final pathColors = _buildSpanColors(prepared);

        // Static-size markers: render words containing [marker] at a fixed
        // display size by counter-scaling against the body size, so they don't
        // grow/shrink with the surrounding text. Scaled around each marker
        // word's centre (in prepared device-px space) to keep it in place.
        Set<int>? markerWords;
        Map<int, Offset>? markerCenters;
        var markerScale = 1.0;
        final markerText = widget.marker;
        final markerFixed = widget.markerFontSize;
        if (markerFixed != null &&
            markerText != null &&
            markerText.isNotEmpty) {
          final bodySize = widget.fontSize ?? _renderedDisplaySize;
          if (bodySize != null && bodySize > 0) {
            markerWords = <int>{};
            markerCenters = <int, Offset>{};
            for (var i = 0; i < widget.words.length; i++) {
              if (!widget.words[i].contains(markerText)) continue;
              markerWords.add(i);
              final r = i < prepared.wordRects.length
                  ? prepared.wordRects[i]
                  : Rect.zero;
              markerCenters[i] =
                  Offset((r.left + r.right) / 2, (r.top + r.bottom) / 2);
            }
            if (markerWords.isEmpty) {
              markerWords = null;
              markerCenters = null;
            } else {
              markerScale = markerFixed / bodySize;
            }
          }
        }

        Widget child = CustomPaint(
          size: Size(widgetWidth, widgetHeight),
          painter: ArabicOutlinePainter(
            paths: prepared.paths,
            pathWordIndices: prepared.pathWordIndices,
            pathSpanColors: pathColors,
            hiddenWordIndices: hidden,
            highlights: highlights,
            highlightColor: widget.highlightColor,
            color: widget.color,
            passedWordIndices: passedIndices,
            passedRects: passedRects,
            passedHighlightColor: passedHighlightColor,
            passedColor: passedColor,
            activeWordIndex: activeIdx,
            activeRect: activeRect,
            activeProgress: activeProgress,
            activeHighlightColor: activeHighlightColor,
            activeColor: activeColor,
            activeWhole: activeWhole,
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: offsetX,
            offsetY: offsetY,
            markerWordIndices: markerWords,
            markerScale: markerScale,
            markerCenters: markerCenters,
            strokeWidth: scaleX == 0 ? 0 : widget.strokeWidth / scaleX,
          ),
        );

        if (widget.onWordTap != null || widget.onMarkerTap != null) {
          child = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details.localPosition, offsetX),
            child: child,
          );
        }

        final boundary = RepaintBoundary(child: child);
        return widget.alignment == null
            ? boundary
            : Align(alignment: widget.alignment!, child: boundary);
      },
    );
  }
}
