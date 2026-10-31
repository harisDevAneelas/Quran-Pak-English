@TestOn('mac-os')
library;

import 'dart:io';

import 'package:arabic_text_justification/src/ffi/ffi_shaper.dart';
import 'package:arabic_text_justification/src/justify/prepared_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// Validates the shared widget layout path (prepareLine) against the real font
/// via the native shaper. Requires .build/macos/libhbq_shaper.dylib.
void main() {
  final root = Directory.current.path;
  final dylib = '$root/.build/macos/libhbq_shaper.dylib';
  final fontPath = '$root/test/fixtures/madina.otf';

  late FfiShaper shaper;
  setUpAll(() => shaper = FfiShaper.load(fontPath, libraryPath: dylib));
  tearDownAll(() => shaper.dispose());

  const words = ['الحمد', 'لله', 'رب', 'العالمين'];

  test('prepareLine justifies a line to ~the target width', () {
    final p = prepareLine(shaper, words,
        nativeSize: 40, nativeWidth: 600, justify: true);

    expect(p.paths.length, greaterThan(5));
    expect(p.height, greaterThan(0));
    // Ink width close to the requested width (a touch under, due to bearings).
    expect(p.width, closeTo(600, 90));
    // One rect per word, several non-empty.
    expect(p.wordRects.length, words.length);
    expect(p.wordRects.where((r) => r.width > 0).length, greaterThan(1));
    // Per-glyph word indices stay in range.
    expect(p.pathWordIndices.every((w) => w >= 0 && w < words.length), isTrue);
  });

  test('prepareLine natural (no justify) returns intrinsic width', () {
    final p = prepareLine(shaper, words,
        nativeSize: 40, nativeWidth: 600, justify: false);
    expect(p.paths, isNotEmpty);
    expect(p.width, greaterThan(0));
  });
}
