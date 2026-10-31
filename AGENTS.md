# Quran reader

Flutter app. Urdu UI. One continuous mushaf, Tajweed coloring, translations, ayah audio, and local profiles.

## Layout

- `lib/main.dart` keeps the native splash up and opens the SQLite factory, then runs `QuranApp`.
- `lib/app.dart` boots profiles, reader settings, the mushaf, fonts, and metadata, then shows `QuranReaderScreen`.
- `lib/core` — theme, named UI sizes (`app_dimens.dart`), KFGQPC font contract, stable mushaf list indices, per-surah ayah counts.
- `lib/data` — colored JSON, metadata, SQLite, Tajweed parse, translations, word-by-word, reciters, verse collections.
- `lib/reader` — reader screen, controller, audio, sidebar, bookmarks, daily plan, profiles.
- `lib/quran/rendering` — KFGQPC font path for the justification shaper.
- `assets/data/quran.colored.json` — Arabic words and Tajweed highlight ranges.
- `assets/data/quran.metadata.json` — manzil, sajda, bismillah words.
- `assets/data/english_db.sqlite` — English translation columns, `Quran.words`, `Sura`, `Juz`, `QuraniDua`, and per-ayah page, ruku, and para columns. `assets/data/database.sqlite` is only the source for `tool/prepare_english_db.py`.
- `third_party/arabic_text_justification` — local package. The web loader is patched so it can load KFGQPC by file path.
- `tool/` — offline scripts. They are not on the reader path.
- `tools/quran_indopak_words.json` — IndoPak word list for the offline WBW repair script.

## Before changing code

- Principles: `docs/constitution.md`
- How a current area works: `docs/features.md`
- A change in progress: `specs/` (`specs/README.md`)

Read the feature block, then the constitution, before editing that area. A new behavior gets `spec.md`, then `plan.md`, then `tasks.md`, before Dart changes.
