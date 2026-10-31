# quran_app

Flutter Quran reader. English UI, one continuous mushaf, Tajweed coloring, translations, ayah audio, and local profiles.

See `docs/features.md` for how each area works and `docs/constitution.md` for the rules a change must not break.

## Local data

`assets/data/english_db.sqlite` is required to run the app but is **not** in git (too large for GitHub). Place your local copy at that path before `flutter pub get` / `flutter run`. The Urdu `assets/data/database.sqlite` is only the source for `tool/prepare_english_db.py`.
