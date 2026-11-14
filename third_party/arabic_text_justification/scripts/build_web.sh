#!/usr/bin/env bash

set -euo pipefail

if ! command -v emcc >/dev/null 2>&1; then
  echo "emcc not found. Install the Emscripten SDK and 'source emsdk_env.sh'." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HB="$ROOT/third_party/harfbuzz"
FT="$ROOT/third_party/freetype"
OUT="$ROOT/web"
mkdir -p "$OUT"

FT_SRCS=(
  "$FT/src/base/ftsystem.c" "$FT/src/base/ftinit.c" "$FT/src/base/ftdebug.c"
  "$FT/src/base/ftbase.c" "$FT/src/base/ftbbox.c" "$FT/src/base/ftbitmap.c"
  "$FT/src/base/ftglyph.c" "$FT/src/base/ftmm.c"
  "$FT/src/truetype/truetype.c" "$FT/src/cff/cff.c" "$FT/src/sfnt/sfnt.c"
  "$FT/src/smooth/smooth.c" "$FT/src/raster/raster.c"
  "$FT/src/psnames/psnames.c" "$FT/src/pshinter/pshinter.c"
  "$FT/src/psaux/psaux.c" "$FT/src/autofit/autofit.c"
  "$FT/src/gzip/ftgzip.c"
)

# em++ links the C++ standard library (required for newer Emscripten SDKs).
em++ -O3 \
  -DFT2_BUILD_LIBRARY=1 -DHB_NO_MT=1 \
  -DFT_CONFIG_MODULES_H='<web_ftmodule.h>' \
  -I "$ROOT/scripts" \
  -I "$HB/src" -I "$FT/include" \
  "$ROOT/src/harfbuzz_shaper.cpp" \
  "$HB/src/harfbuzz.cc" \
  "${FT_SRCS[@]}" \
  -s MODULARIZE=1 -s EXPORT_NAME=createHbqModule \
  -s ENVIRONMENT=web \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s EXPORTED_FUNCTIONS='["_malloc","_free","_hbq_font_load_bytes","_hbq_font_upem","_hbq_font_metrics","_hbq_font_has_tatweel","_hbq_font_set_tatweel","_hbq_shape","_hbq_free_shape","_hbq_glyph_outline","_hbq_free_outline"]' \
  -s EXPORTED_RUNTIME_METHODS='["getValue","setValue","writeArrayToMemory"]' \
  -o "$OUT/hbq.js"

echo "Built $OUT/hbq.js + $OUT/hbq.wasm"
