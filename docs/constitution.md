# Constitution

These are already true. A plan or a code change that breaks one of them is wrong.

## Mushaf text

- Paint mushaf Arabic with `KFGQPCNastaleeq` and an empty `fontFamilyFallback`. That includes the main reader and its headers. The justification shaper loads this file only (`lib/quran/rendering/kfgqpc_font_path.dart`), never Madinah or DigitalKhatt.
- Word-by-word Arabic uses `AlQuranIndoPak` (`QuranFont.wordByWordFamily`) with an empty `fontFamilyFallback`. It does not use `KFGQPCNastaleeq`.
- Do not fall back to a system Arabic font.
- Keep line height at or above `QuranFont.recommendedLineHeight` (2.0). KFGQPC ink exceeds its declared ascent and descent, so parents must not clip it.
- The colored JSON stores plain Unicode words. Shaping happens at paint time. Do not reverse strings or invent ligatures.
- End-of-ayah markers are Arabic-Indic digits (U+0660–U+0669) only. Do not prefix U+06DD.

## Tajweed

- Color comes only from `highlights` in `quran.colored.json`, merged into word color ranges at parse time.
- Highlight `index` values are UTF-16 code units, half-open `[start, end)`. Do not convert them with grapheme clusters.
- Scroll and layout code maps those precomputed ranges to paint colors. It does not re-parse JSON, re-validate highlights, or guess colors from harakat.
- Turning Tajweed off in settings changes paint, not the parsed data.

## Numbering

- In this app, Surah 1 has 6 ayahs. Bismillah is a shared header, not Fatiha ayah 1. Counts live in `lib/core/surah_ayah_counts.dart`. `Sura.TotalAya` counts Fatiha bismillah, so that column is 7.
- `english_db.sqlite` and the audio CDN count bismillah as Fatiha ayah 1. Convert with `DbAyah`: app ayah N in surah 1 is DB/CDN ayah N+1. DB ayah 1 of surah 1 is not an app ayah.
- Surah 9 has no header bismillah.
- Surah and ayah jumps use stable `MushafLayout` list indices. Those indices do not change when the full JSON finishes loading.

## Content files

- Arabic and Tajweed on the main mushaf come from `assets/data/quran.colored.json` only. The reader does not load per-surah JSON slices.
- Translations, word-by-word glosses, surah names, surah introductions, and surah/juz display fields come from `assets/data/english_db.sqlite`. Hub verse lists (Ayaat-e-shifa, Forty Rabbana, Manzil, Ruqyah) come from `QuraniDua`. Those screens paint `DuaWords` (JSON words and Tajweed highlights copied at seed). `DuaText` is not read by the app. Page, ruku, and para boundaries come from `Quran.PageNum1`, `RukuStart`, `ParaStart`, and `ParaRubaStart`. Each surah's para and page come from `Sura`. Para list titles use `Juz.EngName`. `Juz.UrduName` is only the short Arabic opening used to count painted para-name words. The word-by-word screen reads `Quran.words` (`[arabic:english]`). An empty cell shows no word boxes. The database is opened read-only after a one-time copy to `quran_app_en_v1.sqlite`. After replacing the asset database, bump that copy name so existing installs recopy it.
- Do not hand-edit `quran.colored.json`, `quran.metadata.json`, or `english_db.sqlite` to fix a screen. Change the English database with `tool/prepare_english_db.py`, then verify the reader.
- `tool/split_quran_json.py` is offline. Do not wire it into the app.

## Dark UI text

- Body and list text on dark scaffolds use a light ink (`Theme` / `colorScheme.onSurface`). Do not hardcode `Colors.black`, `Colors.black54`, or other near-black colors for labels that appear on the dark reader background.

## Profiles and prefs

- Reading position, bookmarks, daily plan, and reader settings are stored per profile under `p:{profileId}:{base}` in SharedPreferences.
- Profile list and active id are global (`profiles_v1`, `active_profile_id`). The last profile cannot be deleted.
- Switching profiles saves the current settings, rebinds the stores, then loads the new profile. Do not write settings while `applyingProfile` is set or while a switch is in progress.
- Changing reader settings must not reparse the Quran JSON or reload fonts.

## Startup and audio

- Startup keeps `splash_screen.jpeg` full-screen until `QuranApp` bootstrap finishes (database, profiles, settings, font warm-up, metadata, and a small mushaf window around the opening position). Android 12+ OS splash can only be a color plus a circular icon, so Flutter paints that same JPEG after the first frame. The rest of `quran.colored.json` finishes loading in the background after the reader is shown.
- Ayah audio uses a new `AudioPlayer` per ayah. On web, reusing one player repeats the first file for later ayahs.
- Reciter and spoken-translation URLs are `https://qurancompany.com/quran/reciters/{id}/SSSAAA.mp3` and `.../languages/{id}/SSSAAA.mp3`. `SSS` and `AAA` are zero-padded surah and CDN ayah. Surah 1 ayah 1 plays `001001` then `001002`.
