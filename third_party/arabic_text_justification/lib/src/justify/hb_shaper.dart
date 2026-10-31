/// Platform-agnostic HarfBuzz shaping contract used by the justification engine.
///
/// The justification engine ([justifyLine]) is pure Dart and runs identically on
/// Android, iOS and Web. The only thing that differs per platform is *how* a run
/// of text is shaped into glyphs — that is what this interface abstracts:
///
///   * mobile (Android/iOS): implemented via dart:ffi over a standard HarfBuzz
///     build (see `lib/src/ffi/`),
///   * web: implemented via `hb.wasm` and JS interop (see `lib/src/web/`).
///
/// Crucially this is *standard* shaping only — no justification branch. The
/// kashida logic lives entirely in Dart.
library;

/// A single OpenType feature scoped to a cluster range, mirroring HarfBuzz's
/// `hb_feature_t`. [start]/[end] are cluster indices; [end] == -1 means "to the
/// end of the buffer" (whole run).
class HbFeature {
  final String tag;
  final int value;
  final int start;
  final int end;

  const HbFeature({
    required this.tag,
    required this.value,
    required this.start,
    required this.end,
  });
}

/// One shaped glyph, mirroring the website's `GlyphInformation`. Advances and
/// offsets are in font units (unscaled).
class HbGlyph {
  final int glyphId;
  final int cluster;
  final int xAdvance;
  final int yAdvance;
  final int xOffset;
  final int yOffset;

  const HbGlyph(
    this.glyphId,
    this.cluster,
    this.xAdvance,
    this.yAdvance,
    this.xOffset,
    this.yOffset,
  );
}

/// A single decomposed glyph-outline command, in font units (y-up). [type]
/// matches the native PATH_* enum: 0=moveTo, 1=lineTo, 2=quadTo, 3=cubicTo.
class OutlineCommand {
  final int type;
  final double x, y, x1, y1, x2, y2;
  const OutlineCommand(
      this.type, this.x, this.y, this.x1, this.y1, this.x2, this.y2);
}

/// Abstraction over a single loaded font + HarfBuzz shaping engine.
abstract class HbShaper {
  /// Font units per em (UPEM). The DigitalKhatt fonts use 1000, which is why the
  /// engine measures against [kFontSize] == 1000 in font units (scale == 1).
  int get unitsPerEm;

  /// Shape an RTL Arabic [text] run with [features], returning glyphs in the
  /// order HarfBuzz produces them. Implementations must set direction=rtl,
  /// script=Arabic, language=Arabic and cluster level 1, matching the website's
  /// `getWordWidth`/`shape` setup.
  List<HbGlyph> shape(String text, List<HbFeature> features);

  /// Total advance width (sum of xAdvance, in font units) of [text] shaped with
  /// [features]. Equivalent to the website's `getWidth` at fontSize == UPEM.
  int measure(String text, List<HbFeature> features) {
    var total = 0;
    for (final g in shape(text, features)) {
      total += g.xAdvance;
    }
    return total;
  }

  /// Outline of [glyphId] in font units (y-up). Empty when the glyph has no
  /// outline (e.g. spaces) or is unavailable.
  List<OutlineCommand> glyphOutline(int glyphId);

  /// Whether this font's kashida is driven by variable tatweel axes
  /// rather than static `cvXX` glyph variants.
  /// When true the engine justifies by [setTatweel]; when false it uses the
  /// feature cascade. Static fonts (e.g. the baked madina.otf) return false.
  bool get hasTatweel => false;

  /// Set the tatweel axis value (design units, range ±20) for a variable font.
  /// Affects subsequent [shape]/[measure] advances and [glyphOutline] outlines,
  /// and persists until changed (pass 0 for the natural shape). No-op for
  /// static fonts. Implementations must invalidate any outline cache on change.
  void setTatweel(double value) {}

  /// Horizontal font metrics in font units: ascender (up, positive) and
  /// descender (down, negative). Used for a constant line height per font size.
  ({int ascender, int descender}) get fontMetrics;
}
