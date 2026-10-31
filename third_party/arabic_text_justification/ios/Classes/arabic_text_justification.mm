// Forwarder + symbol keepalive for the vendored XCFramework.
//
// The XCFramework ships a static library. Without a reference, the linker
// will dead-strip the FFI symbols and DynamicLibrary.process() won't find
// them at runtime. Keep them alive with __attribute__((used)).

#include "arabic_text_justification.h"

__attribute__((used)) static void* _atj_keepalive[] = {
    (void*)hbq_font_load,
    (void*)hbq_font_load_bytes,
    (void*)hbq_font_upem,
    (void*)hbq_font_metrics,
    (void*)hbq_font_destroy,
    (void*)hbq_shape,
    (void*)hbq_free_shape,
    (void*)hbq_glyph_outline,
    (void*)hbq_free_outline,
};
