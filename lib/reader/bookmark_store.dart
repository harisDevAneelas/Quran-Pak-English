import 'package:shared_preferences/shared_preferences.dart';

import 'profile_scoped_prefs.dart';

/// Ayah bookmarks saved from the verse action menu (per profile).
class BookmarkStore {
  BookmarkStore({required String profileId}) : _profileId = profileId;

  static const _baseKey = 'ayah_bookmark_list';

  String _profileId;

  String get profileId => _profileId;

  void bind(String profileId) {
    _profileId = profileId;
  }

  String get _key => ProfileScopedPrefs.key(_profileId, _baseKey);

  Future<List<({int surah, int ayah})>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return [for (final item in raw) ?_parse(item)];
  }

  Future<void> add({required int surah, required int ayah}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = [...?prefs.getStringList(_key)];
    final token = '$surah:$ayah';
    raw.remove(token);
    raw.insert(0, token);
    await prefs.setStringList(_key, raw);
  }

  Future<void> remove({required int surah, required int ayah}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = [...?prefs.getStringList(_key)];
    raw.remove('$surah:$ayah');
    await prefs.setStringList(_key, raw);
  }

  ({int surah, int ayah})? _parse(String token) {
    final parts = token.split(':');
    if (parts.length != 2) return null;
    final surah = int.tryParse(parts[0]);
    final ayah = int.tryParse(parts[1]);
    if (surah == null || ayah == null) return null;
    return (surah: surah, ayah: ayah);
  }
}
