import 'package:adhan/adhan.dart';

class PrayerMethodOption {
  const PrayerMethodOption({
    required this.id,
    required this.labelUr,
    required this.method,
  });

  final String id;
  final String labelUr;
  final CalculationMethod method;
}

class PrayerFiqahOption {
  const PrayerFiqahOption({
    required this.id,
    required this.labelUr,
    required this.adhanFiqah,
  });

  final String id;
  final String labelUr;

  /// Mapped into the `adhan` package calculation API only.
  final Madhab adhanFiqah;
}

/// Selectable namaz calculation methods (excludes adhan `other`).
class PrayerCalculationCatalog {
  PrayerCalculationCatalog._();

  static const defaultMethodId = 'karachi';
  static const defaultFiqahId = 'hanafi';

  static const methods = <PrayerMethodOption>[
    PrayerMethodOption(
      id: 'karachi',
      labelUr: 'Karachi (Pakistan)',
      method: CalculationMethod.karachi,
    ),
    PrayerMethodOption(
      id: 'umm_al_qura',
      labelUr: 'Umm al-Qura (Saudi)',
      method: CalculationMethod.umm_al_qura,
    ),
    PrayerMethodOption(
      id: 'muslim_world_league',
      labelUr: 'Muslim World League',
      method: CalculationMethod.muslim_world_league,
    ),
    PrayerMethodOption(
      id: 'egyptian',
      labelUr: 'Egyptian',
      method: CalculationMethod.egyptian,
    ),
    PrayerMethodOption(
      id: 'dubai',
      labelUr: 'Dubai / Gulf',
      method: CalculationMethod.dubai,
    ),
    PrayerMethodOption(
      id: 'kuwait',
      labelUr: 'Kuwait',
      method: CalculationMethod.kuwait,
    ),
    PrayerMethodOption(
      id: 'qatar',
      labelUr: 'Qatar',
      method: CalculationMethod.qatar,
    ),
    PrayerMethodOption(
      id: 'north_america',
      labelUr: 'North America (ISNA)',
      method: CalculationMethod.north_america,
    ),
    PrayerMethodOption(
      id: 'moon_sighting_committee',
      labelUr: 'Moon Sighting Committee',
      method: CalculationMethod.moon_sighting_committee,
    ),
    PrayerMethodOption(
      id: 'turkey',
      labelUr: 'Turkey (Diyanet)',
      method: CalculationMethod.turkey,
    ),
    PrayerMethodOption(
      id: 'singapore',
      labelUr: 'Singapore',
      method: CalculationMethod.singapore,
    ),
    PrayerMethodOption(
      id: 'tehran',
      labelUr: 'Tehran',
      method: CalculationMethod.tehran,
    ),
  ];

  static const fiqahs = <PrayerFiqahOption>[
    PrayerFiqahOption(
      id: 'hanafi',
      labelUr: 'Hanafi',
      adhanFiqah: Madhab.hanafi,
    ),
    PrayerFiqahOption(
      id: 'shafi',
      labelUr: 'Shafi\'i',
      adhanFiqah: Madhab.shafi,
    ),
  ];

  static String resolveMethodId(String? raw) {
    if (raw == null || raw.isEmpty) return defaultMethodId;
    for (final m in methods) {
      if (m.id == raw) return m.id;
    }
    return defaultMethodId;
  }

  static String resolveFiqahId(String? raw) {
    if (raw == null || raw.isEmpty) return defaultFiqahId;
    for (final f in fiqahs) {
      if (f.id == raw) return f.id;
    }
    return defaultFiqahId;
  }

  static PrayerMethodOption methodOption(String id) {
    final resolved = resolveMethodId(id);
    return methods.firstWhere((m) => m.id == resolved);
  }

  static PrayerFiqahOption fiqahOption(String id) {
    final resolved = resolveFiqahId(id);
    return fiqahs.firstWhere((f) => f.id == resolved);
  }

  static String fiqahLabel(String id) => fiqahOption(id).labelUr;

  static CalculationMethod toMethod(String id) => methodOption(id).method;

  /// `adhan` package value for عصر shadow length (حنفی / شافعی).
  static Madhab toAdhanFiqah(String id) => fiqahOption(id).adhanFiqah;
}
