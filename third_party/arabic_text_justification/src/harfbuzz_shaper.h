#ifndef HARFBUZZ_SHAPER_H
#define HARFBUZZ_SHAPER_H

// Standard-shaping HarfBuzz wrapper for the Dart justification engine.
//
// Unlike harfbuzz_wrapper.cpp (which justifies inside native code via the
// LTAT/RTAT tatweel axis), this wrapper does *plain* shaping only: it shapes a
// UTF-16 run with arbitrary OpenType features and returns glyphs in font units.
// All kashida logic lives in Dart (lib/src/justify/engine.dart); the cvXX
// features it produces are ordinary GSUB features, so stock HarfBuzz suffices.
//
// The font (blob/face/font + a FreeType face for outlines) is loaded once and
// reused across the many shape() calls a single line of justification makes.

#include <stdint.h>
#include "harfbuzz_wrapper.h" // reuse PathCommand / PATH_* definitions

#define HBQ_EXPORT __attribute__((visibility("default")))

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HBQFont HBQFont;

typedef struct {
    char     tag[4];  // OpenType feature tag, e.g. {'c','v','0','1'}
    uint32_t value;
    uint32_t start;   // cluster start (UTF-16 code-unit offset)
    uint32_t end;     // cluster end (exclusive); 0xFFFFFFFF == whole run
} HBQFeature;

typedef struct {
    int   glyph_id;
    int   cluster;
    float x_advance;  // font units
    float y_advance;
    float x_offset;
    float y_offset;
} HBQGlyph;

typedef struct {
    HBQGlyph* glyphs;
    int       glyph_count;
} HBQShapeResult;

typedef struct {
    PathCommand* commands;  // in font units
    int          command_count;
} HBQOutline;

// Load a font from disk. Returns NULL on failure. Caller owns it and must call
// hbq_font_destroy.
HBQ_EXPORT HBQFont* hbq_font_load(const char* font_path);

// Horizontal font extents in font units: *ascender (up, positive),
// *descender (down, negative) — for uniform line height.
HBQ_EXPORT void hbq_font_metrics(HBQFont* font, int* ascender, int* descender);

// Load a font from an in-memory buffer (used on web, where there is no
// filesystem). The bytes are copied; the caller may free `data` afterwards.
HBQ_EXPORT HBQFont* hbq_font_load_bytes(const uint8_t* data, int length);
HBQ_EXPORT int      hbq_font_upem(HBQFont* font);
HBQ_EXPORT void     hbq_font_destroy(HBQFont* font);

HBQ_EXPORT int  hbq_font_has_tatweel(HBQFont* font);
HBQ_EXPORT void hbq_font_set_tatweel(HBQFont* font, float value);

// Shape `text` (UTF-16, `text_len` code units) with `features`. RTL Arabic,
// cluster level 1 — matching the website's setup. Advances are in font units.
HBQ_EXPORT HBQShapeResult* hbq_shape(
        HBQFont*          font,
        const uint16_t*   text,
        int               text_len,
        const HBQFeature* features,
        int               feature_count);
HBQ_EXPORT void hbq_free_shape(HBQShapeResult* result);

// Outline of a single glyph id, in font units (unscaled). NULL on failure.
HBQ_EXPORT HBQOutline* hbq_glyph_outline(HBQFont* font, int glyph_id);
HBQ_EXPORT void hbq_free_outline(HBQOutline* result);

#ifdef __cplusplus
}
#endif

#endif
