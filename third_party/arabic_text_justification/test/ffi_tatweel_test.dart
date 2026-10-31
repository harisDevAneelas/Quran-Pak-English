@TestOn('mac-os')
library;

import 'dart:io';

import 'package:arabic_text_justification/src/ffi/ffi_shaper.dart';
import 'package:arabic_text_justification/src/justify/hb_shaper.dart';
import 'package:arabic_text_justification/src/justify/prepared_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// Validates the variable-font tatweel (LTAT/RTAT) path that justifies
/// digitalkhatt.otf. Requires the locally-built test dylib:
///   scripts/build_macos_test.sh -> .build/macos/libhbq_shaper.dylib
void main() {
  final root = Directory.current.path;
  final dylib = '$root/.build/macos/libhbq_shaper.dylib';
  final digitalkhatt = '$root/test/fixtures/digitalkhatt.otf';
  final madina = '$root/test/fixtures/madina.otf';

  setUpAll(() {
    if (!File(dylib).existsSync()) {
      throw StateError('Missing $dylib — run scripts/build_macos_test.sh');
    }
  });

  test('digitalkhatt exposes tatweel axes; madina does not', () {
    final dk = FfiShaper.load(digitalkhatt, libraryPath: dylib);
    addTearDown(dk.dispose);
    final md = FfiShaper.load(madina, libraryPath: dylib);
    addTearDown(md.dispose);

    expect(dk.hasTatweel, isTrue, reason: 'digitalkhatt is a variable font');
    expect(md.hasTatweel, isFalse, reason: 'madina is a static cvXX font');
  });

  test('setTatweel widens / narrows the shaped line', () {
    final dk = FfiShaper.load(digitalkhatt, libraryPath: dylib);
    addTearDown(dk.dispose);

    const line = 'الحمد لله رب العالمين';
    dk.setTatweel(0);
    final natural = dk.measure(line, const []);
    dk.setTatweel(20);
    final stretched = dk.measure(line, const []);
    dk.setTatweel(-20);
    final compressed = dk.measure(line, const []);

    expect(natural, greaterThan(0));
    expect(stretched, greaterThan(natural),
        reason: 'positive tatweel must elongate letters');
    expect(compressed, lessThan(natural),
        reason: 'negative tatweel must compress letters');
  });

  test(
      'setTatweel stretches glyph outlines (FreeType coords), not just advances',
      () {
    final dk = FfiShaper.load(digitalkhatt, libraryPath: dylib);
    addTearDown(dk.dispose);

    double maxX(List<OutlineCommand> cmds) {
      var m = double.negativeInfinity;
      for (final c in cmds) {
        if (c.x > m) m = c.x;
        if (c.x1 > m) m = c.x1;
        if (c.x2 > m) m = c.x2;
      }
      return m;
    }

    // Kashida elongates the connecting strokes of *some* glyphs in a line, not
    // every one (dots and isolated forms don't move). Assert that at least one
    // glyph's outline genuinely widens, proving FreeType applies the axis — if
    // only advances changed, letters would render with gaps.
    const line = 'الحمد لله رب العالمين';
    final glyphs = dk.shape(line, const []);

    dk.setTatweel(0);
    final natural = {
      for (final g in glyphs) g.glyphId: maxX(dk.glyphOutline(g.glyphId)),
    };
    dk.setTatweel(20);
    final widened = glyphs
        .where(
            (g) => maxX(dk.glyphOutline(g.glyphId)) > natural[g.glyphId]! + 0.5)
        .length;

    expect(widened, greaterThan(0),
        reason: 'outlines must stretch with the axis, matching advances');
  });

  test('prepareLine justifies a variable-font line to ~target via the axis',
      () {
    final dk = FfiShaper.load(digitalkhatt, libraryPath: dylib);
    addTearDown(dk.dispose);

    const words = ['الحمد', 'لله', 'رب', 'العالمين'];
    final natural = prepareLine(dk, words,
        nativeSize: 40, nativeWidth: 100000, justify: false);
    final target = natural.width * 1.15;
    final justified = prepareLine(dk, words,
        nativeSize: 40, nativeWidth: target, justify: true);

    // The binary search drove the LTAT/RTAT axis to widen the line toward the
    // target (ink width is a touch under the advance target, due to bearings).
    expect(justified.width, greaterThan(natural.width),
        reason: 'kashida should elongate the line');
    expect(justified.width, closeTo(target, target * 0.15));
  });
}
