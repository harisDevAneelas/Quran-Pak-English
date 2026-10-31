import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/audio_language_catalog.dart';
import '../data/ayah_repeat_mode.dart';
import '../data/azaan_catalog.dart';
import '../data/prayer_calculation_catalog.dart';
import '../data/reciter_catalog.dart';
import '../data/tilawat_order.dart';
import '../data/translation_catalog.dart';
import 'profile_scoped_prefs.dart';

/// Reader preferences. Changing these must not reparse Quran JSON or reload fonts.
class ReaderSettings extends ChangeNotifier {
  static const _baseKey = 'reader_settings_v1';

  double _fontSize = 40;
  bool _tajweedEnabled = true;
  ThemeMode _themeMode = ThemeMode.light;
  Color? _customBackground;
  bool _hideTranslation = false;
  bool _backgroundRecitation = false;
  String _reciterId = ReciterCatalog.defaultId;
  /// Last chosen spoken-translation language (never `none`).
  String _audioLanguageId = AudioLanguageCatalog.defaultId;
  bool _audioTranslationEnabled = false;
  TilawatOrder _tilawatOrder = TilawatOrder.defaultOrder;
  AyahRepeatMode _ayahRepeatMode = AyahRepeatMode.defaultMode;
  String _prayerMethodId = PrayerCalculationCatalog.defaultMethodId;
  String _prayerFiqahId = PrayerCalculationCatalog.defaultFiqahId;
  String _azaanId = AzaanCatalog.defaultId;
  bool _azaanEnabled = true;
  List<String> _translatorIds =
      List<String>.from(TranslationCatalog.defaultIds);

  /// When true, [notifyListeners] still runs but callers can skip persistence.
  bool applyingProfile = false;

  double get fontSize => _fontSize;
  bool get tajweedEnabled => _tajweedEnabled;
  ThemeMode get themeMode => _themeMode;
  Color? get customBackground => _customBackground;
  bool get hideTranslation => _hideTranslation;
  /// When on, tilawat may continue with a media notification while locked.
  bool get backgroundRecitation => _backgroundRecitation;
  /// Folder id used in the recitation audio URL.
  String get reciterId => _reciterId;

  /// English name shown in the sidebar and reciter list.
  String get reciterLabel => ReciterCatalog.labelFor(_reciterId);

  /// Effective playback language (`none` when the sidebar toggle is off).
  String get audioLanguageId => _audioTranslationEnabled
      ? _audioLanguageId
      : AudioLanguageCatalog.noneId;

  /// Selected language label (shown even when the toggle is off).
  String get audioLanguageLabel =>
      AudioLanguageCatalog.labelFor(_audioLanguageId);

  bool get audioTranslationEnabled => _audioTranslationEnabled;

  TilawatOrder get tilawatOrder => _tilawatOrder;

  AyahRepeatMode get ayahRepeatMode => _ayahRepeatMode;

  /// Namaz calculation method id ([PrayerCalculationCatalog]).
  String get prayerMethodId => _prayerMethodId;

  /// عصر فقہ id ([PrayerCalculationCatalog]) — حنفی / شافعی.
  String get prayerFiqahId => _prayerFiqahId;

  String get prayerFiqahLabel =>
      PrayerCalculationCatalog.fiqahLabel(_prayerFiqahId);

  /// Azaan voice for namaz-start notifications (used when [azaanEnabled]).
  String get azaanId => _azaanId;

  String get azaanLabel => AzaanCatalog.labelFor(_azaanId);

  /// When off, namaz alerts use the default system sound (no azaan clip).
  bool get azaanEnabled => _azaanEnabled;

  /// Selected translator catalog ids (catalog order when set via picker).
  List<String> get translatorIds => List<String>.unmodifiable(_translatorIds);

  /// First selected id — back-compat for older call sites.
  String get translatorId => _translatorIds.isEmpty
      ? TranslationCatalog.defaultId
      : _translatorIds.first;

  /// Summary label for the sidebar subtitle.
  String get translatorLabel {
    if (_translatorIds.isEmpty) {
      return 'None';
    }
    if (_translatorIds.length == 1) {
      return TranslationCatalog.labelFor(_translatorIds.first);
    }
    return '${_translatorIds.length} translations selected';
  }

  void setFontSize(double value) {
    final next = value.clamp(18.0, 56.0);
    if (next == _fontSize) return;
    _fontSize = next;
    notifyListeners();
  }

  void setTajweedEnabled(bool value) {
    if (value == _tajweedEnabled) return;
    _tajweedEnabled = value;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
  }

  /// Toggles on-screen translation text only — does not change spoken audio.
  void setHideTranslation(bool value) {
    if (value == _hideTranslation) return;
    _hideTranslation = value;
    notifyListeners();
  }

  void setBackgroundRecitation(bool value) {
    if (value == _backgroundRecitation) return;
    _backgroundRecitation = value;
    notifyListeners();
  }

  void setReciter(String value) {
    final id = ReciterCatalog.resolveId(value);
    if (id == _reciterId) return;
    _reciterId = id;
    notifyListeners();
  }

  void setAudioTranslationEnabled(bool value) {
    if (value == _audioTranslationEnabled) return;
    _audioTranslationEnabled = value;
    if (value) {
      if (_tilawatOrder == TilawatOrder.recitationOnly) {
        _tilawatOrder = TilawatOrder.recitationThenTranslation;
      }
    } else if (_tilawatOrder != TilawatOrder.recitationOnly) {
      _tilawatOrder = TilawatOrder.recitationOnly;
    }
    notifyListeners();
  }

  void setAudioLanguage(String value) {
    final id = AudioLanguageCatalog.resolveSelectableId(value);
    if (id == _audioLanguageId && _audioTranslationEnabled) return;
    _audioLanguageId = id;
    _audioTranslationEnabled = true;
    if (_tilawatOrder == TilawatOrder.recitationOnly) {
      _tilawatOrder = TilawatOrder.recitationThenTranslation;
    }
    notifyListeners();
  }

  void setTilawatOrder(TilawatOrder value) {
    final wantsSpoken = value != TilawatOrder.recitationOnly;
    if (value == _tilawatOrder &&
        wantsSpoken == _audioTranslationEnabled) {
      if (wantsSpoken && _hideTranslation) {
        _hideTranslation = false;
        notifyListeners();
      }
      return;
    }
    _tilawatOrder = value;
    _audioTranslationEnabled = wantsSpoken;
    // On-screen text is not tied to whether translation audio is playing.
    // صرف Translation (and mixed orders) still show the translation on screen.
    if (wantsSpoken) {
      _hideTranslation = false;
    }
    notifyListeners();
  }

  void setAyahRepeatMode(AyahRepeatMode value) {
    if (value == _ayahRepeatMode) return;
    _ayahRepeatMode = value;
    notifyListeners();
  }

  void cycleAyahRepeatMode() {
    setAyahRepeatMode(_ayahRepeatMode.next);
  }

  void setPrayerFiqah(String value) {
    final id = PrayerCalculationCatalog.resolveFiqahId(value);
    if (id == _prayerFiqahId) return;
    _prayerFiqahId = id;
    notifyListeners();
  }

  void setAzaanEnabled(bool value) {
    if (value == _azaanEnabled) return;
    _azaanEnabled = value;
    notifyListeners();
  }

  void setAzaan(String value) {
    final id = AzaanCatalog.resolveId(value);
    if (id == _azaanId && _azaanEnabled) return;
    _azaanId = id;
    _azaanEnabled = true;
    notifyListeners();
  }

  void setTranslatorIds(Iterable<String> ids) {
    final next = TranslationCatalog.resolveIds(ids);
    if (_sameIds(next, _translatorIds)) return;
    _translatorIds = next;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'fontSize': _fontSize,
        'tajweedEnabled': _tajweedEnabled,
        'themeMode': _themeMode.name,
        'customBackground': _customBackground?.toARGB32(),
        'hideTranslation': _hideTranslation,
        'backgroundRecitation': _backgroundRecitation,
        'reciter': _reciterId,
        'audioLanguage': _audioLanguageId,
        'audioTranslationEnabled': _audioTranslationEnabled,
        'tilawatOrder': _tilawatOrder.name,
        'ayahRepeatMode': _ayahRepeatMode.name,
        'prayerMethod': _prayerMethodId,
        'prayerFiqah': _prayerFiqahId,
        'azaan': _azaanId,
        'azaanEnabled': _azaanEnabled,
        'translator': translatorId,
        'translators': _translatorIds,
      };

  /// Replaces all fields from [json] (or defaults) and notifies once.
  void applyAll(Map<String, dynamic>? json) {
    applyingProfile = true;
    try {
      _fontSize =
          (json?['fontSize'] as num?)?.toDouble().clamp(18.0, 56.0) ?? 40;
      _tajweedEnabled = json?['tajweedEnabled'] as bool? ?? true;
      _themeMode = _themeModeFromName(json?['themeMode'] as String?);
      final bg = json?['customBackground'];
      _customBackground = bg is int ? Color(bg) : null;
      _hideTranslation = json?['hideTranslation'] as bool? ?? false;
      _backgroundRecitation = json?['backgroundRecitation'] as bool? ??
          json?['phoneLock'] as bool? ??
          false;
      _reciterId = ReciterCatalog.resolveId(json?['reciter'] as String?);
      final rawAudio = json?['audioLanguage'] as String?;
      final resolvedAudio = AudioLanguageCatalog.resolveId(rawAudio);
      if (resolvedAudio == AudioLanguageCatalog.noneId) {
        _audioLanguageId = AudioLanguageCatalog.defaultId;
        _audioTranslationEnabled =
            json?['audioTranslationEnabled'] as bool? ?? false;
      } else {
        _audioLanguageId = resolvedAudio;
        _audioTranslationEnabled =
            json?['audioTranslationEnabled'] as bool? ?? true;
      }
      _tilawatOrder = TilawatOrder.fromName(json?['tilawatOrder'] as String?);
      _ayahRepeatMode =
          AyahRepeatMode.fromName(json?['ayahRepeatMode'] as String?);
      _prayerMethodId = PrayerCalculationCatalog.resolveMethodId(
        json?['prayerMethod'] as String?,
      );
      _prayerFiqahId = PrayerCalculationCatalog.resolveFiqahId(
        json?['prayerFiqah'] as String? ?? json?['prayerMadhab'] as String?,
      );
      _azaanId = AzaanCatalog.resolveId(json?['azaan'] as String?);
      _azaanEnabled = json?['azaanEnabled'] as bool? ?? true;

      final rawList = json?['translators'];
      if (rawList is List) {
        _translatorIds = TranslationCatalog.resolveIds(
          rawList.map((e) => e.toString()),
        );
      } else if (json != null && json.containsKey('translator')) {
        _translatorIds = TranslationCatalog.resolveIds([
          json['translator'] as String? ?? '',
        ]);
      } else {
        _translatorIds = List<String>.from(TranslationCatalog.defaultIds);
      }

      notifyListeners();
    } finally {
      applyingProfile = false;
    }
  }

  /// Resets to factory defaults (used for brand-new profiles).
  void applyDefaults() => applyAll(null);

  /// Factory defaults for the active profile, then notify so listeners persist.
  ///
  /// [applyAll] skips persistence while [applyingProfile] is set; a second
  /// notify after that flag clears writes the reset JSON.
  void resetToDefaults() {
    applyDefaults();
    notifyListeners();
  }

  Future<void> load(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(ProfileScopedPrefs.key(profileId, _baseKey));
    if (raw == null || raw.isEmpty) {
      applyDefaults();
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      applyAll(json);
    } catch (_) {
      applyDefaults();
    }
  }

  Future<void> save(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ProfileScopedPrefs.key(profileId, _baseKey),
      jsonEncode(toJson()),
    );
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }
}
