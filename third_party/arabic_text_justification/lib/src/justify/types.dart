/// Data model + constants for the kashida justification engine.
///
/// Ported from the DigitalKhatt website's `just.service.ts` and
/// `qurantext.service.ts`. Names are kept close to the originals to make the
/// port auditable; Dart conventions (lowerCamel enums) are applied.
library;

import 'hb_shaper.dart';

/// The em size the engine measures against, in font units. The DigitalKhatt
/// fonts are 1000 UPEM, so measuring at 1000 keeps shaping scale == 1.
const int kFontSize = 1000;

enum SpaceType { simple, aya }

/// Mushaf layouts. Order matters: NewMadinah is the default (the `/digitalmushaf`
/// landing page), backed by `madina.otf`.
enum MushafLayoutType { newMadinah, oldMadinah, indoPak15Lines }

/// Outcome of attempting to apply a feature set to a word, mirroring the TS
/// `AppliedResult` enum.
enum AppliedResult { noChange, positive, overflow, forbiden }

/// Kashida stretch families, in the priority order the engine tries them.
/// Numeric values mirror the TS enum (used only as map keys / identity).
enum StretchType {
  none,
  beh,
  finaAscendant,
  otherKashidas,
  kaf,
  secondKashidaNotSameSubWord,
  secondKashidaSameSubWord,
}

/// A resolved OpenType feature (tag + value) applied at a character index.
class TextFontFeatures {
  String name;
  int value;
  TextFontFeatures(this.name, this.value);

  TextFontFeatures clone() => TextFontFeatures(name, value);
}

/// A maximal joined sub-run within a word (split at right-no-join letters / hamza).
class SubWordInfo {
  String baseText;
  final List<int> baseIndexes;
  SubWordInfo({this.baseText = '', List<int>? baseIndexes})
      : baseIndexes = baseIndexes ?? <int>[];
}

/// A whitespace-delimited word on a line, with its "base" (joining) letters and
/// sub-words pre-computed for kashida matching.
class WordInfo {
  int startIndex;
  int endIndex;
  String text;
  String baseText;
  final List<int> baseIndexes;
  final List<SubWordInfo> subwords;

  WordInfo({
    required this.startIndex,
    required this.endIndex,
    this.text = '',
    this.baseText = '',
    List<int>? baseIndexes,
    List<SubWordInfo>? subwords,
  })  : baseIndexes = baseIndexes ?? <int>[],
        subwords = subwords ?? <SubWordInfo>[];
}

/// The analyzed structure of a single line, independent of any shaping.
class LineTextInfo {
  final String lineText;
  final List<int> ayaSpaceIndexes;
  final List<int> simpleSpaceIndexes;
  final Map<int, SpaceType> spaces;
  final List<WordInfo> wordInfos;

  /// Global features applied to the whole line (e.g. `bism` on the basmala
  /// lines of pages 1–2). Null when none.
  final List<HbFeature>? features;

  LineTextInfo({
    required this.lineText,
    required this.ayaSpaceIndexes,
    required this.simpleSpaceIndexes,
    required this.spaces,
    required this.wordInfos,
    this.features,
  });
}

/// Per-word running layout state during justification.
class LayoutResult {
  double parWidth;

  /// Which stretch types have been applied to this word, keyed by family.
  /// Value is `[subWordIndex, characterIndexInSubWord]`.
  final Map<StretchType, List<int>> appliedKashidas;

  LayoutResult(
      {required this.parWidth, Map<StretchType, List<int>>? appliedKashidas})
      : appliedKashidas = appliedKashidas ?? <StretchType, List<int>>{};
}

/// Mutable accumulator threaded through the lookup passes.
class JustInfo {
  Map<int, List<TextFontFeatures>> fontFeatures;
  final double desiredWidth;
  double textLineWidth;
  final List<LayoutResult> layoutResults;
  final HbShaper shaper;
  final List<HbFeature> lineFeatures;

  JustInfo({
    required this.fontFeatures,
    required this.desiredWidth,
    required this.textLineWidth,
    required this.layoutResults,
    required this.shaper,
    required this.lineFeatures,
  });
}

/// The justification result for one line, consumed by the renderer.
class JustResultByLine {
  /// OpenType features to apply, keyed by character index in the line.
  final Map<int, List<TextFontFeatures>> fontFeatures;
  final double simpleSpacing;
  final double ayaSpacing;
  final double xScale;

  JustResultByLine({
    required this.fontFeatures,
    required this.simpleSpacing,
    required this.ayaSpacing,
    required this.xScale,
  });
}

// ── Letter classes (UTF-16; all BMP so JS/Dart code-unit indexing matches) ──

const String rightNoJoinLetters = 'آاٱأإدذرزوؤءة';
const String dualJoinLetters = 'بتثجحخسشصضطظعغفقكلمنهيئى';
const String finalAscendant = 'آادذٱأإكلهة';

/// Code units of all "base" (joining) letters — the union of dual-join and
/// right-no-join letters. Built once.
final Set<int> bases = () {
  final s = <int>{};
  for (var i = 0; i < dualJoinLetters.length; i++) {
    s.add(dualJoinLetters.codeUnitAt(i));
  }
  for (var i = 0; i < rightNoJoinLetters.length; i++) {
    s.add(rightNoJoinLetters.codeUnitAt(i));
  }
  return s;
}();
