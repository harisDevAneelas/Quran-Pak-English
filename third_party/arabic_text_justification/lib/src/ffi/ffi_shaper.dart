/// [HbShaper] implementation backed by the native standard-shaping wrapper via
/// dart:ffi. Used on Android and iOS (and on desktop in tests).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import '../justify/hb_shaper.dart';
import 'shaper_bindings.dart';

class FfiShaper extends HbShaper {
  final HbqBindings _b;
  final Pointer<HBQFont> _font;
  final int _upem;
  final bool _hasTatweel;
  double _tatweel = 0;
  bool _disposed = false;

  final Map<int, List<OutlineCommand>> _outlineCache = {};

  FfiShaper._(this._b, this._font, this._upem)
      : _hasTatweel = (_b.fontHasTatweel?.call(_font) ?? 0) != 0 &&
            _b.fontSetTatweel != null;

  /// Open the native library and load [fontPath].
  ///
  /// [library] / [libraryPath] override how the native library is resolved
  /// (tests pass the locally-built .dylib). When omitted, the package's bundled
  /// FFI library is used per platform convention.
  factory FfiShaper.load(
    String fontPath, {
    DynamicLibrary? library,
    String? libraryPath,
  }) {
    final lib = library ?? _openLibrary(libraryPath);
    final b = HbqBindings(lib);

    final pathPtr = fontPath.toNativeUtf8();
    final font = b.fontLoad(pathPtr);
    calloc.free(pathPtr);

    if (font == nullptr) {
      throw StateError('Failed to load font: $fontPath');
    }
    final upem = b.fontUpem(font);
    return FfiShaper._(b, font, upem);
  }

  /// Load a font from in-memory [bytes] (e.g. a Flutter asset via rootBundle).
  factory FfiShaper.loadBytes(
    Uint8List bytes, {
    DynamicLibrary? library,
    String? libraryPath,
  }) {
    final lib = library ?? _openLibrary(libraryPath);
    final b = HbqBindings(lib);

    final ptr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    final font = b.fontLoadBytes(ptr, bytes.length);
    calloc.free(ptr);

    if (font == nullptr) {
      throw StateError('Failed to load font from ${bytes.length} bytes');
    }
    final upem = b.fontUpem(font);
    return FfiShaper._(b, font, upem);
  }

  static DynamicLibrary _openLibrary(String? libraryPath) {
    if (libraryPath != null) return DynamicLibrary.open(libraryPath);
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libarabic_text_justification.so');
    }
    // iOS/macOS statically link into the process.
    return DynamicLibrary.process();
  }

  @override
  int get unitsPerEm => _upem;

  @override
  bool get hasTatweel => _hasTatweel;

  @override
  void setTatweel(double value) {
    if (!_hasTatweel || value == _tatweel) return;
    _tatweel = value;
    _b.fontSetTatweel!(_font, value);
    // Outlines now depend on the axis value, so the cache is stale.
    _outlineCache.clear();
  }

  @override
  List<HbGlyph> shape(String text, List<HbFeature> features) {
    assert(!_disposed, 'FfiShaper used after dispose()');

    final units = text.codeUnits;
    final textPtr = calloc<Uint16>(units.isEmpty ? 1 : units.length);
    for (var i = 0; i < units.length; i++) {
      textPtr[i] = units[i];
    }

    final featPtr = calloc<HBQFeature>(features.isEmpty ? 1 : features.length);
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final ref = (featPtr + i).ref;
      for (var j = 0; j < 4; j++) {
        ref.tag[j] =
            j < f.tag.length ? f.tag.codeUnitAt(j) : 0x20; // pad with space
      }
      ref.value = f.value;
      ref.start = f.start < 0 ? 0 : f.start;
      ref.end = f.end < 0 ? 0xFFFFFFFF : f.end;
    }

    final res =
        _b.shape(_font, textPtr, units.length, featPtr, features.length);
    final result = <HbGlyph>[];
    if (res != nullptr) {
      final count = res.ref.glyphCount;
      final glyphs = res.ref.glyphs;
      for (var i = 0; i < count; i++) {
        final g = (glyphs + i).ref;
        result.add(HbGlyph(
          g.glyphId,
          g.cluster,
          g.xAdvance.round(),
          g.yAdvance.round(),
          g.xOffset.round(),
          g.yOffset.round(),
        ));
      }
      _b.freeShape(res);
    }

    calloc.free(textPtr);
    calloc.free(featPtr);
    return result;
  }

  @override
  ({int ascender, int descender}) get fontMetrics {
    final asc = calloc<Int32>();
    final desc = calloc<Int32>();
    _b.fontMetrics(_font, asc, desc);
    final result = (ascender: asc.value, descender: desc.value);
    calloc.free(asc);
    calloc.free(desc);
    return result;
  }

  @override
  List<OutlineCommand> glyphOutline(int glyphId) {
    assert(!_disposed, 'FfiShaper used after dispose()');
    final cached = _outlineCache[glyphId];
    if (cached != null) return cached;
    final res = _b.glyphOutline(_font, glyphId);
    final out = <OutlineCommand>[];
    if (res != nullptr) {
      final count = res.ref.commandCount;
      final cmds = res.ref.commands;
      for (var i = 0; i < count; i++) {
        final c = (cmds + i).ref;
        out.add(OutlineCommand(c.type, c.x, c.y, c.x1, c.y1, c.x2, c.y2));
      }
      _b.freeOutline(res);
    }
    _outlineCache[glyphId] = out;
    return out;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _b.fontDestroy(_font);
  }
}
