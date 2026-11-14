import 'dart:developer' show Timeline;

import 'package:arabic_text_justification/arabic_text_justification.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../data/mushaf_divisions.dart';
import '../../data/quran_models.dart';
import '../../quran/rendering/kfgqpc_font_scope.dart';
import '../../quran/rendering/tajweed_word_color_spans.dart';

/// Queues HarfBuzz outlines for [ayah] so a later scroll frame can paint them.
/// Returns true when any line was not shaped yet.
bool warmQuranAyahLines({
  required QuranAyahChunk ayah,
  required double fontSize,
  required double maxWidth,
  required String? fontPath,
  required double devicePixelRatio,
  required int emphasizedWordCount,
  required bool showEndMarker,
  required bool showRubMarker,
}) {
  return _QuranAyahWidgetState.warmLines(
    ayah: ayah,
    fontSize: fontSize,
    maxWidth: maxWidth,
    fontPath: fontPath,
    devicePixelRatio: devicePixelRatio,
    emphasizedWordCount: emphasizedWordCount,
    showEndMarker: showEndMarker,
    showRubMarker: showRubMarker,
  );
}

/// Ayah line from precomputed word color ranges.
///
/// IndoPak end marks are Arabic-Indic digits only (U+0660–U+0669).
/// Uthmani (DigitalKhatt) prefixes U+06DD so the face ligates `endofayaN`.
class QuranAyahWidget extends StatefulWidget {
  /// DigitalKhatt `endofayaN` vs body size (paint + pack width).
  static const double uthmaniEndMarkerScale = 0.82;
  const QuranAyahWidget({
    super.key,
    required this.ayah,
    required this.fontSize,
    required this.tajweedEnabled,
    required this.inkColor,
    this.showEndMarker = true,
    this.showRubMarker = false,
    this.rukuMark,
    this.onRukuAinTap,
    this.alignment = Alignment.centerRight,
    this.emphasizedWordCount = 0,
  });

  static const rubGlyph = '\u06DE';
  static const rukuGlyph = 'ع';

  final QuranAyahChunk ayah;
  final double fontSize;
  final bool tajweedEnabled;
  final Color inkColor;

  final bool showEndMarker;
  final bool showRubMarker;
  final RukuMarkInfo? rukuMark;
  final VoidCallback? onRukuAinTap;
  final Alignment alignment;
  final int emphasizedWordCount;

  @override
  State<QuranAyahWidget> createState() => _QuranAyahWidgetState();
}

class _QuranAyahWidgetState extends State<QuranAyahWidget> {
  static double? _cacheFontSize;
  static String? _cacheFontFamily;
  static final Map<String, double> _widthCache = <String, double>{};
  static double? _spaceWidthCache;

  static double? _packCacheFontSize;
  static String? _packCacheFontPath;
  static bool? _packCacheHbReady;
  static final Map<String, _PackedAyah> _packCache = <String, _PackedAyah>{};
  static const int _packCacheMax = 400;

  bool _warmingShaper = false;

  @override
  Widget build(BuildContext context) {
    final fontPath = KfgqpcFontScope.of(context);
    final fontFamily = KfgqpcFontScope.familyOf(context);
    final rukuMark = widget.rukuMark;
    final screenW = MediaQuery.sizeOf(context).width;
    final hbReady = peekJustificationShaper(fontPath) != null;

    if (!hbReady && !_warmingShaper) {
      _warmingShaper = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        warmJustificationShaper(fontPath).then((_) {
          if (mounted) setState(() => _warmingShaper = false);
        }, onError: (_) {
          if (mounted) setState(() => _warmingShaper = false);
        });
      });
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = (constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : screenW - 40)
              .clamp(120.0, 4000.0);
          return _buildPacked(
            fontPath: fontPath,
            fontFamily: fontFamily,
            maxW: maxW,
            hbReady: hbReady,
            rukuMark: rukuMark,
          );
        },
      ),
    );
  }

  Widget _buildPacked({
    required String? fontPath,
    required String fontFamily,
    required double maxW,
    required bool hbReady,
    required RukuMarkInfo? rukuMark,
  }) {
    final packed = _cachedPack(
      fontPath: fontPath,
      fontFamily: fontFamily,
      maxWidth: maxW,
      hbReady: hbReady,
    );
    final rows = packed.rows;
    final openingWords = packed.openingWords;
    final emphasize = openingWords.isNotEmpty;
    final openingSize = widget.fontSize * 1.18;
    final openingStroke = openingSize * 0.02;

    final uthmaniMarker = fontFamily == QuranFont.digitalKhattFamily &&
        widget.showEndMarker;
    final markerToken = uthmaniMarker ? '\u06DD' : null;
    final markerFontSize = uthmaniMarker
        ? widget.fontSize * QuranAyahWidget.uthmaniEndMarkerScale
        : null;

    Widget line(_HbRow row, {required bool ain, required double slotWidth}) {
      final painted = JustifiedArabicLine(
        words: [for (final cell in row.cells) cell.text],
        fontPath: fontPath,
        fontSize: widget.fontSize,
        justify: false,
        color: widget.inkColor,
        colorSpans: widget.tajweedEnabled
            ? _spansForRow(row, widget.inkColor)
            : const [],
        alignment: widget.alignment,
        marker: markerToken,
        markerFontSize: markerFontSize,
      );

      if (!ain || rukuMark == null || !widget.showEndMarker) {
        return painted;
      }
      final markerIndex = packed.endMarkerIndex;
      if (markerIndex == null || markerIndex < 0) return painted;
      final beforeW = packed.beforeMarkerWidth ?? 0.0;
      final markerW = packed.markerWidth ?? 0.0;
      final gap =
          markerIndex == 0 ? 0.0 : _spaceWidth(widget.fontSize, fontFamily);
      final ovalTop = widget.fontSize * ((2400 - 1022) / 2048);
      final chip = (widget.fontSize * 0.50).clamp(18.0, 24.0);
      final glyph = chip * 0.70;
      const air = 3.5;
      final chipTop = ovalTop - air - chip;
      const slop = 8.0;
      final centerFromRight = beforeW + gap + markerW * 0.5;
      final left = (slotWidth - centerFromRight - chip / 2 - slop).clamp(
        0.0,
        slotWidth,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          painted,
          Positioned(
            left: left,
            top: chipTop - slop,
            width: chip + slop * 2,
            height: chip + slop,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onRukuAinTap,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _RukuAinChip(
                  size: chip,
                  glyphSize: glyph,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final lineBottom = widget.fontSize * 0.25;
    final showAin = rukuMark != null && widget.showEndMarker;
    final ainTop = showAin ? widget.fontSize * 0.18 : 0.0;
    if (!emphasize) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == rows.length - 1 ? ainTop : 0,
                bottom: lineBottom,
              ),
              child: line(
                rows[i],
                ain: i == rows.length - 1,
                slotWidth: maxW,
              ),
            ),
        ],
      );
    }

    final rest = rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: rest.length <= 1 ? ainTop : 0.0,
            bottom: lineBottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: packed.openingWidth + openingStroke + 2,
                child: JustifiedArabicLine(
                  words: [for (final w in openingWords) w.text],
                  fontPath: fontPath,
                  fontSize: openingSize,
                  justify: false,
                  color: widget.inkColor,
                  strokeWidth: openingStroke,
                  colorSpans: widget.tajweedEnabled
                      ? [
                          for (var i = 0; i < openingWords.length; i++)
                            ...TajweedWordColorSpans.fromPrecomputed(
                              wordIndex: i,
                              ranges: openingWords[i].colorRanges,
                              ink: widget.inkColor,
                            ),
                        ]
                      : const [],
                  alignment: widget.alignment,
                ),
              ),
              if (rest.isNotEmpty) ...[
                SizedBox(width: _spaceWidth(openingSize, fontFamily)),
                Expanded(
                  child: line(
                    rest.first,
                    ain: rest.length <= 1,
                    slotWidth: packed.firstLineMaxWidth,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (var i = 1; i < rest.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == rest.length - 1 ? ainTop : 0,
              bottom: lineBottom,
            ),
            child: line(
              rest[i],
              ain: i == rest.length - 1,
              slotWidth: maxW,
            ),
          ),
      ],
    );
  }

  _PackedAyah _cachedPack({
    required String? fontPath,
    required String fontFamily,
    required double maxWidth,
    required bool hbReady,
  }) {
    _ensurePackCache(widget.fontSize, hbReady, fontPath);
    final openingCount = widget.emphasizedWordCount
        .clamp(0, widget.ayah.words.length)
        .toInt();
    final key = _packKey(
      ayah: widget.ayah,
      maxWidth: maxWidth,
      showEndMarker: widget.showEndMarker,
      showRubMarker: widget.showRubMarker,
      openingCount: openingCount,
    );

    final hit = _packCache.remove(key);
    if (hit != null) {
      _packCache[key] = hit;
      return hit;
    }

    Timeline.startSync(
      'QuranAyah.pack',
      arguments: <String, Object?>{
        'surah': widget.ayah.surah,
        'ayah': widget.ayah.ayah,
      },
    );
    final packed = packAyah(
      ayah: widget.ayah,
      fontSize: widget.fontSize,
      fontPath: fontPath,
      fontFamily: fontFamily,
      maxWidth: maxWidth,
      emphasizedWordCount: widget.emphasizedWordCount,
      showEndMarker: widget.showEndMarker,
      showRubMarker: widget.showRubMarker,
    );
    Timeline.finishSync();

    if (_packCache.length >= _packCacheMax) {
      _packCache.remove(_packCache.keys.first);
    }
    _packCache[key] = packed;
    return packed;
  }

  /// Surah+ayah alone is not enough: Rabbana/Shifa store a word slice of the
  /// same ayah that Manzil and the mushaf store in full.
  static String _packKey({
    required QuranAyahChunk ayah,
    required double maxWidth,
    required bool showEndMarker,
    required bool showRubMarker,
    required int openingCount,
  }) {
    final words = ayah.words;
    final first = words.isEmpty ? '' : words.first.text;
    final last = words.isEmpty ? '' : words.last.text;
    return '${ayah.surah}:${ayah.ayah}:${maxWidth.round()}:'
        '${showEndMarker ? 1 : 0}${showRubMarker ? 1 : 0}:'
        '$openingCount:${words.length}:$first:$last';
  }

  static void _ensurePackCache(
    double fontSize,
    bool hbReady,
    String? fontPath,
  ) {
    if (_packCacheFontSize == fontSize &&
        _packCacheHbReady == hbReady &&
        _packCacheFontPath == fontPath) {
      return;
    }
    _packCacheFontSize = fontSize;
    _packCacheHbReady = hbReady;
    _packCacheFontPath = fontPath;
    _packCache.clear();
  }

  static bool warmLines({
    required QuranAyahChunk ayah,
    required double fontSize,
    required double maxWidth,
    required String? fontPath,
    required double devicePixelRatio,
    required int emphasizedWordCount,
    required bool showEndMarker,
    required bool showRubMarker,
  }) {
    final shaper = peekJustificationShaper(fontPath);
    if (shaper == null || fontSize <= 0) return false;
    _ensurePackCache(fontSize, true, fontPath);
    final openingCount = emphasizedWordCount.clamp(0, ayah.words.length).toInt();
    final key = _packKey(
      ayah: ayah,
      maxWidth: maxWidth,
      showEndMarker: showEndMarker,
      showRubMarker: showRubMarker,
      openingCount: openingCount,
    );
    var packed = _packCache.remove(key);
    if (packed != null) {
      _packCache[key] = packed;
    } else {
      packed = packAyah(
        ayah: ayah,
        fontSize: fontSize,
        fontPath: fontPath,
        fontFamily: _familyForFontPath(fontPath),
        maxWidth: maxWidth,
        emphasizedWordCount: emphasizedWordCount,
        showEndMarker: showEndMarker,
        showRubMarker: showRubMarker,
      );
      if (_packCache.length >= _packCacheMax) {
        _packCache.remove(_packCache.keys.first);
      }
      _packCache[key] = packed;
    }

    var queued = false;
    void enqueue(List<String> words, double size) {
      if (words.isEmpty) return;
      final request = PreparedLineRequest(
        shaper: shaper,
        words: words,
        fontSize: size,
        devicePixelRatio: devicePixelRatio,
        fontPath: fontPath,
      );
      if (PreparedLineCache.contains(request.key)) return;
      PreparedLineCache.enqueue(request, urgent: false);
      queued = true;
    }

    if (packed.openingWords.isNotEmpty) {
      enqueue(
        [for (final word in packed.openingWords) word.text],
        fontSize * 1.18,
      );
    }
    for (final row in packed.rows) {
      enqueue([for (final cell in row.cells) cell.text], fontSize);
    }
    return queued;
  }

  static String _familyForFontPath(String? fontPath) {
    if (fontPath != null && fontPath.contains('DigitalKhatt')) {
      return QuranFont.digitalKhattFamily;
    }
    return QuranFont.family;
  }

  static _PackedAyah packAyah({
    required QuranAyahChunk ayah,
    required double fontSize,
    required String? fontPath,
    required String fontFamily,
    required double maxWidth,
    required int emphasizedWordCount,
    required bool showEndMarker,
    required bool showRubMarker,
  }) {
    final trailingMarkers = <String>[
      if (showEndMarker) _endMarkerText(ayah.ayah, fontFamily),
      if (showRubMarker) QuranAyahWidget.rubGlyph,
    ];
    final openingCount = emphasizedWordCount.clamp(0, ayah.words.length).toInt();
    final emphasize = openingCount > 0;
    final openingSize = fontSize * 1.18;
    final openingStroke = openingSize * 0.02;

    late final List<QuranWord> openingWords;
    late final List<QuranWord> bodyWords;
    late final double firstLineMax;
    late final double openingWidth;
    if (emphasize) {
      openingWords = ayah.words.take(openingCount).toList(
        growable: false,
      );
      final openingCells = [
        for (final w in openingWords)
          _HbCell(
            text: w.text,
            colorRanges: w.colorRanges,
            isMarker: false,
          ),
      ];
      openingWidth = _rowWidth(
        openingCells,
        fontSize: openingSize,
        fontPath: fontPath,
        fontFamily: fontFamily,
      );
      final gap = _spaceWidth(openingSize, fontFamily);
      final reserved = openingWidth + openingStroke + 2 + gap;
      firstLineMax = (maxWidth - reserved).clamp(0.0, maxWidth);
      bodyWords = ayah.words.skip(openingCount).toList(
        growable: false,
      );
    } else {
      openingWords = const [];
      openingWidth = 0;
      firstLineMax = maxWidth;
      bodyWords = ayah.words;
    }

    final rows = _packRows(
      words: bodyWords,
      trailingMarkers: trailingMarkers,
      fontSize: fontSize,
      maxWidth: maxWidth,
      firstLineMaxWidth: emphasize ? firstLineMax : null,
      fontPath: fontPath,
      fontFamily: fontFamily,
      endMarkFontPath: fontPath,
    );

    int? endMarkerIndex;
    double? beforeMarkerWidth;
    double? markerWidth;
    if (showEndMarker && rows.isNotEmpty) {
      final markerText = _endMarkerText(ayah.ayah, fontFamily);
      final last = rows.last;
      final markerIndex = last.cells.indexWhere(
        (cell) => cell.isMarker && cell.text == markerText,
      );
      if (markerIndex >= 0) {
        endMarkerIndex = markerIndex;
        beforeMarkerWidth = markerIndex == 0
            ? 0.0
            : _rowWidth(
                last.cells.sublist(0, markerIndex),
                fontSize: fontSize,
                fontPath: fontPath,
                fontFamily: fontFamily,
              );
        final markSize = fontFamily == QuranFont.digitalKhattFamily
            ? fontSize * QuranAyahWidget.uthmaniEndMarkerScale
            : fontSize;
        markerWidth = _rowWidth(
          [last.cells[markerIndex]],
          fontSize: markSize,
          fontPath: fontPath,
          fontFamily: fontFamily,
        );
      }
    }

    return _PackedAyah(
      rows: rows,
      openingWords: openingWords,
      openingWidth: openingWidth,
      firstLineMaxWidth: emphasize ? firstLineMax : maxWidth,
      endMarkerIndex: endMarkerIndex,
      beforeMarkerWidth: beforeMarkerWidth,
      markerWidth: markerWidth,
    );
  }

  static List<WordColorSpan> _spansForRow(_HbRow row, Color ink) {
    return [
      for (var i = 0; i < row.cells.length; i++)
        if (!row.cells[i].isMarker)
          ...TajweedWordColorSpans.fromPrecomputed(
            wordIndex: i,
            ranges: row.cells[i].colorRanges,
            ink: ink,
          ),
    ];
  }

  static void _ensureCache(double fontSize, String fontFamily) {
    if (_cacheFontSize == fontSize && _cacheFontFamily == fontFamily) return;
    _cacheFontSize = fontSize;
    _cacheFontFamily = fontFamily;
    _widthCache.clear();
    _spaceWidthCache = null;
  }

  static double _spaceWidth(double fontSize, String fontFamily) {
    _ensureCache(fontSize, fontFamily);
    return _spaceWidthCache ??= _layoutWidth(' ', fontSize, fontFamily);
  }

  static double _measureWidth(String text, double fontSize, String fontFamily) {
    _ensureCache(fontSize, fontFamily);
    final cached = _widthCache[text];
    if (cached != null) return cached;
    final width = _layoutWidth(text, fontSize, fontFamily);
    _widthCache[text] = width;
    return width;
  }

  static double _layoutWidth(String text, double fontSize, String fontFamily) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: const <String>[],
          fontSize: fontSize,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width;
  }

  static double _rowWidth(
    List<_HbCell> cells, {
    required double fontSize,
    required String? fontPath,
    required String fontFamily,
    String? endMarkFontPath,
  }) {
    if (cells.isEmpty) return 0;
    final markPath = endMarkFontPath ?? fontPath;
    if (markPath != fontPath && cells.any((c) => c.isMarker)) {
      final gap = _spaceWidth(fontSize, fontFamily);
      var used = 0.0;
      for (var i = 0; i < cells.length; i++) {
        if (i > 0) used += gap;
        final cell = cells[i];
        if (cell.isMarker && cell.text != QuranAyahWidget.rubGlyph) {
          used += measureJustificationWordsWidth(
                words: [cell.text],
                fontSize: fontSize,
                fontPath: markPath,
              ) ??
              _measureWidth(cell.text, fontSize, QuranFont.family);
        } else if (cell.isMarker) {
          used += _measureWidth(cell.text, fontSize, fontFamily);
        } else {
          used += measureJustificationWordsWidth(
                words: [cell.text],
                fontSize: fontSize,
                fontPath: fontPath,
              ) ??
              _measureWidth(cell.text, fontSize, fontFamily);
        }
      }
      return used;
    }

    final hb = measureJustificationWordsWidth(
      words: [for (final c in cells) c.text],
      fontSize: fontSize,
      fontPath: fontPath,
    );
    if (hb != null) return hb;

    final gap = _spaceWidth(fontSize, fontFamily);
    var used = 0.0;
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) used += gap;
      used += _measureWidth(cells[i].text, fontSize, fontFamily);
    }
    return used;
  }

  static List<_HbRow> _packRows({
    required List<QuranWord> words,
    required List<String> trailingMarkers,
    required double fontSize,
    required double maxWidth,
    double? firstLineMaxWidth,
    required String? fontPath,
    required String fontFamily,
    String? endMarkFontPath,
  }) {
    final fullLimit = maxWidth + 0.5;
    var limit = (firstLineMaxWidth ?? maxWidth) + 0.5;
    var onFirstLine = firstLineMaxWidth != null;

    final cells = <_HbCell>[
      for (final w in words)
        _HbCell(text: w.text, colorRanges: w.colorRanges, isMarker: false),
      for (final marker in trailingMarkers)
        if (marker.isNotEmpty)
          _HbCell(text: marker, colorRanges: const [], isMarker: true),
    ];

    final rows = <_HbRow>[];
    var current = <_HbCell>[];

    void flush() {
      if (current.isEmpty) return;
      rows.add(_HbRow(List<_HbCell>.of(current)));
      current = [];
      if (onFirstLine) {
        limit = fullLimit;
        onFirstLine = false;
      }
    }

    for (final cell in cells) {
      final trial = <_HbCell>[...current, cell];
      final trialW = _rowWidth(
        trial,
        fontSize: fontSize,
        fontPath: fontPath,
        fontFamily: fontFamily,
        endMarkFontPath: endMarkFontPath,
      );
      if (current.isNotEmpty && trialW > limit) {
        if (cell.isMarker && current.isNotEmpty) {
          final last = current.removeLast();
          final pulled = <_HbCell>[];
          while (current.isNotEmpty && current.last.isMarker) {
            pulled.add(current.removeLast());
          }
          flush();
          current.add(last);
          current.addAll(pulled.reversed);
        } else {
          flush();
        }
      }
      current.add(cell);
    }
    flush();
    return rows;
  }

  /// Arabic-Indic digits (U+0660–U+0669).
  static String _toEasternDigits(int value) {
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final raw = value.toString();
    final buffer = StringBuffer();
    for (final code in raw.codeUnits) {
      final digit = code - 0x30;
      if (digit >= 0 && digit <= 9) {
        buffer.write(eastern[digit]);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// IndoPak: digits only (KFGQPC circled ligatures).
  /// DigitalKhatt: U+06DD + digits → `endofayaN` ligature in the same face.
  static String _endMarkerText(int ayah, String fontFamily) {
    final digits = _toEasternDigits(ayah);
    if (fontFamily == QuranFont.digitalKhattFamily) {
      return '\u06DD$digits';
    }
    return digits;
  }
}

/// Cached line-break result for one ayah at one width / font size.
class _PackedAyah {
  const _PackedAyah({
    required this.rows,
    required this.openingWords,
    required this.openingWidth,
    required this.firstLineMaxWidth,
    this.endMarkerIndex,
    this.beforeMarkerWidth,
    this.markerWidth,
  });

  final List<_HbRow> rows;
  final List<QuranWord> openingWords;
  final double openingWidth;
  final double firstLineMaxWidth;
  final int? endMarkerIndex;
  final double? beforeMarkerWidth;
  final double? markerWidth;
}

class _HbCell {
  const _HbCell({
    required this.text,
    required this.colorRanges,
    required this.isMarker,
  });

  final String text;
  final List<QuranWordColorRange> colorRanges;
  final bool isMarker;
}

class _HbRow {
  const _HbRow(this.cells);
  final List<_HbCell> cells;
}

/// Small filled circle in the IndoPak gap on the ayah oval.
class _RukuAinChip extends StatelessWidget {
  const _RukuAinChip({
    required this.size,
    required this.glyphSize,
  });

  final double size;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RukuAinPainter(glyphSize: glyphSize),
      ),
    );
  }
}

/// Paints ع on the circle by its alphabetic baseline (ink center ≈ baseline).
class _RukuAinPainter extends CustomPainter {
  const _RukuAinPainter({required this.glyphSize});

  final double glyphSize;

  static const _glyphColor = Color(0xFFFFF8EE);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide / 2,
      Paint()..color = AppTheme.orange,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: QuranAyahWidget.rukuGlyph,
        style: TextStyle(
          fontFamily: QuranFont.family,
          fontFamilyFallback: const <String>[],
          fontSize: glyphSize,
          height: 1.0,
          color: _glyphColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout();

    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    const inkCenterAboveBaseline = 55 / 2048;
    final dx = (size.width - painter.width) / 2;
    final dy = size.height / 2 -
        baseline +
        glyphSize * inkCenterAboveBaseline;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _RukuAinPainter oldDelegate) =>
      oldDelegate.glyphSize != glyphSize;
}
