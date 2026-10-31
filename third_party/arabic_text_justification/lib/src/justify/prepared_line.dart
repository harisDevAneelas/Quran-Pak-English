/// Shared engine-driven line preparation for the public widgets.
///
/// This is the single layout path behind both `JustifiedArabicLine` (vector) and
/// `JustifiedArabicBitmapLine` (bitmap): it shapes + kashida-justifies a line
/// through the Dart engine and emits glyph outlines positioned in device pixels,
/// plus the word rects / per-glyph mapping those widgets need for hit-testing,
/// color spans, highlights and progress.
library;

import 'dart:ui' as ui;

import 'engine.dart';
import 'hb_shaper.dart';
import 'line_analyzer.dart';
import 'types.dart';

/// Engine-produced line geometry in device pixels. Mirrors the shape the widgets
/// previously got from the native outline path, so downstream code is unchanged.
class PreparedLine {
  final List<ui.Path> paths;
  final List<int> pathWordIndices;

  /// UTF-16 code-unit offset of each glyph within its word (for color spans).
  final List<int> pathCharInWord;
  final List<ui.Rect> wordRects;
  final double minX;
  final double minY;
  final double width;
  final double height;

  const PreparedLine({
    required this.paths,
    required this.pathWordIndices,
    required this.pathCharInWord,
    required this.wordRects,
    required this.minX,
    required this.minY,
    required this.width,
    required this.height,
  });

  static const empty = PreparedLine(
    paths: [],
    pathWordIndices: [],
    pathCharInWord: [],
    wordRects: [],
    minX: 0,
    minY: 0,
    width: 0,
    height: 0,
  );
}

List<HbFeature> _renderFeatures(LineTextInfo info, JustResultByLine r) {
  final feats = <HbFeature>[...(info.features ?? const <HbFeature>[])];
  r.fontFeatures.forEach((i, list) {
    for (final f in list) {
      feats.add(HbFeature(tag: f.name, value: f.value, start: i, end: i + 1));
    }
  });
  return feats;
}

ui.Path _glyphPath(List<OutlineCommand> cmds, double ox, double oy,
    double ascender, double sx, double sy) {
  // Position in font units (RTL x is negative-leftward), flip y about the
  // ascender so y=0 is the top of the line box, then scale to device px.
  final p = ui.Path();
  double tx(double x) => (ox + x) * sx;
  double ty(double y) => (ascender - (oy + y)) * sy;
  for (final c in cmds) {
    switch (c.type) {
      case 0:
        p.moveTo(tx(c.x), ty(c.y));
      case 1:
        p.lineTo(tx(c.x), ty(c.y));
      case 2:
        p.quadraticBezierTo(tx(c.x1), ty(c.y1), tx(c.x), ty(c.y));
      case 3:
        p.cubicTo(tx(c.x1), ty(c.y1), tx(c.x2), ty(c.y2), tx(c.x), ty(c.y));
    }
  }
  p.close();
  return p;
}

/// Find the tatweel axis value (LTAT/RTAT design units, ±20) that stretches
/// [line] to [targetFu] font units, and leave [shaper] set to it.
void _applyLineTatweel(
  HbShaper shaper,
  String line,
  List<HbFeature> features,
  double targetFu,
) {
  int measureAt(double v) {
    shaper.setTatweel(v);
    return shaper.measure(line, features);
  }

  // Clamp when the target is outside the axis range (best-effort fit); each
  // check also leaves the shaper at the clamped end.
  if (measureAt(20) <= targetFu) return; // max stretch, still too narrow
  if (measureAt(-20) >= targetFu) return; // max compress, still too wide

  var lo = -20.0, hi = 20.0;
  for (var i = 0; i < 10 && hi - lo > 0.1; i++) {
    final mid = (lo + hi) * 0.5;
    if (measureAt(mid) >= targetFu) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  shaper.setTatweel(hi);
}

/// Prepare [words] as one justified line. [nativeSize] is the device-px font
/// size; [nativeWidth] the device-px content width. When [justify] is false the
/// line is shaped naturally (no kashida) and the caller scales to fit.
PreparedLine prepareLine(
  HbShaper shaper,
  List<String> words, {
  required double nativeSize,
  required double nativeWidth,
  required bool justify,
  MushafLayoutType mushafType = MushafLayoutType.newMadinah,
  bool bism = false,
}) {
  final line = words.join(' ');
  if (line.isEmpty || nativeSize <= 0) return PreparedLine.empty;

  final info = analyzeLineForJust(line, bism: bism);
  final upem = shaper.unitsPerEm;
  final glyphScale = nativeSize / upem;
  final metrics = shaper.fontMetrics;
  final ascender = metrics.ascender.toDouble();
  final metricHeightFu = (metrics.ascender - metrics.descender).toDouble();

  List<HbFeature> feats;
  var xScale = 1.0;
  var simpleSpacing = 0.0;
  var ayaSpacing = 0.0;
  var useSpacing = false;

  if (shaper.hasTatweel) {
    // Variable-font kashida (digitalkhatt.otf): elongate letters via the
    // LTAT/RTAT tatweel axes. Letters carry the stretch, so spaces stay
    // natural and no cvXX features are applied.
    feats = info.features ?? const <HbFeature>[];
    if (justify) {
      _applyLineTatweel(shaper, line, feats, nativeWidth / glyphScale);
    } else {
      shaper.setTatweel(0); // natural shape for non-justified lines
    }
  } else if (justify) {
    final spaceWidth = shaper.measure(' ', const []).toDouble();
    final desiredFu = nativeWidth / glyphScale;
    final result = justifyLine(info, shaper, kFontSize / desiredFu, spaceWidth,
        mushafType: mushafType);
    feats = _renderFeatures(info, result);
    xScale = result.xScale;
    simpleSpacing = result.simpleSpacing;
    ayaSpacing = result.ayaSpacing;
    useSpacing = true;
  } else {
    feats = info.features ?? const <HbFeature>[];
  }

  final glyphs = shaper.shape(line, feats);

  // O(1) cluster→word lookup (clusters are line char indices; every base char
  // falls inside exactly one word range). Whitespace clusters are not in any
  // range and are handled separately below.
  final clusterWord = List<int>.filled(line.length, 0);
  for (var w = 0; w < info.wordInfos.length; w++) {
    final wi = info.wordInfos[w];
    for (var i = wi.startIndex; i <= wi.endIndex && i < line.length; i++) {
      clusterWord[i] = w;
    }
  }

  final sx = glyphScale * xScale;
  final sy = glyphScale;

  final paths = <ui.Path>[];
  final pathWords = <int>[];
  final pathChar = <int>[];

  // Per-word x extent (device px) for word rects.
  final wordMinX = <int, double>{};
  final wordMaxX = <int, double>{};

  var currentX = 0.0; // font units, negative-leftward
  var minX = double.infinity, maxX = double.negativeInfinity;

  for (var gi = glyphs.length - 1; gi >= 0; gi--) {
    final g = glyphs[gi];
    final space = info.spaces[g.cluster];
    final double adv;
    if (useSpacing && space == SpaceType.aya) {
      adv = ayaSpacing;
    } else if (useSpacing && space == SpaceType.simple) {
      adv = simpleSpacing;
    } else {
      adv = g.xAdvance.toDouble();
    }
    currentX -= adv;

    // Whitespace just advances the cursor — it owns no glyph or word rect.
    if (space != null) continue;

    final w = (g.cluster >= 0 && g.cluster < clusterWord.length)
        ? clusterWord[g.cluster]
        : 0;
    // device-px x extent of this glyph's advance box
    final gLeft = (currentX) * sx;
    final gRight = (currentX + adv) * sx;
    final lo = gLeft < gRight ? gLeft : gRight;
    final hi = gLeft < gRight ? gRight : gLeft;
    wordMinX[w] =
        wordMinX.containsKey(w) ? (lo < wordMinX[w]! ? lo : wordMinX[w]!) : lo;
    wordMaxX[w] =
        wordMaxX.containsKey(w) ? (hi > wordMaxX[w]! ? hi : wordMaxX[w]!) : hi;

    final cmds = shaper.glyphOutline(g.glyphId); // shaper-level memoized
    if (cmds.isEmpty) continue;

    final path = _glyphPath(
        cmds, currentX + g.xOffset, g.yOffset.toDouble(), ascender, sx, sy);
    final b = path.getBounds();
    if (b.left < minX) minX = b.left;
    if (b.right > maxX) maxX = b.right;

    paths.add(path);
    pathWords.add(w);
    final wi = info.wordInfos[w];
    pathChar.add(g.cluster - wi.startIndex);
  }

  final metricHeight = metricHeightFu * sy;

  final wordRects = <ui.Rect>[];
  for (var w = 0; w < info.wordInfos.length; w++) {
    if (wordMinX.containsKey(w) && wordMaxX[w]! > wordMinX[w]!) {
      wordRects
          .add(ui.Rect.fromLTRB(wordMinX[w]!, 0, wordMaxX[w]!, metricHeight));
    } else {
      wordRects.add(ui.Rect.zero);
    }
  }

  if (paths.isEmpty || maxX <= minX || metricHeight <= 0) {
    return PreparedLine(
      paths: const [],
      pathWordIndices: const [],
      pathCharInWord: const [],
      wordRects: wordRects,
      minX: 0,
      minY: 0,
      width: 0,
      height: 0,
    );
  }

  return PreparedLine(
    paths: paths,
    pathWordIndices: pathWords,
    pathCharInWord: pathChar,
    wordRects: wordRects,
    minX: minX,
    minY: 0,
    width: maxX - minX,
    height: metricHeight,
  );
}

ui.Picture _recordPreparedLine(
  PreparedLine prepared, {
  required double scaleX,
  required double scaleY,
  required double offsetX,
  required ui.Color color,
  List<int>? pathIndices,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(offsetX, 0);
  canvas.scale(scaleX, scaleY);
  final paint = ui.Paint()
    ..color = color
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.fill;
  if (pathIndices == null) {
    for (final p in prepared.paths) {
      canvas.drawPath(p, paint);
    }
  } else {
    for (final i in pathIndices) {
      if (i < 0 || i >= prepared.paths.length) continue;
      canvas.drawPath(prepared.paths[i], paint);
    }
  }
  return recorder.endRecording();
}

/// Rasterize a [PreparedLine] (already in device px) into an image at the given
/// display [scaleX]/[scaleY] and [color]. Used by the bitmap widget.
Future<ui.Image> rasterizePreparedLine(
  PreparedLine prepared, {
  required double scaleX,
  required double scaleY,
  required double offsetX,
  required ui.Color color,
  required int pixelWidth,
  required int pixelHeight,
  List<int>? pathIndices,
}) {
  final picture = _recordPreparedLine(
    prepared,
    scaleX: scaleX,
    scaleY: scaleY,
    offsetX: offsetX,
    color: color,
    pathIndices: pathIndices,
  );
  return picture
      .toImage(pixelWidth, pixelHeight)
      .whenComplete(picture.dispose);
}

/// Same as [rasterizePreparedLine], but blocks until the image is ready so
/// the first layout frame can report a real height.
ui.Image rasterizePreparedLineSync(
  PreparedLine prepared, {
  required double scaleX,
  required double scaleY,
  required double offsetX,
  required ui.Color color,
  required int pixelWidth,
  required int pixelHeight,
  List<int>? pathIndices,
}) {
  final picture = _recordPreparedLine(
    prepared,
    scaleX: scaleX,
    scaleY: scaleY,
    offsetX: offsetX,
    color: color,
    pathIndices: pathIndices,
  );
  try {
    return picture.toImageSync(pixelWidth, pixelHeight);
  } finally {
    picture.dispose();
  }
}
