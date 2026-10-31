export 'src/bundled_fonts.dart' show JustificationFont;
export 'src/models/word_color_span.dart';
export 'src/models/word_progress.dart';
export 'src/platform/shaper_loader.dart'
    show peekJustificationShaper, warmJustificationShaper;
export 'src/justify/measure_words.dart' show measureJustificationWordsWidth;
export 'src/justify/prepared_line_cache.dart'
    show PreparedLineCache, PreparedLineRequest, preparedLineCacheKey;
export 'src/widgets/justified_arabic_bitmap_line.dart';
export 'src/widgets/justified_arabic_block.dart';
export 'src/widgets/justified_arabic_line.dart';

// Engine type used by some widget params. (Web-safe — no dart:ffi here; import
// the platform shaper via `arabic_text_justification_ffi.dart` on mobile.)
export 'src/justify/types.dart' show MushafLayoutType;
