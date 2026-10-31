import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';
import 'profile_scoped_prefs.dart';

/// Owns the list of local profiles and the active profile id.
class ProfileManager extends ChangeNotifier {
  static const _profilesKey = 'profiles_v1';
  static const _activeIdKey = 'active_profile_id';
  static const _legacyMigratedKey = 'legacy_migrated_v1';

  static const _legacySurahKey = 'manual_reading_position_surah';
  static const _legacyAyahKey = 'manual_reading_position_ayah';
  static const _legacyBookmarksKey = 'ayah_bookmark_list';
  static const _legacyDailyPlanKey = 'daily_recitation_plan_v1';

  List<Profile> _profiles = const [];
  String? _activeProfileId;
  bool _ready = false;

  List<Profile> get profiles => List.unmodifiable(_profiles);
  String? get activeProfileId => _activeProfileId;
  bool get isReady => _ready;

  Profile? get activeProfile {
    final id = _activeProfileId;
    if (id == null) return null;
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _profiles = _decodeProfiles(prefs.getString(_profilesKey));
    _activeProfileId = prefs.getString(_activeIdKey);

    final migrated = prefs.getBool(_legacyMigratedKey) ?? false;
    if (!migrated) {
      await _migrateLegacy(prefs);
    }

    if (_profiles.isEmpty) {
      final profile = _newProfile(name: 'Profile');
      _profiles = [profile];
      _activeProfileId = profile.id;
      await _persistMeta(prefs);
    } else if (_activeProfileId == null ||
        !_profiles.any((p) => p.id == _activeProfileId)) {
      _activeProfileId = _profiles.first.id;
      await prefs.setString(_activeIdKey, _activeProfileId!);
    }

    _ready = true;
    notifyListeners();
  }

  Future<Profile> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Profile name must not be empty');
    }
    final profile = _newProfile(name: trimmed);
    _profiles = [..._profiles, profile];
    final prefs = await SharedPreferences.getInstance();
    await _persistMeta(prefs);
    notifyListeners();
    return profile;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final next = [..._profiles];
    next[index] = next[index].copyWith(name: trimmed);
    _profiles = next;
    final prefs = await SharedPreferences.getInstance();
    await _persistMeta(prefs);
    notifyListeners();
  }

  /// Deletes [id]. Refuses when it is the only profile.
  /// If it was active, switches to another profile and returns that id.
  Future<String?> delete(String id) async {
    if (_profiles.length <= 1) return null;
    final remaining = _profiles.where((p) => p.id != id).toList();
    if (remaining.length == _profiles.length) return null;

    final prefs = await SharedPreferences.getInstance();
    final prefix = ProfileScopedPrefs.prefix(id);
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      await prefs.remove(key);
    }

    _profiles = remaining;
    String? switchedTo;
    if (_activeProfileId == id) {
      _activeProfileId = remaining.first.id;
      switchedTo = _activeProfileId;
    }
    await _persistMeta(prefs);
    notifyListeners();
    return switchedTo;
  }

  Future<void> select(String id) async {
    if (!_profiles.any((p) => p.id == id)) return;
    if (_activeProfileId == id) return;
    _activeProfileId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeIdKey, id);
    notifyListeners();
  }

  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final profile = _newProfile(name: 'Profile');
    _profiles = [profile];
    _activeProfileId = profile.id;

    final surah = prefs.getInt(_legacySurahKey);
    final ayah = prefs.getInt(_legacyAyahKey);
    if (surah != null) {
      await prefs.setInt(
        ProfileScopedPrefs.key(profile.id, _legacySurahKey),
        surah,
      );
    }
    if (ayah != null) {
      await prefs.setInt(
        ProfileScopedPrefs.key(profile.id, _legacyAyahKey),
        ayah,
      );
    }

    final bookmarks = prefs.getStringList(_legacyBookmarksKey);
    if (bookmarks != null && bookmarks.isNotEmpty) {
      await prefs.setStringList(
        ProfileScopedPrefs.key(profile.id, _legacyBookmarksKey),
        bookmarks,
      );
    }

    final plan = prefs.getString(_legacyDailyPlanKey);
    if (plan != null && plan.isNotEmpty) {
      await prefs.setString(
        ProfileScopedPrefs.key(profile.id, _legacyDailyPlanKey),
        plan,
      );
    }

    await prefs.setBool(_legacyMigratedKey, true);
    await _persistMeta(prefs);
  }

  Future<void> _persistMeta(SharedPreferences prefs) async {
    await prefs.setString(
      _profilesKey,
      jsonEncode([for (final p in _profiles) p.toJson()]),
    );
    final active = _activeProfileId;
    if (active != null) {
      await prefs.setString(_activeIdKey, active);
    }
  }

  List<Profile> _decodeProfiles(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>)
            Profile.fromJson(item)
          else if (item is Map)
            Profile.fromJson(Map<String, dynamic>.from(item)),
      ].where((p) => p.id.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Profile _newProfile({required String name}) {
    return Profile(
      id: _generateId(),
      name: name,
      createdAt: DateTime.now(),
    );
  }

  static String _generateId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
