class RecommendedSurah {
  const RecommendedSurah({
    required this.surah,
    required this.labelUr,
    required this.titleUr,
    required this.reasonUr,
  });

  final int surah;
  final String labelUr;
  final String titleUr;
  final String reasonUr;
}

/// Hub فوری فہرست candidates: daily + timed occasion surahs.
abstract final class OccasionSurahs {
  static const muzammil = RecommendedSurah(
    surah: 73,
    labelUr: 'Muzammil',
    titleUr: 'Surah Muzammil',
    reasonUr: 'Daily',
  );
  static const rahman = RecommendedSurah(
    surah: 55,
    labelUr: 'Rahman',
    titleUr: 'Surah Rahman',
    reasonUr: 'Daily',
  );

  static List<RecommendedSurah> get all => [
        muzammil,
        rahman,
        RecommendedSurahResolver.yasin,
        RecommendedSurahResolver.waqiah,
        RecommendedSurahResolver.mulk,
        RecommendedSurahResolver.sajdah,
        RecommendedSurahResolver.kahf,
        RecommendedSurahResolver.dukhan,
      ];

  static RecommendedSurah? byId(int surah) {
    for (final item in all) {
      if (item.surah == surah) return item;
    }
    return null;
  }

  static bool contains(int surah) => byId(surah) != null;
}

abstract final class RecommendedSurahResolver {
  static const yasinStartHour = 6;
  static const yasinEndHour = 12;
  static const eveningStartHour = 19;
  static const eveningEndHour = 3;
  static const kahfStartHour = 6;
  static const kahfEndHour = 19;
  static const dukhanStartHour = 20;
  static const dukhanEndHour = 3;

  static const kahf = RecommendedSurah(
    surah: 18,
    labelUr: 'Kahf',
    titleUr: 'Surah Kahf',
    reasonUr: 'Friday',
  );
  static const dukhan = RecommendedSurah(
    surah: 44,
    labelUr: 'Dukhan',
    titleUr: 'Surah Dukhan',
    reasonUr: 'Thursday',
  );
  static const mulk = RecommendedSurah(
    surah: 67,
    labelUr: 'Mulk',
    titleUr: 'Surah Mulk',
    reasonUr: 'Evening',
  );
  static const yasin = RecommendedSurah(
    surah: 36,
    labelUr: 'Yasin',
    titleUr: 'Surah Yasin',
    reasonUr: 'Morning',
  );
  static const waqiah = RecommendedSurah(
    surah: 56,
    labelUr: 'Waqiah',
    titleUr: 'Surah Waqiah',
    reasonUr: 'Evening',
  );
  static const sajdah = RecommendedSurah(
    surah: 32,
    labelUr: 'Sajdah',
    titleUr: 'Surah Sajdah',
    reasonUr: 'Evening',
  );

  static RecommendedSurah resolve([DateTime? now]) {
    final many = resolveMany(now);
    if (many.isNotEmpty) return many.first;
    return yasin;
  }

  static List<RecommendedSurah> resolveMany([DateTime? now]) {
    final t = now ?? DateTime.now();
    final seen = <int>{};
    final out = <RecommendedSurah>[];

    void add(RecommendedSurah surah) {
      if (seen.add(surah.surah)) out.add(surah);
    }

    if (isKahfWindow(t)) add(kahf);
    if (isDukhanWindow(t)) add(dukhan);
    if (isEveningWindow(t)) {
      add(mulk);
      add(waqiah);
      add(sajdah);
    }
    if (isYasinWindow(t)) add(yasin);
    return out;
  }

  static bool isYasinWindow(DateTime t) =>
      t.hour >= yasinStartHour && t.hour < yasinEndHour;

  static bool isEveningWindow(DateTime t) =>
      t.hour >= eveningStartHour || t.hour < eveningEndHour;

  static bool isKahfWindow(DateTime t) =>
      t.weekday == DateTime.friday &&
      t.hour >= kahfStartHour &&
      t.hour < kahfEndHour;

  static bool isDukhanWindow(DateTime t) {
    if (t.weekday == DateTime.thursday) {
      return t.hour >= dukhanStartHour;
    }
    if (t.weekday == DateTime.friday) {
      return t.hour < dukhanEndHour;
    }
    return false;
  }
}
