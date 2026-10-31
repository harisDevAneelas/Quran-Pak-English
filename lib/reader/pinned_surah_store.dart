import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/recommended_surah.dart';
import 'profile_scoped_prefs.dart';

/// Profile-scoped hub pins for occasion surahs (مستقل / Quick list).
///
/// Notifies on [bind] and [save] so an open hub can reload after a profile switch.
class PinnedSurahStore extends ChangeNotifier {
  PinnedSurahStore({required String profileId}) : _profileId = profileId;

  static const _baseKey = 'pinned_occasion_surahs_v1';

  String _profileId;

  String get profileId => _profileId;

  void bind(String profileId) {
    if (_profileId == profileId) return;
    _profileId = profileId;
    notifyListeners();
  }

  String get _key => ProfileScopedPrefs.key(_profileId, _baseKey);

  Future<Set<int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return {};
      final out = <int>{};
      for (final item in list) {
        final id = item is int ? item : int.tryParse('$item');
        if (id != null && OccasionSurahs.contains(id)) out.add(id);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Set<int> surahs) async {
    final prefs = await SharedPreferences.getInstance();
    final forProfile = _profileId;
    final cleaned = [
      for (final id in surahs)
        if (OccasionSurahs.contains(id)) id,
    ]..sort();
    await prefs.setString(
      ProfileScopedPrefs.key(forProfile, _baseKey),
      jsonEncode(cleaned),
    );
    if (_profileId != forProfile) return;
    notifyListeners();
  }

  Future<void> setPinned(int surah, bool pinned) async {
    if (!OccasionSurahs.contains(surah)) return;
    final current = await load();
    if (pinned) {
      current.add(surah);
    } else {
      current.remove(surah);
    }
    await save(current);
  }
}
