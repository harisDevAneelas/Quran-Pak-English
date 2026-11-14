#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/macos"
mkdir -p "$OUT"

clang++ -std=c++17 -dynamiclib -fvisibility=hidden -O2 \
  $(pkg-config --cflags harfbuzz freetype2) \
  "$ROOT/src/harfbuzz_shaper.cpp" \
  $(pkg-config --libs harfbuzz freetype2) \
  -o "$OUT/libhbq_shaper.dylib"

echo "Built $OUT/libhbq_shaper.dylib"
