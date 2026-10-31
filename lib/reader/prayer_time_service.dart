import 'package:adhan/adhan.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/prayer_calculation_catalog.dart';

enum NamazName { fajr, dhuhr, asr, maghrib, isha }

extension NamazNameUr on NamazName {
  String get labelUr => switch (this) {
        NamazName.fajr => 'Fajr',
        NamazName.dhuhr => 'Dhuhr',
        NamazName.asr => 'Asr',
        NamazName.maghrib => 'Maghrib',
        NamazName.isha => 'Isha',
      };
}

class DayPrayerTimes {
  const DayPrayerTimes({
    required this.date,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.nextFajr,
  });

  final DateTime date;
  final DateTime fajr;

  /// Sunrise — end of the Fajr window (not ظہر).
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  /// End of the Isha window (usually next day's Fajr).
  final DateTime nextFajr;

  DateTime startOf(NamazName name) => switch (name) {
        NamazName.fajr => fajr,
        NamazName.dhuhr => dhuhr,
        NamazName.asr => asr,
        NamazName.maghrib => maghrib,
        NamazName.isha => isha,
      };

  /// Authentic end of each fard window: Fajr ends at sunrise, not at Dhuhr.
  DateTime endOf(NamazName name) => switch (name) {
        NamazName.fajr => sunrise,
        NamazName.dhuhr => asr,
        NamazName.asr => maghrib,
        NamazName.maghrib => isha,
        NamazName.isha => nextFajr,
      };

  /// Current prayer at [now], including overnight عشاء until Fajr.
  ///
  /// Returns null between sunrise and ظہر (no fard window then).
  ({NamazName name, DateTime start, DateTime end})? currentAt(DateTime now) {
    if (now.isBefore(fajr)) {
      return (name: NamazName.isha, start: isha, end: fajr);
    }
    for (final name in NamazName.values) {
      final start = startOf(name);
      final end = endOf(name);
      if (!now.isBefore(start) && now.isBefore(end)) {
        return (name: name, start: start, end: end);
      }
    }
    return null;
  }

  /// Next fard start at or after [now] (e.g. ظہر while after sunrise).
  ({NamazName name, DateTime start})? nextAt(DateTime now) {
    for (final name in NamazName.values) {
      final start = startOf(name);
      if (now.isBefore(start)) {
        return (name: name, start: start);
      }
    }
    if (now.isBefore(nextFajr)) {
      return (name: NamazName.fajr, start: nextFajr);
    }
    return null;
  }

  /// صبح until ظہر, دوپہر until عصر, شام until مغرب, رات from مغرب (and before فجر).
  String dayPartAt(DateTime t) {
    if (t.isBefore(fajr)) return 'Night';
    if (t.isBefore(dhuhr)) return 'Morning';
    if (t.isBefore(asr)) return 'Afternoon';
    if (t.isBefore(maghrib)) return 'Evening';
    return 'Night';
  }
}

/// Device location (throttled) + prayer times from the active profile's method.
///
/// GPS is used at most about twice a day. Cached coords drive hub times and
/// the day's namaz notifications; the phone GPS switch is never force-toggled.
class PrayerTimeService extends ChangeNotifier {
  PrayerTimeService._();

  static final PrayerTimeService instance = PrayerTimeService._();

  static const _latKey = 'prayer_last_lat_v1';
  static const _lngKey = 'prayer_last_lng_v1';
  static const _fixKey = 'prayer_last_fix_ms_v1';
  static const _consentAskedKey = 'prayer_location_consent_asked_v1';

  /// Cap live GPS to roughly twice per day.
  static const _refreshInterval = Duration(hours: 12);

  Coordinates? _coords;
  String? _errorUr;
  int _locateGen = 0;
  CalculationMethod _method = CalculationMethod.karachi;
  Madhab _fiqah = Madhab.hanafi;

  String? get errorUr => _errorUr;

  /// Whether a cached or live GPS fix is available for prayer math.
  bool get hasCoords => _coords != null;

  /// True only until the first-open consent dialog has been shown once.
  Future<bool> shouldAskLocationConsentOnOpen() async {
    if (kIsWeb) return false;
    if (!await needsLocationPermission()) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_consentAskedKey) ?? false);
  }

  Future<void> markLocationConsentAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentAskedKey, true);
  }

  /// Syncs calculation prefs from [ReaderSettings] (or defaults).
  void applyCalculation({
    required String methodId,
    required String fiqahId,
  }) {
    final method = PrayerCalculationCatalog.toMethod(methodId);
    final fiqah = PrayerCalculationCatalog.toAdhanFiqah(fiqahId);
    if (method == _method && fiqah == _fiqah) return;
    _method = method;
    _fiqah = fiqah;
    notifyListeners();
  }

  /// True when the OS has not granted while-in-use / always permission yet.
  Future<bool> needsLocationPermission() async {
    if (kIsWeb) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;
  }

  /// Loads cache; may refresh GPS at most ~twice/day unless [forceRefresh].
  Future<void> beginForegroundLocation({
    bool promptSettings = false,
    bool afterUserConsent = false,
  }) async {
    await ensureLocation(
      promptSettings: promptSettings,
      requestOsPermission: afterUserConsent,
      openServiceIfOff: afterUserConsent,
      forceRefresh: afterUserConsent || promptSettings,
    );
  }

  /// Cancels an in-flight rare GPS fix.
  void endForegroundLocation() {
    _locateGen++;
  }

  /// Resolves coordinates from cache, with optional throttled live GPS.
  Future<void> ensureLocation({
    bool promptSettings = false,
    bool requestOsPermission = false,
    bool openServiceIfOff = false,
    bool forceRefresh = false,
  }) async {
    final gen = ++_locateGen;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (gen != _locateGen) return;

      await _loadCache(prefs);
      if (gen != _locateGen) return;

      var permission = await Geolocator.checkPermission();
      if (gen != _locateGen) return;
      if (permission == LocationPermission.denied && requestOsPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (gen != _locateGen) return;
      if (permission == LocationPermission.denied) {
        if (_coords == null) {
          _errorUr = 'Allow location to see prayer times';
        }
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (_coords == null) {
          _errorUr =
              'Allow location in Settings, then come back';
        }
        if (promptSettings || requestOsPermission) {
          await Geolocator.openAppSettings();
        }
        return;
      }

      final needsGps = forceRefresh || _coords == null || _cacheStale(prefs);
      if (!needsGps) {
        _errorUr = null;
        return;
      }

      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (gen != _locateGen) return;
      if (!serviceOn) {
        if (_coords != null) {
          _errorUr = null;
        } else {
          _errorUr =
              'Phone location is off. Turn it on to see prayer times';
        }
        if (promptSettings || openServiceIfOff) {
          await Geolocator.openLocationSettings();
        }
        return;
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _locationSettings(),
        );
        if (gen != _locateGen) return;
        await _saveFix(prefs, pos.latitude, pos.longitude);
        _errorUr = null;
        notifyListeners();
      } catch (e) {
        debugPrint('PrayerTimeService getCurrentPosition: $e');
        if (_coords == null) {
          final last = await Geolocator.getLastKnownPosition();
          if (gen != _locateGen) return;
          if (last != null) {
            await _saveFix(prefs, last.latitude, last.longitude);
            _errorUr = null;
            notifyListeners();
          } else {
            _errorUr = 'Could not get location. Try again';
          }
        }
      }
    } catch (e) {
      debugPrint('PrayerTimeService location: $e');
      if (_coords == null) {
        _errorUr = 'Could not get location';
      }
    }
  }

  Future<void> _loadCache(SharedPreferences prefs) async {
    final cachedLat = prefs.getDouble(_latKey);
    final cachedLng = prefs.getDouble(_lngKey);
    if (cachedLat != null && cachedLng != null) {
      _coords = Coordinates(cachedLat, cachedLng);
      _errorUr = null;
    }
  }

  bool _cacheStale(SharedPreferences prefs) {
    final ms = prefs.getInt(_fixKey);
    if (ms == null) return true;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    return age >= _refreshInterval;
  }

  Future<void> _saveFix(
    SharedPreferences prefs,
    double lat,
    double lng,
  ) async {
    _coords = Coordinates(lat, lng);
    await prefs.setDouble(_latKey, lat);
    await prefs.setDouble(_lngKey, lng);
    await prefs.setInt(_fixKey, DateTime.now().millisecondsSinceEpoch);
  }

  LocationSettings _locationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 0,
        forceLocationManager: true,
        timeLimit: const Duration(seconds: 20),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.low,
        activityType: ActivityType.other,
        timeLimit: const Duration(seconds: 20),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.low,
      timeLimit: Duration(seconds: 20),
    );
  }

  DayPrayerTimes? timesFor(DateTime day) {
    final c = _coords;
    if (c == null) return null;
    final params = _method.getParameters();
    // `madhab` is the adhan package field name; app language is فقہ.
    params.madhab = _fiqah;
    final components = DateComponents.from(day);
    final times = PrayerTimes(c, components, params);
    final nextDay = day.add(const Duration(days: 1));
    final next = PrayerTimes(c, DateComponents.from(nextDay), params);
    return DayPrayerTimes(
      date: DateTime(day.year, day.month, day.day),
      fajr: times.fajr,
      sunrise: times.sunrise,
      dhuhr: times.dhuhr,
      asr: times.asr,
      maghrib: times.maghrib,
      isha: times.isha,
      nextFajr: next.fajr,
    );
  }

  /// Today's times, with عشاء spanning overnight until Fajr when needed.
  DayPrayerTimes? today([DateTime? now]) {
    final t = now ?? DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final times = timesFor(day);
    if (times == null) return null;
    if (!t.isBefore(times.fajr)) return times;

    final prev = timesFor(day.subtract(const Duration(days: 1)));
    if (prev == null) {
      return DayPrayerTimes(
        date: times.date,
        fajr: times.fajr,
        sunrise: times.sunrise,
        dhuhr: times.dhuhr,
        asr: times.asr,
        maghrib: times.maghrib,
        isha: times.isha,
        nextFajr: times.fajr,
      );
    }
    return DayPrayerTimes(
      date: times.date,
      fajr: times.fajr,
      sunrise: times.sunrise,
      dhuhr: times.dhuhr,
      asr: times.asr,
      maghrib: times.maghrib,
      isha: prev.isha,
      nextFajr: times.fajr,
    );
  }
}
