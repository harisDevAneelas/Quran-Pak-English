#include "harfbuzz_shaper.h"
#include <hb.h>
#include <hb-ot.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include FT_MULTIPLE_MASTERS_H
#include <cstdlib>
#include <cstring>
#include <vector>

struct HBQFont {
    hb_blob_t*   blob;
    hb_face_t*   face;
    hb_font_t*   font;
    unsigned int upem;
    FT_Library   ft_lib;
    FT_Face      ft_face;      // may be NULL if FreeType init failed
    void*        owned_bytes;  // non-NULL when loaded from memory (we free it)

    // Variation-axis info for tatweel kashida (digitalkhatt.otf). Populated in
    // finish_font from the FreeType MM/var table. ltat_idx/rtat_idx are the FT
    // axis indices of the LTAT/RTAT axes (-1 when absent); axis_default holds
    // every axis's default design coord so we only move the tatweel axes.
    int          n_axes = 0;
    int          ltat_idx = -1;
    int          rtat_idx = -1;
    FT_Fixed     axis_default[16] = {0};
};

// Finish initialising an HBQFont once its blob exists. `owned_bytes`/`bytes_len`
// are non-NULL only for the from-memory path (so FreeType can use the buffer
// and we can free it on destroy).
static HBQFont* finish_font(hb_blob_t* blob, void* owned_bytes,
                            const FT_Byte* ft_base, FT_Long ft_len,
                            const char* ft_path) {
    if (!blob || hb_blob_get_length(blob) == 0) {
        if (blob) hb_blob_destroy(blob);
        if (owned_bytes) free(owned_bytes);
        return nullptr;
    }
    hb_face_t* face = hb_face_create(blob, 0);
    hb_font_t* font = hb_font_create(face);
    unsigned int upem = hb_face_get_upem(face);
    // scale == upem → advances/positions come back in raw font units.
    hb_font_set_scale(font, (int)upem, (int)upem);
    hb_ot_font_set_funcs(font);

    HBQFont* f = new HBQFont{blob, face, font, upem, nullptr, nullptr, owned_bytes};

    if (FT_Init_FreeType(&f->ft_lib) == 0) {
        FT_Error err = ft_path
            ? FT_New_Face(f->ft_lib, ft_path, 0, &f->ft_face)
            : FT_New_Memory_Face(f->ft_lib, ft_base, ft_len, 0, &f->ft_face);
        if (err != 0) f->ft_face = nullptr;
    }

    // Discover the tatweel variation axes (LTAT/RTAT) if this is a variable
    // font, so hbq_font_set_tatweel can drive them for kashida.
    if (f->ft_face) {
        FT_MM_Var* mm = nullptr;
        if (FT_Get_MM_Var(f->ft_face, &mm) == 0 && mm) {
            f->n_axes = (int)mm->num_axis;
            for (FT_UInt i = 0; i < mm->num_axis && i < 16; i++) {
                f->axis_default[i] = mm->axis[i].def;
                if (mm->axis[i].tag == FT_MAKE_TAG('L', 'T', 'A', 'T')) f->ltat_idx = (int)i;
                if (mm->axis[i].tag == FT_MAKE_TAG('R', 'T', 'A', 'T')) f->rtat_idx = (int)i;
            }
            FT_Done_MM_Var(f->ft_lib, mm);
        }
    }
    return f;
}

extern "C" {

HBQFont* hbq_font_load(const char* font_path) {
    hb_blob_t* blob = hb_blob_create_from_file(font_path);
    return finish_font(blob, nullptr, nullptr, 0, font_path);
}

HBQFont* hbq_font_load_bytes(const uint8_t* data, int length) {
    if (!data || length <= 0) return nullptr;
    // Copy so HarfBuzz and FreeType can keep using the buffer after the caller
    // frees theirs.
    void* copy = malloc((size_t)length);
    if (!copy) return nullptr;
    memcpy(copy, data, (size_t)length);
    hb_blob_t* blob = hb_blob_create((const char*)copy, (unsigned)length,
                                     HB_MEMORY_MODE_READONLY, nullptr, nullptr);
    return finish_font(blob, copy, (const FT_Byte*)copy, (FT_Long)length, nullptr);
}

int hbq_font_upem(HBQFont* font) {
    return font ? (int)font->upem : 0;
}

void hbq_font_metrics(HBQFont* font, int* ascender, int* descender) {
    if (!font) { if (ascender) *ascender = 0; if (descender) *descender = 0; return; }
    hb_font_extents_t e;
    hb_font_get_h_extents(font->font, &e);
    if (ascender) *ascender = e.ascender;   // font units (scale == upem)
    if (descender) *descender = e.descender; // negative
}

void hbq_font_destroy(HBQFont* font) {
    if (!font) return;
    if (font->ft_face) FT_Done_Face(font->ft_face);
    if (font->ft_lib) FT_Done_FreeType(font->ft_lib);
    hb_font_destroy(font->font);
    hb_face_destroy(font->face);
    hb_blob_destroy(font->blob);
    if (font->owned_bytes) free(font->owned_bytes);
    delete font;
}

int hbq_font_has_tatweel(HBQFont* font) {
    return (font && (font->ltat_idx >= 0 || font->rtat_idx >= 0)) ? 1 : 0;
}

void hbq_font_set_tatweel(HBQFont* font, float value) {
    if (!font) return;

    hb_variation_t v[2] = {
        { HB_TAG('L', 'T', 'A', 'T'), value },
        { HB_TAG('R', 'T', 'A', 'T'), value },
    };
    hb_font_set_variations(font->font, v, 2);

    if (font->ft_face && font->n_axes > 0) {
        FT_Fixed coords[16];
        int n = font->n_axes < 16 ? font->n_axes : 16;
        for (int i = 0; i < n; i++) coords[i] = font->axis_default[i];
        const FT_Fixed fixed = (FT_Fixed)(value * 65536.0f);
        if (font->ltat_idx >= 0 && font->ltat_idx < n) coords[font->ltat_idx] = fixed;
        if (font->rtat_idx >= 0 && font->rtat_idx < n) coords[font->rtat_idx] = fixed;
        FT_Set_Var_Design_Coordinates(font->ft_face, (FT_UInt)n, coords);
    }
}

HBQShapeResult* hbq_shape(
        HBQFont*          font,
        const uint16_t*   text,
        int               text_len,
        const HBQFeature* features,
        int               feature_count) {
    if (!font) return nullptr;

    hb_buffer_t* buf = hb_buffer_create();
    hb_buffer_add_utf16(buf, text, text_len, 0, text_len);
    hb_buffer_set_direction(buf, HB_DIRECTION_RTL);
    hb_buffer_set_script(buf, HB_SCRIPT_ARABIC);
    hb_buffer_set_language(buf, hb_language_from_string("ar", -1));
    hb_buffer_set_cluster_level(buf, HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS);

    std::vector<hb_feature_t> hf;
    hf.reserve(feature_count);
    for (int i = 0; i < feature_count; i++) {
        hb_feature_t feat;
        feat.tag = HB_TAG(features[i].tag[0], features[i].tag[1],
                          features[i].tag[2], features[i].tag[3]);
        feat.value = features[i].value;
        feat.start = features[i].start;
        feat.end   = features[i].end; // 0xFFFFFFFF == HB_FEATURE_GLOBAL_END
        hf.push_back(feat);
    }

    hb_shape(font->font, buf, feature_count ? hf.data() : nullptr, feature_count);

    unsigned int gc = 0;
    hb_glyph_info_t*     infos = hb_buffer_get_glyph_infos(buf, &gc);
    hb_glyph_position_t* poses = hb_buffer_get_glyph_positions(buf, &gc);

    HBQShapeResult* r = (HBQShapeResult*)malloc(sizeof(HBQShapeResult));
    r->glyph_count = (int)gc;
    r->glyphs = (HBQGlyph*)malloc(sizeof(HBQGlyph) * (gc ? gc : 1));
    for (unsigned int i = 0; i < gc; i++) {
        r->glyphs[i].glyph_id  = (int)infos[i].codepoint;
        r->glyphs[i].cluster   = (int)infos[i].cluster;
        r->glyphs[i].x_advance = (float)poses[i].x_advance;
        r->glyphs[i].y_advance = (float)poses[i].y_advance;
        r->glyphs[i].x_offset  = (float)poses[i].x_offset;
        r->glyphs[i].y_offset  = (float)poses[i].y_offset;
    }

    hb_buffer_destroy(buf);
    return r;
}

void hbq_free_shape(HBQShapeResult* result) {
    if (result) {
        free(result->glyphs);
        free(result);
    }
}

// --- Outline extraction (font units) ---
//
// DigitalKhattV2 is CFF2. FreeType's FT_LOAD_NO_SCALE path is unreliable for
// CFF/CFF2 (mark glyphs / GPOS attachment look detached on web). Load at UPEM
// without NO_SCALE and convert 26.6 fixed → font units (/64).

namespace {
struct OutlineData {
    std::vector<PathCommand> commands;
    float scale; // 1 for FT_LOAD_NO_SCALE; 1/64 when loaded at UPEM char size
};

static float _ou(OutlineData* d, FT_Pos v) { return (float)v * d->scale; }

int move_to(const FT_Vector* to, void* user) {
    auto* d = (OutlineData*)user;
    PathCommand c = {};
    c.type = PATH_MOVE_TO;
    c.x = _ou(d, to->x); c.y = _ou(d, to->y);
    d->commands.push_back(c);
    return 0;
}
int line_to(const FT_Vector* to, void* user) {
    auto* d = (OutlineData*)user;
    PathCommand c = {};
    c.type = PATH_LINE_TO;
    c.x = _ou(d, to->x); c.y = _ou(d, to->y);
    d->commands.push_back(c);
    return 0;
}
int conic_to(const FT_Vector* ctrl, const FT_Vector* to, void* user) {
    auto* d = (OutlineData*)user;
    PathCommand c = {};
    c.type = PATH_QUAD_TO;
    c.x1 = _ou(d, ctrl->x); c.y1 = _ou(d, ctrl->y);
    c.x = _ou(d, to->x); c.y = _ou(d, to->y);
    d->commands.push_back(c);
    return 0;
}
int cubic_to(const FT_Vector* c1, const FT_Vector* c2, const FT_Vector* to, void* user) {
    auto* d = (OutlineData*)user;
    PathCommand c = {};
    c.type = PATH_CUBIC_TO;
    c.x1 = _ou(d, c1->x); c.y1 = _ou(d, c1->y);
    c.x2 = _ou(d, c2->x); c.y2 = _ou(d, c2->y);
    c.x = _ou(d, to->x); c.y = _ou(d, to->y);
    d->commands.push_back(c);
    return 0;
}
} // namespace

HBQOutline* hbq_glyph_outline(HBQFont* font, int glyph_id) {
    if (!font || !font->ft_face) return nullptr;

    HBQOutline* r = (HBQOutline*)malloc(sizeof(HBQOutline));
    r->commands = nullptr;
    r->command_count = 0;

    // Prefer UPEM-sized load (works for TTF and CFF2). Fall back to NO_SCALE.
    float outline_scale = 1.0f / 64.0f;
    FT_Error err = FT_Set_Char_Size(
        font->ft_face, 0, (FT_F26Dot6)(font->upem * 64), 72, 72);
    if (err == 0) {
        err = FT_Load_Glyph(font->ft_face, (FT_UInt)glyph_id,
                            FT_LOAD_NO_BITMAP | FT_LOAD_NO_HINTING);
    }
    if (err != 0 ||
        font->ft_face->glyph->format != FT_GLYPH_FORMAT_OUTLINE) {
        outline_scale = 1.0f;
        if (FT_Load_Glyph(font->ft_face, (FT_UInt)glyph_id,
                          FT_LOAD_NO_SCALE | FT_LOAD_NO_BITMAP) != 0 ||
            font->ft_face->glyph->format != FT_GLYPH_FORMAT_OUTLINE) {
            return r;
        }
    }

    FT_Outline_Funcs funcs = {};
    funcs.move_to = move_to;
    funcs.line_to = line_to;
    funcs.conic_to = conic_to;
    funcs.cubic_to = cubic_to;

    OutlineData data;
    data.scale = outline_scale;
    FT_Outline_Decompose(&font->ft_face->glyph->outline, &funcs, &data);

    int n = (int)data.commands.size();
    r->command_count = n;
    if (n > 0) {
        r->commands = (PathCommand*)malloc(sizeof(PathCommand) * n);
        for (int i = 0; i < n; i++) r->commands[i] = data.commands[i];
    }
    return r;
}

void hbq_free_outline(HBQOutline* result) {
    if (result) {
        free(result->commands);
        free(result);
    }
}

} // extern "C"
