import 'package:arabic_text_justification/src/justify/line_analyzer.dart';
import 'package:arabic_text_justification/src/justify/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('analyzeLineForJust', () {
    test('splits a line into space-delimited words', () {
      final info = analyzeLineForJust('بسم الله');
      // Two words plus the engine's bookkeeping: one WordInfo per word.
      expect(info.wordInfos.length, 2);
      expect(info.wordInfos[0].text, 'بسم');
      expect(info.wordInfos[1].text, 'الله');
    });

    test('records base letters and their in-word indexes', () {
      final info = analyzeLineForJust('بسم');
      final w = info.wordInfos.single;
      // All three letters are joining "base" letters.
      expect(w.baseText, 'بسم');
      expect(w.baseIndexes, [0, 1, 2]);
    });

    test('classifies a normal gap as a simple space', () {
      final info = analyzeLineForJust('بسم الله');
      expect(info.simpleSpaceIndexes, [3]);
      expect(info.ayaSpaceIndexes, isEmpty);
      expect(info.spaces[3], SpaceType.simple);
    });

    test('classifies a space before the aya mark as an aya space', () {
      // ...word + space + END OF AYAH (U+06DD)
      final info = analyzeLineForJust('الله ۝');
      expect(info.ayaSpaceIndexes, contains(4));
      expect(info.spaces[4], SpaceType.aya);
    });

    test('classifies a space after an arabic-indic digit as an aya space', () {
      // digit ٢ (U+0662) then space.
      final info = analyzeLineForJust('٢ الله');
      expect(info.ayaSpaceIndexes, contains(1));
      expect(info.spaces[1], SpaceType.aya);
    });

    test('starts a new sub-word after a right-no-join letter', () {
      // alif (ا) is right-no-join, so "با" yields two sub-words.
      final info = analyzeLineForJust('باب');
      final w = info.wordInfos.single;
      expect(w.subwords.length, greaterThanOrEqualTo(2));
    });

    test('applies the bism global feature when requested', () {
      final info = analyzeLineForJust('بسم', bism: true);
      expect(info.features, isNotNull);
      expect(info.features!.single.tag, 'bism');
    });
  });
}
