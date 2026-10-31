import 'package:shared_preferences/shared_preferences.dart';

import 'profile_scoped_prefs.dart';

/// Last-seen Today's recitation position, separate from the main mushaf store.
class TilawatPositionStore {
  TilawatPositionStore({required String profileId}) : _profileId = profileId;

  static const _surahBase = 'tilawat_reading_position_surah';
  static const _ayahBase = 'tilawat_reading_position_ayah';
  static const _promptDayBase = 'tilawat_arrangement_prompt_day';

  String _profileId;

  String get profileId => _profileId;

  void bind(String profileId) {
    _profileId = profileId;
  }

  String get _surahKey => ProfileScopedPrefs.key(_profileId, _surahBase);
  String get _ayahKey => ProfileScopedPrefs.key(_profileId, _ayahBase);
  String get _promptDayKey =>
      ProfileScopedPrefs.key(_profileId, _promptDayBase);

  static String _localDayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

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

  /// Arrangement prompt at most once per local calendar day.
  Future<bool> shouldShowArrangementPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_promptDayKey) != _localDayKey();
  }

  Future<void> markArrangementPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_promptDayKey, _localDayKey());
  }
}
