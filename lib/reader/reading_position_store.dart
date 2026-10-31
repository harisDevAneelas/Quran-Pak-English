import 'package:shared_preferences/shared_preferences.dart';

import 'profile_scoped_prefs.dart';

/// Last-seen reading position (`surah` + `ayah` only), scoped to a profile.
///
/// The reader debounces autosaves while scrolling (flush on scroll end), and
/// also supports an explicit manual save from the bottom bar.
class ReadingPositionStore {
  ReadingPositionStore({required String profileId}) : _profileId = profileId;

  static const _surahBase = 'manual_reading_position_surah';
  static const _ayahBase = 'manual_reading_position_ayah';

  String _profileId;

  String get profileId => _profileId;

  void bind(String profileId) {
    _profileId = profileId;
  }

  String get _surahKey => ProfileScopedPrefs.key(_profileId, _surahBase);
  String get _ayahKey => ProfileScopedPrefs.key(_profileId, _ayahBase);

  Future<void> save({required int surah, required int ayah}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_surahKey, surah);
    await prefs.setInt(_ayahKey, ayah);
  }

  Future<({int surah, int ayah})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final surah = prefs.getInt(_surahKey);
    final ayah = prefs.getInt(_ayahKey);
    if (surah == null || ayah == null) return null;
    return (surah: surah, ayah: ayah);
  }
}
