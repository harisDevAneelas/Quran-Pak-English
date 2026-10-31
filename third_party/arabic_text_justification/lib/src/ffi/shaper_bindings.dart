/// dart:ffi bindings for the standard-shaping native wrapper (harfbuzz_shaper.h).
library;

import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Opaque native font handle (`HBQFont*`).
final class HBQFont extends Opaque {}

final class HBQFeature extends Struct {
  @Array(4)
  external Array<Uint8> tag;
  @Uint32()
  external int value;
  @Uint32()
  external int start;
  @Uint32()
  external int end;
}

final class HBQGlyph extends Struct {
  @Int32()
  external int glyphId;
  @Int32()
  external int cluster;
  @Float()
  external double xAdvance;
  @Float()
  external double yAdvance;
  @Float()
  external double xOffset;
  @Float()
  external double yOffset;
}

final class HBQShapeResult extends Struct {
  external Pointer<HBQGlyph> glyphs;
  @Int32()
  external int glyphCount;
}

final class HBQPathCommand extends Struct {
  @Int32()
  external int type;
  @Float()
  external double x;
  @Float()
  external double y;
  @Float()
  external double x1;
  @Float()
  external double y1;
  @Float()
  external double x2;
  @Float()
  external double y2;
}

final class HBQOutline extends Struct {
  external Pointer<HBQPathCommand> commands;
  @Int32()
  external int commandCount;
}

/// Thin resolver over the native symbols.
class HbqBindings {
  final Pointer<HBQFont> Function(Pointer<Utf8>) fontLoad;
  final Pointer<HBQFont> Function(Pointer<Uint8>, int) fontLoadBytes;
  final int Function(Pointer<HBQFont>) fontUpem;
  final void Function(Pointer<HBQFont>, Pointer<Int32>, Pointer<Int32>)
      fontMetrics;
  final void Function(Pointer<HBQFont>) fontDestroy;
  final Pointer<HBQShapeResult> Function(
      Pointer<HBQFont>, Pointer<Uint16>, int, Pointer<HBQFeature>, int) shape;
  final void Function(Pointer<HBQShapeResult>) freeShape;
  final Pointer<HBQOutline> Function(Pointer<HBQFont>, int) glyphOutline;
  final void Function(Pointer<HBQOutline>) freeOutline;

  // Variable-font tatweel API. Null when the loaded native library predates it
  // (older bundled binary) — callers fall back to feature justification.
  final int Function(Pointer<HBQFont>)? fontHasTatweel;
  final void Function(Pointer<HBQFont>, double)? fontSetTatweel;

  HbqBindings._({
    required this.fontLoad,
    required this.fontLoadBytes,
    required this.fontUpem,
    required this.fontMetrics,
    required this.fontDestroy,
    required this.shape,
    required this.freeShape,
    required this.glyphOutline,
    required this.freeOutline,
    this.fontHasTatweel,
    this.fontSetTatweel,
  });

  factory HbqBindings(DynamicLibrary lib) {
    // The tatweel symbols only exist in libraries rebuilt after the
    // variable-axis feature landed. Look them up defensively so older bundled
    // binaries keep working (the shaper then reports hasTatweel == false).
    int Function(Pointer<HBQFont>)? hasTatweel;
    void Function(Pointer<HBQFont>, double)? setTatweel;
    try {
      hasTatweel = lib.lookupFunction<Int32 Function(Pointer<HBQFont>),
          int Function(Pointer<HBQFont>)>('hbq_font_has_tatweel');
      setTatweel = lib.lookupFunction<Void Function(Pointer<HBQFont>, Float),
          void Function(Pointer<HBQFont>, double)>('hbq_font_set_tatweel');
    } on ArgumentError {
      hasTatweel = null;
      setTatweel = null;
    }

    return HbqBindings._(
      fontHasTatweel: hasTatweel,
      fontSetTatweel: setTatweel,
      fontLoad: lib.lookupFunction<Pointer<HBQFont> Function(Pointer<Utf8>),
          Pointer<HBQFont> Function(Pointer<Utf8>)>('hbq_font_load'),
      fontLoadBytes: lib.lookupFunction<
          Pointer<HBQFont> Function(Pointer<Uint8>, Int32),
          Pointer<HBQFont> Function(
              Pointer<Uint8>, int)>('hbq_font_load_bytes'),
      fontUpem: lib.lookupFunction<Int32 Function(Pointer<HBQFont>),
          int Function(Pointer<HBQFont>)>('hbq_font_upem'),
      fontMetrics: lib.lookupFunction<
          Void Function(Pointer<HBQFont>, Pointer<Int32>, Pointer<Int32>),
          void Function(Pointer<HBQFont>, Pointer<Int32>,
              Pointer<Int32>)>('hbq_font_metrics'),
      fontDestroy: lib.lookupFunction<Void Function(Pointer<HBQFont>),
          void Function(Pointer<HBQFont>)>('hbq_font_destroy'),
      shape: lib.lookupFunction<
          Pointer<HBQShapeResult> Function(Pointer<HBQFont>, Pointer<Uint16>,
              Int32, Pointer<HBQFeature>, Int32),
          Pointer<HBQShapeResult> Function(Pointer<HBQFont>, Pointer<Uint16>,
              int, Pointer<HBQFeature>, int)>('hbq_shape'),
      freeShape: lib.lookupFunction<Void Function(Pointer<HBQShapeResult>),
          void Function(Pointer<HBQShapeResult>)>('hbq_free_shape'),
      glyphOutline: lib.lookupFunction<
          Pointer<HBQOutline> Function(Pointer<HBQFont>, Int32),
          Pointer<HBQOutline> Function(
              Pointer<HBQFont>, int)>('hbq_glyph_outline'),
      freeOutline: lib.lookupFunction<Void Function(Pointer<HBQOutline>),
          void Function(Pointer<HBQOutline>)>('hbq_free_outline'),
    );
  }
}
