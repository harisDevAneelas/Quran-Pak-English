# arabic_text_justification

A Flutter plugin for Arabic text rendering with kashida-based justification using [HarfBuzz](https://harfbuzz.github.io/) and [FreeType](https://freetype.org/).

Ships two line widgets plus a multi-line block for page-style layouts. Supports both **bitmap** and **vector outline** rendering.

Runs on **Android, iOS, and web** — the same C shaper is used via native FFI on mobile and compiled to **WebAssembly** on web, so shaping is identical everywhere. (Web needs one script tag — see [Web](#web).)

## Demo

<table>
  <tr>
    <td><img height="450" alt="Recording 1" src="https://github.com/user-attachments/assets/9dc766d5-63ae-4176-9e05-478b4ba57a1a" /></td>
    <td><img height="450" alt="Recording 2" src="https://github.com/user-attachments/assets/f245e9d1-5e4c-4943-a461-a17605b0b275" /></td>
  </tr>
  <tr>
    <td><img height="450" alt="Screenshot_20260418_102642" src="https://github.com/user-attachments/assets/893a31fb-e470-43b8-8e5f-347514b84324" /></td>
    <td><img height="450" alt="Screenshot_20260418_091940" src="https://github.com/user-attachments/assets/9eb7cd2d-5b7f-4b25-be75-fb130d214d77" /></td>
  </tr>
</table>

---

## How It Works

1. **Text shaping** — HarfBuzz applies Arabic letter forms, ligatures, and optional kashida justification.
2. **Glyph processing** — FreeType either rasterizes glyphs to a bitmap or extracts vector bezier outlines.
3. **Word mapping** — per-word bounding rectangles and glyph-to-word indices are returned for hit-testing and animation.

---

## Capabilities

### Two line widgets — outline or bitmap

Both widgets take the same parameters. Pick based on your needs:

- **`JustifiedArabicLine`** — vector outlines (bezier `Path`s). Scales cleanly, supports per-character tints via `colorSpans`, and is best for sweep-style animation.
- **`JustifiedArabicBitmapLine`** — rasterized line blit once per layout. Lightest paint cost for mostly-static text; still supports highlights, tap routing, and `WordProgress`.

```dart
JustifiedArabicBitmapLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'],
  fontSize: 24,
)
```

### Multi-line block — page-style layout

`JustifiedArabicBlock` composes N pre-split lines with a single shared font size, so every row renders at the same height even when word content differs. Useful for mushaf-style pages where line breaks are pre-assigned by the caller.

```dart
JustifiedArabicBlock(
  lines: [
    JustifiedArabicLineSpec(words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ']),
    JustifiedArabicLineSpec(words: ['ٱلرَّحْمَٰنِ', 'ٱلرَّحِيمِ']),
  ],
  lineSpacing: 4,
)
```

Per-line overrides (`color`, `highlightedWordIndices`, `colorSpans`, `wordProgress`, `alignment`, `justify`) go in `JustifiedArabicLineSpec`. Leave `fontSize` null to auto-fit — the block picks the size that fills a height-bounded slot, or that makes the widest natural line fill the available width when height is unbounded.

Two block-level options help when the reader can resize the text:

- **`preserveLineHeight: true`** — lock each row to the layout grid so changing `fontSize` only scales the glyphs (centered in their slot) and never moves the lines. Useful for keeping a mushaf's ruled lines fixed. Honored when the block has a bounded height and an explicit `fontSize`.
- **`staticMarker: true`** (with optional `markerFontSize`) — render words containing `marker` at a fixed size so ayah marks stay put while the body text resizes. When `markerFontSize` is null it falls back to the block's auto-fit size.

```dart
JustifiedArabicBlock(
  fontSize: fontSize,        // user-adjustable
  marker: '۝',
  staticMarker: true,        // ۝ markers keep a fixed size
  preserveLineHeight: true,  // lines stay on the grid as fontSize changes
  lines: lines,
)
```

### Bundled fonts

Two fonts ship with the package, selected via the `font` parameter (on the line, bitmap, and block widgets):

- **`JustificationFont.madinah`** (default) — kashida via static `cvNN` glyph variants.
- **`JustificationFont.digitalKhatt`** — kashida via the font's `LTAT`/`RTAT` variable-font tatweel axes.

Both elongate letters to fill the line; the engine picks the right strategy from the font automatically.

```dart
JustifiedArabicBlock(
  font: JustificationFont.digitalKhatt,
  lines: lines,
)
```

### Render a justified RTL line

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'],
  fontSize: 24,
)
```

Set `justify: false` for natural-width rendering without kashida expansion.

### Sizing — fixed, width-fit, or height-fit

Three mutually-exclusive modes:

```dart
JustifiedArabicLine(words: words, fontSize: 24)  // fixed
JustifiedArabicLine(words: words)                // auto-fit to width (fontSize: null)
JustifiedArabicLine(words: words, height: 48)    // auto-fit to height (fontSize ignored)
```

### Align within the available width

When `justify: false` the widget reports its intrinsic (tight) size so you position it with a parent. Pass `alignment` if you want the widget itself to fill the width and place the content inside.

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'],
  justify: false,
  alignment: Alignment.centerRight,
)
```

### Tap a word — or a marker

Pass a `marker` string. Words containing it fire `onMarkerTap` instead of `onWordTap`.

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ', '۝٢'],
  marker: '۝',
  onWordTap: (i, w) => print('word: $w'),
  onMarkerTap: (i, w) => print('verse end: $w'),
)
```

### Highlight words

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'],
  highlightedWordIndices: {1, 2}, // لِلَّهِ, رَبِّ
  highlightColor: Colors.blue.withOpacity(0.2),
)
```

### Color specific characters

`WordColorSpan` tints a character range inside a word (UTF-16 code-unit offsets). Useful for tajweed or any per-character coloring.

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'],
  colorSpans: [
    // color ح م د inside ٱلْحَمْدُ
    WordColorSpan(wordIndex: 0, start: 3, end: 6, color: Colors.red),
  ],
)
```

### Animate progress through words

`WordProgress` drives read-along / recitation animation. For any set of **passed** words + one **active** word, two independent effects apply — each opt-in:

- **Background highlight** via `passedHighlightColor` / `activeHighlightColor`
- **Glyph tint** via `passedColor` / `activeColor`

Two **animation styles** for the active word:

- **`.sweep`** — right-to-left partial fill driven by `activeProgress` (0..1). Good for continuous playback (audio-driven recitation).
- **`.whole`** — discrete on/off per word. Good for step-by-step advancement.

**Example 1 — read-along with background sweep**:

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'],
  wordProgress: WordProgress(
    passedWordIndices: {0, 1},
    passedHighlightColor: Colors.grey.withOpacity(0.25),
    activeWordIndex: 2,
    activeProgress: 0.6,
    activeHighlightColor: Colors.grey.withOpacity(0.55),
    style: WordProgressStyle.sweep,
  ),
)
```

**Example 2 — memorization / reveal with hidden words and glyph tints**:

`hiddenWordIndices` hides glyphs, highlights, and tap hits for the listed words. Pair with `marker` so ayah markers stay visible while the verse body is progressively revealed.

```dart
JustifiedArabicLine(
  words: ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ', '۝٢'],
  marker: '۝',
  wordProgress: WordProgress(
    passedWordIndices: {0, 1},
    passedColor: Colors.black,
    activeWordIndex: 2,
    activeColor: Colors.blue,
    hiddenWordIndices: {3}, // still to reveal
    style: WordProgressStyle.whole,
  ),
)
```

---

## Web

On web the shaper runs as WebAssembly. The package ships the prebuilt module at `web/hbq.js` + `web/hbq.wasm` (rebuild with `scripts/build_web.sh`. Two one-time steps in your app:

1. Copy `hbq.js` and `hbq.wasm` into your app's `web/` folder.
2. Load the module before Flutter boots, in `web/index.html`:

```html
<body>
  <script src="hbq.js"></script>
  <script src="flutter_bootstrap.js" async></script>
</body>
```

---

## Example

- [`example/`](https://github.com/kartikasw/arabic_text_justification/tree/master/example) — tabs cover the Widget (taps, line height, font size), Bitmap, timer-driven progress animation, the memorization / reveal mode, a regex-based tajweed demo, and a multi-line Block page. The menu icon opens a Mushaf page comparing block vs. line-by-line composition on the same slot.

---

## Acknowledgments

- [DigitalKhatt](https://digitalkhatt.org/) — Arabic justification and font technology
- [HarfBuzz](https://harfbuzz.github.io/) — Text shaping engine (justification branch by DigitalKhatt)
- [FreeType](https://freetype.org/) — Font rendering library

Portions of this software are copyright (c) 2023 The FreeType Project (https://freetype.org). All rights reserved.

See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for full license details.

---

## License

MIT — see [LICENSE](LICENSE) for details.
