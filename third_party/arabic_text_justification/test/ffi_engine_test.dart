@TestOn('mac-os')
library;

import 'dart:io';

import 'package:arabic_text_justification/src/ffi/ffi_shaper.dart';
import 'package:arabic_text_justification/src/justify/engine.dart';
import 'package:arabic_text_justification/src/justify/hb_shaper.dart';
import 'package:arabic_text_justification/src/justify/line_analyzer.dart';
import 'package:arabic_text_justification/src/justify/types.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end validation of the justification engine against the REAL
/// DigitalKhatt madina font, shaped through the native standard-shaping
/// wrapper (no justify branch). Requires the locally-built test dylib:
///   clang++ ... src/harfbuzz_shaper.cpp -> .build/macos/libhbq_shaper.dylib
void main() {
  final root = Directory.current.path;
  final dylib = '$root/.build/macos/libhbq_shaper.dylib';
  final fontPath = '$root/test/fixtures/madina.otf';

  late FfiShaper shaper;

  setUpAll(() {
    if (!File(dylib).existsSync()) {
      throw StateError('Missing $dylib — run scripts/build_macos_test.sh');
    }
    shaper = FfiShaper.load(fontPath, libraryPath: dylib);
  });
  tearDownAll(() => shaper.dispose());

  test('loads the font with a sane UPEM', () {
    expect(shaper.unitsPerEm, greaterThan(0));
  });

  test('loads an identical shaper from in-memory bytes (the web path)', () {
    final bytes = File(fontPath).readAsBytesSync();
    final fromBytes = FfiShaper.loadBytes(bytes, libraryPath: dylib);
    addTearDown(fromBytes.dispose);
    expect(fromBytes.unitsPerEm, shaper.unitsPerEm);
    // Same measurement as the path-loaded shaper.
    expect(fromBytes.measure('بسم', const []),
        equals(shaper.measure('بسم', const [])));
  });

  test('shapes Arabic text into glyphs with positive width', () {
    final glyphs = shaper.shape('بسم', const []);
    expect(glyphs, isNotEmpty);
    expect(shaper.measure('بسم', const []), greaterThan(0));
  });

  test('justifyLine fills the target width using real kashida features', () {
    const line = 'الحمد لله رب العالمين';
    final info = analyzeLineForJust(line);

    final natural = shaper.measure(line, const []).toDouble();
    final spaceWidth = shaper.measure(' ', const []).toDouble();
    expect(natural, greaterThan(0));

    // Ask for an 18% wider line — beyond what the (capped) space stretch alone
    // can provide, so the kashida feature passes must run.
    final desired = natural * 1.18;
    final ratio = kFontSize / desired;

    final result = justifyLine(info, shaper, ratio, spaceWidth,
        mushafType: MushafLayoutType.newMadinah);

    // Kashida features were actually applied (not just inter-word spacing).
    expect(result.fontFeatures, isNotEmpty,
        reason:
            'engine should apply cvXX kashida features for a large stretch');

    // Every word the engine chose to stretch must genuinely be wider with its
    // features than without — i.e. the real font responds to those features.
    var verifiedWider = 0;
    double total = 0;
    for (final w in info.wordInfos) {
      final feats = <HbFeature>[];
      for (var i = w.startIndex; i <= w.endIndex; i++) {
        for (final f in result.fontFeatures[i] ?? const <TextFontFeatures>[]) {
          feats.add(HbFeature(
            tag: f.name,
            value: f.value,
            start: i - w.startIndex,
            end: i - w.startIndex + 1,
          ));
        }
      }
      final wWidth = shaper.measure(w.text, feats);
      if (feats.isNotEmpty) {
        expect(wWidth, greaterThan(shaper.measure(w.text, const [])),
            reason: 'word "${w.text}" should be wider with applied features');
        verifiedWider++;
      }
      total += wWidth;
    }
    expect(verifiedWider, greaterThan(0));

    total += result.simpleSpacing * info.simpleSpaceIndexes.length;
    total += result.ayaSpacing * info.ayaSpaceIndexes.length;

    // The justified line reaches the requested width (final space distribution
    // is uncapped, so it should land essentially exactly on target).
    expect(total, closeTo(desired, desired * 0.02));
  });

  test('shrink path scales down an over-wide line', () {
    const line = 'الحمد لله رب العالمين';
    final info = analyzeLineForJust(line);
    final natural = shaper.measure(line, const []).toDouble();
    final spaceWidth = shaper.measure(' ', const []).toDouble();

    final desired = natural * 0.8;
    final result = justifyLine(info, shaper, kFontSize / desired, spaceWidth);
    expect(result.xScale, closeTo(0.8, 0.05));
  });
}
