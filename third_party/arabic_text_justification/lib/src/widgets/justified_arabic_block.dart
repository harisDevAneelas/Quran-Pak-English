import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../bundled_fonts.dart';
import '../justify/hb_shaper.dart';
import '../models/models.dart';
import '../platform/shaper_loader.dart';
import 'justified_arabic_line.dart';

typedef BlockWordTap = void Function(int lineIndex, int wordIndex, String word);

/// Per-line configuration for [JustifiedArabicBlock]. Mirrors the subset
/// of [JustifiedArabicLine] props that are line-specific. Block-level
/// settings (marker, tap callbacks, font path, padding, spacing, font size)
/// are shared across every line.
class JustifiedArabicLineSpec {
  final List<String> words;

  /// When null, inherits from the block's [JustifiedArabicBlock.justify].
  final bool? justify;

  /// When null, inherits from the block's [JustifiedArabicBlock.color].
  final Color? color;

  final Set<int>? highlightedWordIndices;

  /// When null, inherits from the block's
  /// [JustifiedArabicBlock.highlightColor].
  final Color? highlightColor;

  final List<WordColorSpan>? colorSpans;

  final WordProgress? wordProgress;

  /// Alignment of a non-justified line within the block width. Honored only
  /// when the effective [justify] is false.
  final AlignmentGeometry? alignment;

  const JustifiedArabicLineSpec({
    required this.words,
    this.justify,
    this.color,
    this.highlightedWordIndices,
    this.highlightColor,
    this.colorSpans,
    this.wordProgress,
    this.alignment,
  });
}

/// Multi-line justified Arabic block.
///
/// The block picks one shared font size across all lines so every row has
/// the same height, even when word content differs. Each line is then
/// rendered independently with its own [JustifiedArabicLineSpec] —
/// justify on/off, highlights, color spans, word progress, per-line color
/// and alignment are all configurable per line.
///
/// Lines are pre-split by the caller. The standard mushaf layout already
/// assigns specific words to specific lines (so every printed copy matches
/// page-for-page); this widget preserves that control instead of running a
/// line-break algorithm.
class JustifiedArabicBlock extends StatefulWidget {
  /// One spec per rendered row.
  final List<JustifiedArabicLineSpec> lines;

  /// Default justify value for specs that don't override it.
  final bool justify;

  /// Default color for specs that don't override it.
  final Color color;

  /// Default highlight background for specs that don't override it.
  final Color highlightColor;

  /// Shared font size across all lines. When null, the block auto-fits:
  /// picks the size at which the *widest* natural line fills the available
  /// width; shorter lines get kashida-stretched (or rendered at their
  /// natural width if their spec has [JustifiedArabicLineSpec.justify]
  /// false).
  final double? fontSize;

  /// Vertical gap between adjacent lines.
  final double lineSpacing;

  /// Lock each row's height to the layout grid so changing [fontSize] does not
  /// move the lines. Honored only when the block has a bounded height and an
  /// explicit [fontSize].
  ///
  /// When false (default), the row height tracks [fontSize] — bigger font,
  /// taller rows, the whole block grows. When true, every row keeps the slot
  /// height the container affords (`contentHeight / lines.length`) and the
  /// glyphs render at [fontSize] centered within that slot. This keeps lines
  /// pinned to a fixed grid (e.g. a mushaf's ruled lines) while the reader
  /// scales the text up or down.
  ///
  /// Has no effect when [fontSize] is null (the glyphs already fill the slot)
  /// or when the block's height is unbounded (there is no grid to lock to).
  final bool preserveLineHeight;

  final EdgeInsetsGeometry? padding;

  final String? fontPath;

  final JustificationFont font;

  /// Text that identifies a word as a marker (e.g. '۝'). Routed to
  /// [onMarkerTap] when tapped, otherwise to [onWordTap].
  final String? marker;

  /// When true, words containing [marker] render at a fixed size so resizing
  /// the body text (via [fontSize]) leaves the marker unchanged. The size is
  /// [markerFontSize], or — when that's null — the block's auto-fit ("optimal")
  /// size. No effect when [marker] is null.
  final bool staticMarker;

  /// Fixed display size for markers when [staticMarker] is on. When null, the
  /// marker falls back to the block's auto-fit size.
  final double? markerFontSize;

  final BlockWordTap? onWordTap;

  final BlockWordTap? onMarkerTap;

  const JustifiedArabicBlock({
    super.key,
    required this.lines,
    this.justify = true,
    this.color = Colors.black,
    this.highlightColor = const Color(0x332196F3),
    this.fontSize,
    this.lineSpacing = 0,
    this.preserveLineHeight = false,
    this.padding,
    this.fontPath,
    this.font = JustificationFont.defaultFont,
    this.marker,
    this.staticMarker = false,
    this.markerFontSize,
    this.onWordTap,
    this.onMarkerTap,
  });

  @override
  State<JustifiedArabicBlock> createState() => _JustifiedArabicBlockState();
}

class _JustifiedArabicBlockState extends State<JustifiedArabicBlock> {
  String? _fontPath;
  HbShaper? _shaper;
  double? _resolvedDisplaySize;
  // Fixed per-row box height (display px) when [preserveLineHeight] is active;
  // null means rows size to their glyph box (default behavior).
  double? _resolvedLineBox;
  // Fixed marker size (display px) when [staticMarker] is active; null means
  // markers scale with the body text.
  double? _resolvedMarkerSize;
  double? _resolvedForWidth;
  double? _resolvedForHeight;

  // Cached per-line tap adapters. Allocated once per (onWordTap,
  // onMarkerTap, lines.length) change so we don't churn closures on every
  // rebuild (e.g. ValueListenableBuilder ticks during playback).
  List<void Function(int, String)?>? _wordTapAdapters;
  List<void Function(int, String)?>? _markerTapAdapters;

  @override
  void initState() {
    super.initState();
    _fontPath = widget.fontPath;
    _loadShaper();
  }

  @override
  void didUpdateWidget(JustifiedArabicBlock oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.fontPath != oldWidget.fontPath ||
        widget.font != oldWidget.font) {
      _fontPath = widget.fontPath;
      _invalidateSize();
      _loadShaper();
    }

    // Only *word content* and the explicit fontSize affect calibration.
    // Per-line style changes (color, highlights, justify, spans, progress)
    // rebuild the children automatically without re-running calibration.
    if (widget.fontSize != oldWidget.fontSize ||
        widget.preserveLineHeight != oldWidget.preserveLineHeight ||
        widget.lineSpacing != oldWidget.lineSpacing ||
        widget.staticMarker != oldWidget.staticMarker ||
        widget.markerFontSize != oldWidget.markerFontSize ||
        _wordsChanged(widget.lines, oldWidget.lines)) {
      _invalidateSize();
    }

    if (widget.onWordTap != oldWidget.onWordTap ||
        widget.onMarkerTap != oldWidget.onMarkerTap ||
        widget.lines.length != oldWidget.lines.length) {
      _wordTapAdapters = null;
      _markerTapAdapters = null;
    }
  }

  void _invalidateSize() {
    _resolvedDisplaySize = null;
    _resolvedLineBox = null;
    _resolvedMarkerSize = null;
    _resolvedForWidth = null;
    _resolvedForHeight = null;
  }

  static bool _wordsChanged(
      List<JustifiedArabicLineSpec> a, List<JustifiedArabicLineSpec> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i].words, b[i].words)) return true;
    }
    return false;
  }

  Future<void> _loadShaper() async {
    final sh = await resolveShaper(widget.fontPath, font: widget.font);
    if (mounted) setState(() => _shaper = sh);
  }

  /// Resolves the shared glyph [fontSize] (display px); the fixed per-row
  /// [lineBox] height when [preserveLineHeight] applies (else null); and the
  /// fixed [markerSize] when [staticMarker] is on (else null). The body size is
  /// the caller's [fontSize] or the auto-fit size; the marker falls back to
  /// that same auto-fit ("optimal") size when [markerFontSize] is unset.
  ({double fontSize, double? lineBox, double? markerSize})? _computeLayout(
    double contentWidth,
    double contentHeight,
  ) {
    final sh = _shaper;
    if (sh == null) return null;
    if (widget.lines.isEmpty) return null;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final nativeWidth = contentWidth * dpr;
    if (nativeWidth <= 0) return null;

    final explicit = widget.fontSize;

    // The auto-fit ("optimal") display size, plus the grid slot height when the
    // block has a bounded height. Prefer height-based sizing: row height is a
    // pure function of fontSize and font metrics, so every block with the same
    // line count + height renders at the same size (PageView-of-blocks match
    // without cross-block calibration). Width is handled per line by kashida.
    double? optimal;
    double? slotDisplay;
    if (contentHeight.isFinite && contentHeight > 0) {
      final m = sh.fontMetrics;
      final metric = (m.ascender - m.descender).toDouble();
      if (metric > 0) {
        final n = widget.lines.length;
        final nativeHeight = contentHeight * dpr;
        final nativeSpacing = widget.lineSpacing * dpr;
        // Reserve one display pixel per row as a safety buffer (subpixel
        // rounding accumulates across N per-line heights).
        final safetyNative = n * dpr;
        final availForGlyphs =
            nativeHeight - (n - 1) * nativeSpacing - safetyNative;
        if (availForGlyphs > 0) {
          final slotNative = availForGlyphs / n; // per-row box, native px
          slotDisplay = slotNative / dpr;
          optimal = (slotNative * (sh.unitsPerEm / metric)) / dpr;
        }
      }
    }
    final needOptimal = explicit == null ||
        (widget.staticMarker && widget.markerFontSize == null);
    if (optimal == null && needOptimal) {
      optimal = _widthFitDisplaySize(sh, nativeWidth, dpr);
    }
    if (needOptimal && optimal == null) return null;

    final body = explicit ?? optimal!;
    // preserveLineHeight only locks rows to the grid when there's a bounded
    // slot AND the caller fixed the font size (otherwise glyphs already fill).
    final lineBox =
        (widget.preserveLineHeight && explicit != null) ? slotDisplay : null;
    final markerSize =
        widget.staticMarker ? (widget.markerFontSize ?? optimal) : null;

    return (fontSize: body, lineBox: lineBox, markerSize: markerSize);
  }

  /// Display size that makes the widest natural justified line fill
  /// [nativeWidth]. Null when nothing measurable.
  double? _widthFitDisplaySize(HbShaper sh, double nativeWidth, double dpr) {
    // "Natural" means un-stretched: reset the tatweel axis so a previous line's
    // justification doesn't skew the measurement on variable fonts (no-op for
    // static fonts).
    sh.setTatweel(0);
    final texts = <String>[
      for (final spec in widget.lines)
        if (spec.justify ?? widget.justify) spec.words.join(' '),
    ];
    final calibrationTexts = texts.isNotEmpty
        ? texts
        : [for (final spec in widget.lines) spec.words.join(' ')];
    var maxNaturalFu = 0.0;
    for (final t in calibrationTexts) {
      final w = sh.measure(t, const []).toDouble();
      if (w > maxNaturalFu) maxNaturalFu = w;
    }
    if (maxNaturalFu <= 0) return null;
    return (nativeWidth * sh.unitsPerEm / maxNaturalFu) / dpr;
  }

  void _ensureTapAdapters() {
    final count = widget.lines.length;
    if (_wordTapAdapters != null &&
        _markerTapAdapters != null &&
        _wordTapAdapters!.length == count) {
      return;
    }
    final onWordTap = widget.onWordTap;
    final onMarkerTap = widget.onMarkerTap;
    _wordTapAdapters = List<void Function(int, String)?>.generate(
      count,
      (lineIndex) => onWordTap == null
          ? null
          : (wordIndex, word) => onWordTap(lineIndex, wordIndex, word),
      growable: false,
    );
    _markerTapAdapters = List<void Function(int, String)?>.generate(
      count,
      (lineIndex) => onMarkerTap == null
          ? null
          : (wordIndex, word) => onMarkerTap(lineIndex, wordIndex, word),
      growable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_shaper == null) return const SizedBox.shrink();
    if (widget.lines.isEmpty) return const SizedBox.shrink();

    final insets =
        widget.padding?.resolve(Directionality.of(context)) ?? EdgeInsets.zero;

    return LayoutBuilder(
      builder: (context, constraints) {
        final outerWidth = constraints.maxWidth;
        final contentWidth = (outerWidth - insets.horizontal).clamp(
          0.0,
          double.infinity,
        );
        final outerHeight = constraints.maxHeight;
        final contentHeight = outerHeight.isFinite
            ? (outerHeight - insets.vertical).clamp(0.0, double.infinity)
            : double.infinity;

        // Resolve the shared font size synchronously. Width- and
        // height-fitting both run as pure FFI calls — safe during build.
        // Caching avoids recomputing on every layout pass.
        if (_resolvedDisplaySize == null ||
            _resolvedForWidth != contentWidth ||
            _resolvedForHeight != contentHeight) {
          final layout = _computeLayout(contentWidth, contentHeight);
          if (layout == null) return const SizedBox.shrink();
          _resolvedDisplaySize = layout.fontSize;
          _resolvedLineBox = layout.lineBox;
          _resolvedMarkerSize = layout.markerSize;
          _resolvedForWidth = contentWidth;
          _resolvedForHeight = contentHeight;
        }

        final sharedSize = _resolvedDisplaySize!;
        final sharedLineBox = _resolvedLineBox;
        final sharedMarkerSize = _resolvedMarkerSize;
        _ensureTapAdapters();
        final wordTaps = _wordTapAdapters!;
        final markerTaps = _markerTapAdapters!;

        final rows = <Widget>[];
        for (var i = 0; i < widget.lines.length; i++) {
          if (i > 0 && widget.lineSpacing > 0) {
            rows.add(SizedBox(height: widget.lineSpacing));
          }
          final spec = widget.lines[i];
          // JustifiedArabicLine wraps its own output in a RepaintBoundary,
          // so per-line paint invalidation (e.g. word-progress ticks) is
          // already isolated from siblings — no outer boundary needed.
          rows.add(
            JustifiedArabicLine(
              words: spec.words,
              justify: spec.justify ?? widget.justify,
              color: spec.color ?? widget.color,
              highlightedWordIndices: spec.highlightedWordIndices,
              highlightColor: spec.highlightColor ?? widget.highlightColor,
              colorSpans: spec.colorSpans,
              wordProgress: spec.wordProgress,
              alignment: spec.alignment,
              fontSize: sharedSize,
              lineBoxHeight: sharedLineBox,
              markerFontSize: sharedMarkerSize,
              fontPath: _fontPath,
              font: widget.font,
              marker: widget.marker,
              onWordTap: wordTaps[i],
              onMarkerTap: markerTaps[i],
            ),
          );
        }

        return Padding(
          padding: insets,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        );
      },
    );
  }
}
