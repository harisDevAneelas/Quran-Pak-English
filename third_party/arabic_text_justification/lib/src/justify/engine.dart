/// The kashida justification engine — a pure-Dart port of the DigitalKhatt
/// website's `just.service.ts`.
///
/// It stretches a line of Arabic text to a desired width by repeatedly applying
/// kashida / alternate OpenType features and re-measuring through an [HbShaper],
/// exactly like the website does. No HarfBuzz justification branch is involved:
/// the shaper only does *standard* shaping; all of the logic lives here.
///
/// Names mirror the originals to keep the port auditable. The one structural
/// difference: where the TS relies on JS regex match indices (the `d` flag),
/// this port matches letter classes with explicit right-to-left / left-to-right
/// scans over the sub-word "base text" (which also avoids JS's
/// overlapping-match quirks).
library;

import 'hb_shaper.dart';
import 'types.dart';

// ── Width helpers ───────────────────────────────────────────────────────────

/// Equivalent of the website's `getWidth(text, font, FONTSIZE, features)`.
/// With the DigitalKhatt 1000-UPEM fonts the scale factor is 1.
double _getWidth(HbShaper shaper, String text, List<HbFeature> features) =>
    shaper.measure(text, features) * kFontSize / shaper.unitsPerEm;

/// Equivalent of the website's `getWordWidth` — sums advances after applying the
/// per-character features accumulated so far. Returns raw font units.
double _getWordWidth(
  WordInfo wordInfo,
  Map<int, List<TextFontFeatures>> justResults,
  HbShaper shaper,
  List<HbFeature> lineFeatures,
) {
  final features = <HbFeature>[...lineFeatures];
  for (var i = wordInfo.startIndex; i <= wordInfo.endIndex; i++) {
    final justInfo = justResults[i];
    if (justInfo != null) {
      for (final feat in justInfo) {
        features.add(HbFeature(
          tag: feat.name,
          value: feat.value,
          start: i - wordInfo.startIndex,
          end: i - wordInfo.startIndex + 1,
        ));
      }
    }
  }
  return shaper.measure(wordInfo.text, features).toDouble();
}

AppliedResult _tryApplyFeatures(
  int wordIndex,
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  Map<int, List<TextFontFeatures>> newFeatures,
) {
  final layout = justInfo.layoutResults[wordIndex];
  final wordInfo = lineTextInfo.wordInfos[wordIndex];

  final wordNewWidth = _getWordWidth(
      wordInfo, newFeatures, justInfo.shaper, justInfo.lineFeatures);
  final diff = wordNewWidth - layout.parWidth;
  if (wordNewWidth != layout.parWidth &&
      justInfo.textLineWidth + diff < justInfo.desiredWidth) {
    justInfo.textLineWidth += diff;
    layout.parWidth = wordNewWidth;
    justInfo.fontFeatures = newFeatures;
    return AppliedResult.positive;
  } else if (diff == 0) {
    return AppliedResult.noChange;
  } else {
    return AppliedResult.overflow;
  }
}

/// One feature to apply, with an optional combine rule for an existing value.
class _AppliedFeature {
  final TextFontFeatures feature;
  final int Function(int? prev, int curr)? calcNewValue;
  _AppliedFeature(this.feature, [this.calcNewValue]);
}

List<TextFontFeatures> _mergeFeatures(
  List<TextFontFeatures>? prevFeatures,
  List<_AppliedFeature> newFeatures,
) {
  final merged = <TextFontFeatures>[
    if (prevFeatures != null) ...prevFeatures.map((x) => x.clone()),
  ];
  for (final nf in newFeatures) {
    TextFontFeatures? exist;
    for (final pf in merged) {
      if (pf.name == nf.feature.name) {
        exist = pf;
        break;
      }
    }
    if (exist != null) {
      exist.value = nf.calcNewValue != null
          ? nf.calcNewValue!(exist.value, nf.feature.value)
          : nf.feature.value;
    } else {
      merged.add(TextFontFeatures(
        nf.feature.name,
        nf.calcNewValue != null
            ? nf.calcNewValue!(null, nf.feature.value)
            : nf.feature.value,
      ));
    }
  }
  return merged;
}

// ── Small string / list utilities ───────────────────────────────────────────

bool _inSet(String set, String? ch) => ch != null && set.contains(ch);

String? _charAt(String s, int i) => (i >= 0 && i < s.length) ? s[i] : null;

/// `list.at(index)` with JS-style negative indexing; null when out of range.
T? _at<T>(List<T> list, int index) {
  var i = index;
  if (i < 0) i += list.length;
  return (i >= 0 && i < list.length) ? list[i] : null;
}

bool _pairAt(String s, int i, String c1, String c2) =>
    i >= 0 && i + 1 < s.length && _inSet(c1, s[i]) && _inSet(c2, s[i + 1]);

/// Rightmost start index of a [c1][c2] pair, within [minStart, length-2-endSlack].
int? _lastPair(String s, String c1, String c2,
    {int minStart = 0, int endSlack = 0}) {
  for (var i = s.length - 2 - endSlack; i >= minStart; i--) {
    if (_pairAt(s, i, c1, c2)) return i;
  }
  return null;
}

/// All start indices of [c1][c2] pairs, left to right (overlapping allowed,
/// matching the greedy/global semantics the original relies on).
List<int> _allPairs(String s, String c1, String c2) {
  final r = <int>[];
  for (var i = 0; i + 1 < s.length; i++) {
    if (_pairAt(s, i, c1, c2)) r.add(i);
  }
  return r;
}

// ── Letter classes used by the kashida lookups ──────────────────────────────

// applyKashidasSubWords classes.
const String _right = 'بتثنيئجحخسشصضطظعغفقمه';
const String _leftNoRz = 'ئبتثنيجحخطظعغفقةلم';
const String _behL1 = 'بتثنيسشصض';
const String _behL2 = 'بتثنيم';
const String _finaAsc2 = 'آادذٱأإكلهة';
const String _rz = 'رز';

// applySimpleJust classes.
const String _rightKash = 'بتثجحخسشصضطظعغفقمنهيئى';
const String _jhk = 'جحخ';
const String _leftKashidaMedi = 'بتثجحخسشعغفقكلمنيئىآاٱأإدذرزؤة';
const String _altFin1 = 'بتثفكنصضسشقيئى';
const String _finalKashida2 = 'دذآاٱأإملهة';
const String _finalKashidaEndWord2 = 'آاٱأإملهة';
const String _hahFinal2 = 'هة';

// ── applyKashida / applyKaf / applyAlternate ────────────────────────────────

AppliedResult _applyKashida(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  int wordIndex,
  int subWordIndex,
  int firstSubWordMatchIndex,
  int secondSubWordMacthIndex,
) {
  final wordInfos = lineTextInfo.wordInfos;
  final lineText = lineTextInfo.lineText;
  final wordInfo = wordInfos[wordIndex];
  final subWordInfo = wordInfo.subwords[subWordIndex];
  final firstMatchIndex = subWordInfo.baseIndexes[firstSubWordMatchIndex];
  final secondMatchIndex = subWordInfo.baseIndexes[secondSubWordMacthIndex];
  final firstIndexInLine = wordInfo.startIndex + firstMatchIndex;
  final secondIndexInLine = wordInfo.startIndex + secondMatchIndex;

  final tempResult = Map<int, List<TextFontFeatures>>.of(justInfo.fontFeatures);

  final firstPrevFeatures = tempResult[firstIndexInLine];
  final secondPrevFeatures = tempResult[secondIndexInLine];

  const forbidden = AppliedResult.forbiden;

  if (secondPrevFeatures != null &&
      secondPrevFeatures.any((a) => a.name == 'cv01')) {
    return forbidden;
  }

  final chark3 = lineText[firstIndexInLine];
  final chark4 = lineText[secondIndexInLine];

  final lastBaseIndex = _at(subWordInfo.baseIndexes, -1);
  final finalSubWordMatch = lastBaseIndex == secondMatchIndex;

  if (chark4 == 'ق' && lastBaseIndex == secondMatchIndex) {
    return forbidden;
  } else if (chark3 == 'ل' &&
      ((chark4 == 'ك' || chark4 == 'د' || chark4 == 'ذ' || chark4 == 'ة') ||
          (chark4 == 'ه' && lastBaseIndex == secondMatchIndex))) {
    return forbidden;
  } else if ('ئبتثنيى'.contains(chark3) &&
      subWordInfo.baseIndexes[0] != firstMatchIndex &&
      'رز'.contains(chark4)) {
    return forbidden;
  }

  final secondNewFeatures = <TextFontFeatures>[];

  final prevCv01 =
      firstPrevFeatures?.where((a) => a.name == 'cv01').firstOrNull?.value;
  final cv01Value = ((prevCv01 ?? 0) + 1).clamp(0, 6);

  final firstAppliedFeatures = <_AppliedFeature>[
    _AppliedFeature(TextFontFeatures('cv01', 1), (prev, curr) => cv01Value),
  ];

  if ('بتثنيئ'.contains(chark3)) {
    firstAppliedFeatures.add(_AppliedFeature(TextFontFeatures('cv10', 1)));
  }

  // decomposition
  final base2 = _charAt(subWordInfo.baseText, 2);
  final baseLast = _at(subWordInfo.baseText.split(''), -1);
  final secondToLastBaseIndex = _at(subWordInfo.baseIndexes, -2);

  void deco(String name) {
    firstAppliedFeatures.add(_AppliedFeature(TextFontFeatures(name, 1)));
    secondNewFeatures.add(TextFontFeatures(name, 1));
  }

  if ('ه'.contains(chark3) && 'م'.contains(chark4) && finalSubWordMatch) {
    deco('cv11');
  } else if ('بتثنيئ'.contains(chark3) &&
      subWordInfo.baseIndexes[0] == firstMatchIndex &&
      'جحخ'.contains(chark4)) {
    deco('cv12');
  } else if ('م'.contains(chark3) &&
      subWordInfo.baseIndexes[0] == firstMatchIndex &&
      'جحخ'.contains(chark4)) {
    deco('cv13');
  } else if ('فق'.contains(chark3) &&
      subWordInfo.baseIndexes[0] == firstMatchIndex &&
      'جحخ'.contains(chark4)) {
    deco('cv14');
  } else if ('ل'.contains(chark3) &&
      subWordInfo.baseIndexes[0] == firstMatchIndex &&
      'جحخ'.contains(chark4)) {
    deco('cv15');
  } else if ('عغ'.contains(chark3) &&
      subWordInfo.baseIndexes[0] == firstMatchIndex &&
      ('آادذٱأإل'.contains(chark4) ||
          ('بتثنيئ'.contains(chark4) && _inSet('سش', base2)))) {
    deco('cv16');
  } else if ('جحخ'.contains(chark3)) {
    if ('آادذٱأإل'.contains(chark4) ||
        ('هة'.contains(chark4) && finalSubWordMatch) ||
        ('بتثنيئ'.contains(chark4) &&
            secondToLastBaseIndex == secondMatchIndex &&
            _inSet('رزن', baseLast))) {
      deco('cv16');
    } else if (subWordInfo.baseIndexes[0] == firstMatchIndex &&
        'م'.contains(chark4)) {
      deco('cv18');
    }
  } else if ('سشصض'.contains(chark3) && 'رز'.contains(chark4)) {
    deco('cv17');
  }

  final firstNewFeatures =
      _mergeFeatures(firstPrevFeatures, firstAppliedFeatures);

  final int cv02Value;
  if (finalAscendant.contains(chark4) && finalSubWordMatch) {
    cv02Value = cv01Value;
  } else {
    cv02Value = 2 * cv01Value;
  }
  secondNewFeatures.add(TextFontFeatures('cv02', cv02Value));

  tempResult[firstIndexInLine] = firstNewFeatures;
  tempResult[secondIndexInLine] = secondNewFeatures;

  return _tryApplyFeatures(wordIndex, lineTextInfo, justInfo, tempResult);
}

AppliedResult _applyKaf(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  int wordIndex,
  int subWordIndex,
  int firstSubWordMatchIndex,
  int secondSubWordMacthIndex,
) {
  final wordInfos = lineTextInfo.wordInfos;
  final lineText = lineTextInfo.lineText;
  final wordInfo = wordInfos[wordIndex];
  final subWordInfo = wordInfo.subwords[subWordIndex];
  final firstMatchIndex = subWordInfo.baseIndexes[firstSubWordMatchIndex];
  final secondMatchIndex = subWordInfo.baseIndexes[secondSubWordMacthIndex];
  final firstIndexInLine = wordInfo.startIndex + firstMatchIndex;
  final secondIndexInLine = wordInfo.startIndex + secondMatchIndex;

  final tempResult = Map<int, List<TextFontFeatures>>.of(justInfo.fontFeatures);

  final firstPrevFeatures = tempResult[firstIndexInLine];
  final secondPrevFeatures = tempResult[secondIndexInLine];

  tempResult[firstIndexInLine] = _mergeFeatures(
    firstPrevFeatures,
    [_AppliedFeature(TextFontFeatures('cv03', 1), (p, c) => 1)],
  );

  final firstNewFeatures = _mergeFeatures(
    secondPrevFeatures,
    [_AppliedFeature(TextFontFeatures('cv03', 1), (p, c) => 1)],
  );
  tempResult[secondIndexInLine] = firstNewFeatures;

  int? fathaIndex;
  if (_charAt(lineText, firstIndexInLine + 1) == 'َ') {
    fathaIndex = firstIndexInLine + 1;
  } else if (_charAt(lineText, firstIndexInLine + 1) == 'ّ' &&
      _charAt(lineText, firstIndexInLine + 2) == 'َ') {
    fathaIndex = firstIndexInLine + 2;
  }

  if (fathaIndex != null) {
    final cv01Value =
        firstNewFeatures.where((a) => a.name == 'cv01').firstOrNull?.value ?? 0;
    tempResult[fathaIndex] = [TextFontFeatures('cv01', 1 + (cv01Value ~/ 3))];
  }

  return _tryApplyFeatures(wordIndex, lineTextInfo, justInfo, tempResult);
}

AppliedResult _applyAlternate(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  int wordIndex,
  int indexInLine,
) {
  final lineText = lineTextInfo.lineText;
  const forbidden = AppliedResult.forbiden;

  final tempResult = Map<int, List<TextFontFeatures>>.of(justInfo.fontFeatures);
  final prevFeatures = tempResult[indexInLine];

  final cv02 =
      prevFeatures?.where((a) => a.name == 'cv02').firstOrNull?.value ?? 0;
  if (cv02 > 0) return forbidden;

  final newFeatures = _mergeFeatures(prevFeatures, [
    _AppliedFeature(
      TextFontFeatures('cv01', 1),
      (prev, curr) => ((prev ?? 0) + curr).clamp(0, 12),
    ),
  ]);
  tempResult[indexInLine] = newFeatures;

  int? fathaIndex;
  if (_charAt(lineText, indexInLine + 1) == 'َ') {
    fathaIndex = indexInLine + 1;
  } else if (_charAt(lineText, indexInLine + 1) == 'ّ' &&
      _charAt(lineText, indexInLine + 2) == 'َ') {
    fathaIndex = indexInLine + 2;
  }

  if (fathaIndex != null) {
    final cv01FathaValue =
        newFeatures.where((a) => a.name == 'cv01').firstOrNull?.value ?? 0;
    tempResult[fathaIndex] = [
      TextFontFeatures('cv01', 1 + (cv01FathaValue ~/ 3))
    ];
  }

  return _tryApplyFeatures(wordIndex, lineTextInfo, justInfo, tempResult);
}

// ── Sub-word matching per stretch type ──────────────────────────────────────

/// Per-subword candidate offsets (index into the sub-word's baseIndexes) for a
/// given [type], in the priority order the original's regex list produces.
List<int> _typeMatches(SubWordInfo sub, StretchType type) {
  final bt = sub.baseText;
  switch (type) {
    case StretchType.beh:
      final o = _lastPair(bt, _behL1, _behL2, minStart: 1, endSlack: 1);
      return o != null ? [o] : const [];
    case StretchType.finaAscendant:
      return _pairAt(bt, bt.length - 2, _right, _finaAsc2)
          ? [bt.length - 2]
          : const [];
    case StretchType.otherKashidas:
      final r = <int>[];
      final reh = _lastPair(bt, _right, _rz);
      if (reh != null) r.add(reh);
      final other = _lastPair(bt, _right, _leftNoRz);
      if (other != null) r.add(other);
      return r;
    case StretchType.kaf:
      for (var i = bt.length - 2; i >= 0; i--) {
        if (bt[i] == 'ك') return [i];
      }
      return const [];
    case StretchType.secondKashidaNotSameSubWord:
      final r = <int>[];
      final beh = _lastPair(bt, _behL1, _behL2, minStart: 1, endSlack: 1);
      if (beh != null) r.add(beh);
      if (_pairAt(bt, bt.length - 2, _right, _finaAsc2)) r.add(bt.length - 2);
      final reh = _lastPair(bt, _right, _rz);
      if (reh != null) r.add(reh);
      final other = _lastPair(bt, _right, _leftNoRz);
      if (other != null) r.add(other);
      return r;
    case StretchType.secondKashidaSameSubWord:
      final r = <int>[];
      final beh = _lastPair(bt, _behL1, _behL2, minStart: 1, endSlack: 1);
      if (beh != null) r.add(beh);
      if (_pairAt(bt, bt.length - 2, _right, _finaAsc2)) r.add(bt.length - 2);
      r.addAll(_allPairs(bt, _right, _rz));
      r.addAll(_allPairs(bt, _right, _leftNoRz));
      return r;
    case StretchType.none:
      return const [];
  }
}

class _SubWordsMatch {
  final List<int> subWordIndexes = [];
  final Map<int, List<int>> matches = {}; // subWordIndex -> offsets
}

_SubWordsMatch _matchSubWords(WordInfo wordInfo, StretchType type) {
  final result = _SubWordsMatch();
  for (var subIndex = 0; subIndex < wordInfo.subwords.length; subIndex++) {
    final offsets = _typeMatches(wordInfo.subwords[subIndex], type);
    result.matches[subIndex] = offsets;
    if (offsets.isNotEmpty) result.subWordIndexes.add(subIndex);
  }
  return result;
}

bool _applyKashidasSubWords(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  StretchType type,
  int nbLevels,
) {
  final wordInfos = lineTextInfo.wordInfos;

  final matchresult = <_SubWordsMatch>[
    for (final w in wordInfos) _matchSubWords(w, type),
  ];

  for (var level = 1; level <= nbLevels; level++) {
    for (var wordIndex = 0; wordIndex < wordInfos.length; wordIndex++) {
      final subWordsMatch = matchresult[wordIndex];
      final wordLayout = justInfo.layoutResults[wordIndex];

      final type1Applied = wordLayout.appliedKashidas[StretchType.beh];
      final type2Applied =
          wordLayout.appliedKashidas[StretchType.finaAscendant];
      final type3Applied =
          wordLayout.appliedKashidas[StretchType.otherKashidas];
      final type5Applied =
          wordLayout.appliedKashidas[StretchType.secondKashidaNotSameSubWord];

      if (type == StretchType.beh &&
          (type2Applied != null || type3Applied != null)) {
        continue;
      }
      if (type == StretchType.finaAscendant &&
          (type1Applied != null || type3Applied != null)) {
        continue;
      }
      if (type == StretchType.otherKashidas &&
          (type1Applied != null || type2Applied != null)) {
        continue;
      }

      var done = false;
      for (var i = subWordsMatch.subWordIndexes.length - 1;
          i >= 0 && !done;
          i--) {
        final subWordIndex = subWordsMatch.subWordIndexes[i];
        for (final firstSubWordMatchIndex
            in subWordsMatch.matches[subWordIndex]!) {
          final secondSubWordMacthIndex = firstSubWordMatchIndex + 1;

          if (type == StretchType.secondKashidaNotSameSubWord) {
            final type123 = type1Applied ?? type2Applied ?? type3Applied;
            if (type123 != null && type123[0] == subWordIndex) continue;
          } else if (type == StretchType.secondKashidaSameSubWord) {
            final type123 = type1Applied ?? type2Applied ?? type3Applied;
            if (type123 != null &&
                type123[0] == subWordIndex &&
                type123[1] == firstSubWordMatchIndex) {
              continue;
            }
            if (type5Applied != null &&
                type5Applied[0] == subWordIndex &&
                type5Applied[1] == firstSubWordMatchIndex) {
              continue;
            }
          }

          final appliedResult = type == StretchType.kaf
              ? _applyKaf(lineTextInfo, justInfo, wordIndex, subWordIndex,
                  firstSubWordMatchIndex, secondSubWordMacthIndex)
              : _applyKashida(lineTextInfo, justInfo, wordIndex, subWordIndex,
                  firstSubWordMatchIndex, secondSubWordMacthIndex);

          if (appliedResult == AppliedResult.positive) {
            wordLayout.appliedKashidas[type] = [
              subWordIndex,
              firstSubWordMatchIndex
            ];
          } else if (appliedResult == AppliedResult.overflow) {
            return true;
          } else if (appliedResult == AppliedResult.forbiden) {
            continue;
          }

          done = true;
          break;
        }
      }
    }
  }
  return false;
}

bool _applyAlternatesSubWords(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  String chars,
  int nbLevels,
) {
  final wordInfos = lineTextInfo.wordInfos;

  // ^.*(?<alt>[chars])$  →  last base char of a sub-word is in [chars].
  // matchSubWords iterates sub-words; the apply loop uses the highest matching
  // sub-word index, so record that here.
  final matchresult = <int?>[];
  for (final w in wordInfos) {
    int? subWordIndex;
    for (var subIndex = w.subwords.length - 1; subIndex >= 0; subIndex--) {
      final bt = w.subwords[subIndex].baseText;
      if (bt.isNotEmpty && chars.contains(bt[bt.length - 1])) {
        subWordIndex = subIndex;
        break;
      }
    }
    matchresult.add(subWordIndex);
  }

  for (var level = 1; level <= nbLevels; level++) {
    for (var wordIndex = 0; wordIndex < wordInfos.length; wordIndex++) {
      final wordInfo = wordInfos[wordIndex];
      final subWordIndex = matchresult[wordIndex];
      if (subWordIndex == null) continue;

      final sub = wordInfo.subwords[subWordIndex];
      final matchIndex = sub.baseIndexes.length - 1; // last base char
      final indexInLine = wordInfo.startIndex + sub.baseIndexes[matchIndex];

      final appliedResult =
          _applyAlternate(lineTextInfo, justInfo, wordIndex, indexInLine);
      if (appliedResult == AppliedResult.overflow) return true;
      // forbiden → try next word; positive/noChange → next word.
    }
  }
  return false;
}

// ── applySimpleJust (used for IndoPak layout) ───────────────────────────────

enum _SimpleKind { alternate, kashida, kaf }

class _SimpleMatch {
  final _SimpleKind kind;
  final int subWordIndex;
  final int offset;
  _SimpleMatch(this.kind, this.subWordIndex, this.offset);
}

/// Branch tests of `regExprSimple`, in priority order. Returns kind + offset.
_SimpleMatch? _regExprSimple(int subWordIndex, String bt) {
  // 1: altFin  ^.*([altFin1])$
  if (bt.isNotEmpty && _altFin1.contains(bt[bt.length - 1])) {
    return _SimpleMatch(_SimpleKind.alternate, subWordIndex, bt.length - 1);
  }
  // 2: hah-medi ^.*([jhk][leftKashidaMedi]).*$  (rightmost)
  final hahMedi = _lastPair(bt, _jhk, _leftKashidaMedi);
  if (hahMedi != null)
    return _SimpleMatch(_SimpleKind.kashida, subWordIndex, hahMedi);
  // 3: hah-final ^.*([jhk][هة])$
  if (_pairAt(bt, bt.length - 2, _jhk, _hahFinal2)) {
    return _SimpleMatch(_SimpleKind.kashida, subWordIndex, bt.length - 2);
  }
  // 4: finalKashida ^.*([rightKash][finalKashida2])$
  if (_pairAt(bt, bt.length - 2, _rightKash, _finalKashida2)) {
    return _SimpleMatch(_SimpleKind.kashida, subWordIndex, bt.length - 2);
  }
  // 5: behBeh ^.+([behL1][behL2]).+$
  final beh = _lastPair(bt, _behL1, _behL2, minStart: 1, endSlack: 1);
  if (beh != null) return _SimpleMatch(_SimpleKind.kashida, subWordIndex, beh);
  // 6: reh .*([rightKash][رز])
  final reh = _lastPair(bt, _rightKash, _rz);
  if (reh != null) return _SimpleMatch(_SimpleKind.kashida, subWordIndex, reh);
  // 7: other .*([rightKash](?:ل|[leftKashidaMedi]))
  final other = _lastPair(bt, _rightKash, _leftKashidaMedi);
  if (other != null)
    return _SimpleMatch(_SimpleKind.kashida, subWordIndex, other);
  // 8: kaf ^.*([ك].).*$
  for (var i = bt.length - 2; i >= 0; i--) {
    if (bt[i] == 'ك') return _SimpleMatch(_SimpleKind.kaf, subWordIndex, i);
  }
  return null;
}

_SimpleMatch? _simpleMatchForWord(WordInfo wordInfo) {
  if (wordInfo.baseText.isEmpty) return null;
  final lastIndex = wordInfo.subwords.length - 1;
  final lastSub = wordInfo.subwords[lastIndex];

  // type 1: altFin on the last sub-word.
  if (lastSub.baseText.isNotEmpty &&
      _altFin1.contains(lastSub.baseText[lastSub.baseText.length - 1])) {
    return _SimpleMatch(
        _SimpleKind.alternate, lastIndex, lastSub.baseText.length - 1);
  }

  final lastWordChar = wordInfo.baseText[wordInfo.baseText.length - 1];
  if ('يئى'.contains(lastWordChar)) return null;

  // type 2: regHahFinaAscenKashida on the last sub-word (always kashida).
  final bt = lastSub.baseText;
  final hahMedi = _lastPair(bt, _jhk, _leftKashidaMedi);
  if (hahMedi != null)
    return _SimpleMatch(_SimpleKind.kashida, lastIndex, hahMedi);
  if (_pairAt(bt, bt.length - 2, _jhk, _hahFinal2)) {
    return _SimpleMatch(_SimpleKind.kashida, lastIndex, bt.length - 2);
  }
  if (_pairAt(bt, bt.length - 2, _rightKash, _finalKashidaEndWord2)) {
    return _SimpleMatch(_SimpleKind.kashida, lastIndex, bt.length - 2);
  }

  // type 3: regExprSimple, scanning sub-words last → first.
  for (var subIndex = lastIndex; subIndex >= 0; subIndex--) {
    final m = _regExprSimple(subIndex, wordInfo.subwords[subIndex].baseText);
    if (m != null) return m;
  }
  return null;
}

bool _applySimpleJust(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  bool firstWordIncluded,
  bool wordByWord,
  int nbLevelAlt,
  int nbLevelKashida,
) {
  final wordInfos = lineTextInfo.wordInfos;
  final firstWordIndex = firstWordIncluded ? 0 : 1;

  final matchresult = <_SimpleMatch?>[
    for (var wordIndex = 0; wordIndex < wordInfos.length; wordIndex++)
      (wordInfos[wordIndex].baseText.isEmpty || wordIndex < firstWordIndex)
          ? null
          : _simpleMatchForWord(wordInfos[wordIndex]),
  ];

  final stretchedWords = <int, bool>{};

  final maxLevel = nbLevelAlt > nbLevelKashida ? nbLevelAlt : nbLevelKashida;
  for (var level = 1; level <= maxLevel; level++) {
    for (var wordIndex = wordInfos.length - 1;
        wordIndex >= firstWordIndex;
        wordIndex--) {
      if (stretchedWords[wordIndex + 1] == true) continue;

      final wordInfo = wordInfos[wordIndex];
      final m = matchresult[wordIndex];
      if (m == null) continue;

      AppliedResult? appliedResult;
      final sub = wordInfo.subwords[m.subWordIndex];

      if (m.kind == _SimpleKind.alternate) {
        if (level <= nbLevelAlt) {
          final indexInLine = wordInfo.startIndex + sub.baseIndexes[m.offset];
          appliedResult =
              _applyAlternate(lineTextInfo, justInfo, wordIndex, indexInLine);
        }
      } else if (level <= nbLevelKashida) {
        final first = m.offset;
        final second = m.offset + 1;
        if (m.kind == _SimpleKind.kaf) {
          appliedResult = _applyKaf(
              lineTextInfo, justInfo, wordIndex, m.subWordIndex, first, second);
        } else {
          appliedResult = _applyKashida(
              lineTextInfo, justInfo, wordIndex, m.subWordIndex, first, second);
        }
      }

      if (appliedResult == AppliedResult.overflow) {
        return true;
      } else if (appliedResult == AppliedResult.positive && wordByWord) {
        stretchedWords[wordIndex] = true;
      }
    }
  }
  return false;
}

// ── Top-level passes ────────────────────────────────────────────────────────

void _applyExperimentalJust(LineTextInfo lineTextInfo, JustInfo justInfo) {
  bool k(StretchType t, int n) =>
      _applyKashidasSubWords(lineTextInfo, justInfo, t, n);
  bool a(String c, int n) =>
      _applyAlternatesSubWords(lineTextInfo, justInfo, c, n);

  // ignore: unnecessary_statements
  k(StretchType.beh, 2) ||
      a('بتثكن', 2) ||
      k(StretchType.finaAscendant, 3) ||
      k(StretchType.otherKashidas, 2) ||
      a('ىصضسشفقيئ', 2) ||
      k(StretchType.kaf, 1) ||
      k(StretchType.beh, 1) ||
      a('بتثكن', 1) ||
      k(StretchType.finaAscendant, 1) ||
      k(StretchType.otherKashidas, 1) ||
      a('ىصضسشفقيئ', 1) ||
      a('بتثكن', 2) ||
      a('ىصضسشفقيئبتثكن', 2) ||
      k(StretchType.beh, 1) ||
      k(StretchType.finaAscendant, 1) ||
      k(StretchType.otherKashidas, 1) ||
      a('ىصضسشفقيئبتثكن', 2) ||
      k(StretchType.secondKashidaNotSameSubWord, 2) ||
      k(StretchType.secondKashidaSameSubWord, 2);
}

JustInfo _stretchLine(
  LineTextInfo lineTextInfo,
  JustInfo justInfo,
  MushafLayoutType mushafType,
) {
  if (mushafType == MushafLayoutType.newMadinah ||
      mushafType == MushafLayoutType.oldMadinah) {
    _applyExperimentalJust(lineTextInfo, justInfo);
  } else {
    _applySimpleJust(lineTextInfo, justInfo, true, false, 2, 2);
  }
  return justInfo;
}

/// Justify a single analyzed line to the desired width.
///
/// [fontSizeLineWidthRatio] mirrors the website: `desiredWidth = FONTSIZE /
/// fontSizeLineWidthRatio`. [spaceWidth] is the natural space advance in font
/// units. Returns the per-character features, space widths, and x-scale the
/// renderer applies.
JustResultByLine justifyLine(
  LineTextInfo lineTextInfo,
  HbShaper shaper,
  double fontSizeLineWidthRatio,
  double spaceWidth, {
  MushafLayoutType mushafType = MushafLayoutType.newMadinah,
}) {
  final lineFeatures = lineTextInfo.features ?? const <HbFeature>[];
  final desiredWidth = kFontSize / fontSizeLineWidthRatio;
  final lineText = lineTextInfo.lineText;

  final layOutResult = <LayoutResult>[];
  JustInfo? justResults;

  for (final wordInfo in lineTextInfo.wordInfos) {
    final parWidth = _getWidth(shaper, wordInfo.text, lineFeatures);
    layOutResult.add(LayoutResult(parWidth: parWidth));
  }

  var currentLineWidth = _getWidth(shaper, lineText, lineFeatures);
  final diff = desiredWidth - currentLineWidth;

  var xScale = 1.0;
  var simpleSpacing = spaceWidth;
  var ayaSpacing = spaceWidth;

  if (diff > 0) {
    {
      final maxStretchBySpace = spaceWidth < 100 ? spaceWidth : 100.0;
      final maxStretchByAyaSpace =
          (spaceWidth * 2) < 200 ? spaceWidth * 2 : 200.0;

      final maxStretch =
          maxStretchBySpace * lineTextInfo.simpleSpaceIndexes.length +
              maxStretchByAyaSpace * lineTextInfo.ayaSpaceIndexes.length;

      final stretch = (desiredWidth - currentLineWidth) < maxStretch
          ? (desiredWidth - currentLineWidth)
          : maxStretch;
      final spaceRatio = maxStretch != 0 ? stretch / maxStretch : 0.0;
      final stretchBySpace = spaceRatio * maxStretchBySpace;
      final stretchByAyaSpace = spaceRatio * maxStretchByAyaSpace;

      var simpleSpaceWidth = spaceWidth + stretchBySpace;
      var ayaSpaceWidth = spaceWidth + stretchByAyaSpace;

      currentLineWidth += stretch;

      if (desiredWidth > currentLineWidth) {
        final justInfo = JustInfo(
          textLineWidth: currentLineWidth,
          fontFeatures: <int, List<TextFontFeatures>>{},
          layoutResults: layOutResult,
          desiredWidth: desiredWidth,
          shaper: shaper,
          lineFeatures: lineFeatures,
        );
        justResults = _stretchLine(lineTextInfo, justInfo, mushafType);
        currentLineWidth = justResults.textLineWidth;
      }

      if (desiredWidth > currentLineWidth) {
        final addToSpace =
            (desiredWidth - currentLineWidth) / lineTextInfo.spaces.length;
        simpleSpaceWidth += addToSpace;
        ayaSpaceWidth += addToSpace;
      }

      simpleSpacing = simpleSpaceWidth;
      ayaSpacing = ayaSpaceWidth;
    }
  } else {
    xScale = desiredWidth / currentLineWidth;
  }

  return JustResultByLine(
    fontFeatures: justResults?.fontFeatures ?? <int, List<TextFontFeatures>>{},
    simpleSpacing: simpleSpacing,
    ayaSpacing: ayaSpacing,
    xScale: xScale,
  );
}
