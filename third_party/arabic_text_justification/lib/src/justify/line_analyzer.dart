/// Port of `analyzeLineForJust` from the DigitalKhatt website's `just.service.ts`.
///
/// Pure string processing — no shaping — so it is independently unit-testable.
/// Splits a line into words and joined sub-words, records space classification
/// (simple vs. aya), and pre-computes the base-letter indexes the kashida
/// lookups rely on.
library;

import 'hb_shaper.dart';
import 'types.dart';

/// Code unit at [index], or -1 when out of range. Mirrors JS `charCodeAt`
/// returning `NaN` for out-of-range indices (the original relies on the
/// resulting comparisons being false).
int _codeUnitOr(String s, int index) =>
    (index >= 0 && index < s.length) ? s.codeUnitAt(index) : -1;

const int _ayaMark = 0x06DD; // ۝ END OF AYAH
const int _arabicIndicZero = 0x0660;
const int _arabicIndicNine = 0x0669;

/// Analyze a single [lineText] into a [LineTextInfo].
///
/// [bism] marks the basmala line (pages 1–2, line index 1 on the website),
/// which gets a global `bism` feature applied to the whole line.
LineTextInfo analyzeLineForJust(String lineText, {bool bism = false}) {
  final info = LineTextInfo(
    lineText: lineText,
    ayaSpaceIndexes: <int>[],
    simpleSpaceIndexes: <int>[],
    spaces: <int, SpaceType>{},
    wordInfos: <WordInfo>[],
    features: bism
        ? const [HbFeature(tag: 'bism', value: 1, start: 0, end: -1)]
        : null,
  );

  var currentWord = WordInfo(
    startIndex: 0,
    endIndex: -1,
    subwords: [SubWordInfo()],
  );
  info.wordInfos.add(currentWord);

  for (var i = 0; i < lineText.length; i++) {
    final char = lineText[i];
    if (char == ' ') {
      final prev = _codeUnitOr(lineText, i - 1);
      final next = _codeUnitOr(lineText, i + 1);
      if ((prev >= _arabicIndicZero && prev <= _arabicIndicNine) ||
          next == _ayaMark) {
        info.ayaSpaceIndexes.add(i);
        info.spaces[i] = SpaceType.aya;
      } else {
        info.simpleSpaceIndexes.add(i);
        info.spaces[i] = SpaceType.simple;
      }
      currentWord = WordInfo(
        startIndex: i + 1,
        endIndex: i,
        subwords: [SubWordInfo()],
      );
      info.wordInfos.add(currentWord);
    } else {
      currentWord.text += char;
      if (bases.contains(char.codeUnitAt(0))) {
        currentWord.baseText += char;
        currentWord.baseIndexes.add(i - currentWord.startIndex);
        var isHamza = false;
        if (char == 'ء') {
          currentWord.subwords.add(SubWordInfo());
          isHamza = true;
        }
        final subWord = currentWord.subwords.last;
        subWord.baseText += char;
        subWord.baseIndexes.add(i - currentWord.startIndex);
        if (i < lineText.length - 1 &&
            rightNoJoinLetters.contains(char) &&
            !isHamza) {
          currentWord.subwords.add(SubWordInfo());
        }
      }
      currentWord.endIndex++;
    }
  }

  return info;
}
