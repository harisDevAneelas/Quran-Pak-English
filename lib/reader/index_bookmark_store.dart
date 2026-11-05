import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_scoped_prefs.dart';

/// Profile-scoped whole-surah / whole-para bookmarks from the index grids.
///
/// Order is bookmark time: the first marked item stays first (not surah/para
/// number). Notifies on [bind] and save so an open hub can reload tiles.
class IndexBookmarkStore extends ChangeNotifier {
  IndexBookmarkStore({required String profileId}) : _profileId = profileId;

  static const _surahsBaseKey = 'index_bookmark_surahs_v1';
  static const _parasBaseKey = 'index_bookmark_paras_v1';

  String _profileId;

  String get profileId => _profileId;

  void bind(String profileId) {
    if (_profileId == profileId) return;
    _profileId = profileId;
    notifyListeners();
  }

  /// Surah ids in mark order (first bookmarked first).
  Future<List<int>> loadSurahs() async {
    return _loadIds(
      ProfileScopedPrefs.key(_profileId, _surahsBaseKey),
      min: 1,
      max: 114,
    );
  }

  /// Para ids in mark order (first bookmarked first).
  Future<List<int>> loadParas() async {
    return _loadIds(
      ProfileScopedPrefs.key(_profileId, _parasBaseKey),
      min: 1,
      max: 30,
    );
  }

  Future<bool> isSurahBookmarked(int surah) async {
    final all = await loadSurahs();
    return all.contains(surah);
  }

  Future<bool> isParaBookmarked(int para) async {
    final all = await loadParas();
    return all.contains(para);
  }

  Future<void> setSurahBookmarked(int surah, bool bookmarked) async {
    if (surah < 1 || surah > 114) return;
    final forProfile = _profileId;
    final key = ProfileScopedPrefs.key(forProfile, _surahsBaseKey);
    final current = await _loadIds(key, min: 1, max: 114);
    if (bookmarked) {
      if (!current.contains(surah)) current.add(surah);
    } else {
      current.remove(surah);
    }
    await _saveIds(key, current, forProfile: forProfile);
  }

  Future<void> setParaBookmarked(int para, bool bookmarked) async {
    if (para < 1 || para > 30) return;
    final forProfile = _profileId;
    final key = ProfileScopedPrefs.key(forProfile, _parasBaseKey);
    final current = await _loadIds(key, min: 1, max: 30);
    if (bookmarked) {
      if (!current.contains(para)) current.add(para);
    } else {
      current.remove(para);
    }
    await _saveIds(key, current, forProfile: forProfile);
  }

  Future<List<int>> _loadIds(
    String key, {
    required int min,
    required int max,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = <int>[];
      final seen = <int>{};
      for (final item in list) {
        final id = item is int ? item : int.tryParse('$item');
        if (id == null || id < min || id > max) continue;
        if (!seen.add(id)) continue;
        out.add(id);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIds(
    String key,
    List<int> ids, {
    required String forProfile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(ids));
    if (_profileId != forProfile) return;
    notifyListeners();
  }
}
