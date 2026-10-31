/// [HbShaper] for the web, backed by the SAME `harfbuzz_shaper.cpp` compiled to
/// WebAssembly via Emscripten (see scripts/build_web.sh). Because it's the same
/// C code as the mobile FFI shaper, shaping behaviour is identical across all
/// platforms.
///
/// Build produces `web/hbq.js` + `web/hbq.wasm`. Add to web/index.html:
///   <script src="hbq.js"></script>
/// then: `final shaper = await WebShaper.load(fontBytes);`
///
/// NOTE: This file uses dart:js_interop and only compiles/loads on web. Do not
/// import it on mobile.
@JS()
library;

import 'dart:js_interop';
import 'dart:typed_data';

import '../justify/hb_shaper.dart';

/// The Emscripten MODULARIZE factory exposed by hbq.js.
@JS('createHbqModule')
external JSPromise<_HbqModule> _createHbqModule();

/// Emscripten module surface (functions exported with a leading underscore,
/// plus the getValue/setValue/writeArrayToMemory runtime helpers).
extension type _HbqModule(JSObject _) implements JSObject {
  @JS('_malloc')
  external int malloc(int size);
  @JS('_free')
  external void free(int ptr);
  @JS('_hbq_font_load_bytes')
  external int fontLoadBytes(int dataPtr, int len);
  @JS('_hbq_font_upem')
  external int fontUpem(int font);
  @JS('_hbq_font_metrics')
  external void fontMetricsRaw(int font, int ascPtr, int descPtr);
  @JS('_hbq_font_has_tatweel')
  external int fontHasTatweel(int font);
  @JS('_hbq_font_set_tatweel')
  external void fontSetTatweel(int font, double value);
  @JS('_hbq_shape')
  external int shapeRaw(int font, int textPtr, int len, int featPtr, int nfeat);
  @JS('_hbq_free_shape')
  external void freeShape(int res);
  @JS('_hbq_glyph_outline')
  external int glyphOutlineRaw(int font, int gid);
  @JS('_hbq_free_outline')
  external void freeOutline(int res);

  // Returns a JS number; integer types come back integer-valued (use toInt()).
  external double getValue(int ptr, String type);
  external void setValue(int ptr, int value, String type);
  external void writeArrayToMemory(JSUint8Array array, int ptr);
}

class WebShaper extends HbShaper {
  final _HbqModule _m;
  final int _font;
  final int _upem;
  final bool _hasTatweel;
  double _tatweel = 0;

  final Map<int, List<OutlineCommand>> _outlineCache = {};

  WebShaper._(this._m, this._font, this._upem, this._hasTatweel);

  static Future<WebShaper> load(Uint8List bytes) async {
    final m = await _createHbqModule().toDart;
    final fontPtr = m.malloc(bytes.length);
    m.writeArrayToMemory(bytes.toJS, fontPtr);
    final font = m.fontLoadBytes(fontPtr, bytes.length);
    m.free(fontPtr);
    if (font == 0) {
      throw StateError('Failed to load font from ${bytes.length} bytes (web)');
    }
    return WebShaper._(m, font, m.fontUpem(font), m.fontHasTatweel(font) != 0);
  }

  @override
  int get unitsPerEm => _upem;

  @override
  bool get hasTatweel => _hasTatweel;

  @override
  void setTatweel(double value) {
    if (!_hasTatweel || value == _tatweel) return;
    _tatweel = value;
    _m.fontSetTatweel(_font, value);
    // Outlines now depend on the axis value, so the cache is stale.
    _outlineCache.clear();
  }

  @override
  ({int ascender, int descender}) get fontMetrics {
    final asc = _m.malloc(4);
    final desc = _m.malloc(4);
    _m.fontMetricsRaw(_font, asc, desc);
    final result = (
      ascender: _m.getValue(asc, 'i32').toInt(),
      descender: _m.getValue(desc, 'i32').toInt(),
    );
    _m.free(asc);
    _m.free(desc);
    return result;
  }

  @override
  List<HbGlyph> shape(String text, List<HbFeature> features) {
    final units = text.codeUnits;
    final textPtr = _m.malloc((units.isEmpty ? 1 : units.length) * 2);
    for (var i = 0; i < units.length; i++) {
      _m.setValue(textPtr + i * 2, units[i], 'i16');
    }

    final featPtr = _m.malloc((features.isEmpty ? 1 : features.length) * 16);
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final base = featPtr + i * 16;
      for (var j = 0; j < 4; j++) {
        _m.setValue(
            base + j, j < f.tag.length ? f.tag.codeUnitAt(j) : 0x20, 'i8');
      }
      _m.setValue(base + 4, f.value, 'i32');
      _m.setValue(base + 8, f.start < 0 ? 0 : f.start, 'i32');
      _m.setValue(base + 12, f.end < 0 ? 0xFFFFFFFF : f.end, 'i32');
    }

    final res =
        _m.shapeRaw(_font, textPtr, units.length, featPtr, features.length);
    final out = <HbGlyph>[];
    if (res != 0) {
      final glyphsPtr = _m.getValue(res, 'i32').toInt();
      final count = _m.getValue(res + 4, 'i32').toInt();
      for (var i = 0; i < count; i++) {
        final g = glyphsPtr + i * 24; // sizeof(HBQGlyph)
        out.add(HbGlyph(
          _m.getValue(g, 'i32').toInt(),
          _m.getValue(g + 4, 'i32').toInt(),
          _m.getValue(g + 8, 'float').round(),
          _m.getValue(g + 12, 'float').round(),
          _m.getValue(g + 16, 'float').round(),
          _m.getValue(g + 20, 'float').round(),
        ));
      }
      _m.freeShape(res);
    }

    _m.free(textPtr);
    _m.free(featPtr);
    return out;
  }

  @override
  List<OutlineCommand> glyphOutline(int glyphId) {
    final cached = _outlineCache[glyphId];
    if (cached != null) return cached;
    final res = _m.glyphOutlineRaw(_font, glyphId);
    final out = <OutlineCommand>[];
    if (res != 0) {
      final cmdsPtr = _m.getValue(res, 'i32').toInt();
      final count = _m.getValue(res + 4, 'i32').toInt();
      for (var i = 0; i < count; i++) {
        final c = cmdsPtr + i * 28; // sizeof(PathCommand)
        out.add(OutlineCommand(
          _m.getValue(c, 'i32').toInt(),
          _m.getValue(c + 4, 'float'),
          _m.getValue(c + 8, 'float'),
          _m.getValue(c + 12, 'float'),
          _m.getValue(c + 16, 'float'),
          _m.getValue(c + 20, 'float'),
          _m.getValue(c + 24, 'float'),
        ));
      }
      _m.freeOutline(res);
    }
    _outlineCache[glyphId] = out;
    return out;
  }
}
