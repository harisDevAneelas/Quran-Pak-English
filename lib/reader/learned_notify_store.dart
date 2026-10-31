import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'profile_scoped_prefs.dart';

/// Per-surah learned notification clock (minutes from local midnight).
///
/// Device-global for scheduling (one phone), keyed by active profile so each
/// profile can learn independently when that profile is active.
class LearnedNotifyStore {
  LearnedNotifyStore({required String profileId}) : _profileId = profileId;

  static const _baseKey = 'learned_surah_notify_v1';

  String _profileId;

  void bind(String profileId) {
    _profileId = profileId;
  }

  String get _key => ProfileScopedPrefs.key(_profileId, _baseKey);

  Future<Map<int, int>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return {};
      final out = <int, int>{};
      json.forEach((key, value) {
        final surah = int.tryParse('$key');
        final minutes = value is int ? value : int.tryParse('$value');
        if (surah != null && minutes != null) {
          out[surah] = minutes.clamp(0, 24 * 60 - 1);
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<int?> loadMinutes(int surah) async {
    final all = await loadAll();
    return all[surah];
  }

  Future<void> saveMinutes(int surah, int minutesFromMidnight) async {
    final all = await loadAll();
    all[surah] = minutesFromMidnight.clamp(0, 24 * 60 - 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final e in all.entries) '${e.key}': e.value,
      }),
    );
  }

  Future<void> recordOpenNow(int surah, [DateTime? now]) async {
    final t = now ?? DateTime.now();
    await saveMinutes(surah, t.hour * 60 + t.minute);
  }
}
