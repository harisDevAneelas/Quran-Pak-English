import '../data/recommended_surah.dart';
import 'prayer_time_service.dart';

int hour12To24(int hour12, bool isPm) {
  final h = hour12 % 12;
  return isPm ? h + 12 : h;
}

enum TimedSurahEdge { morning, evening, dukhan }

/// Morning Yasin clamp: 4:00–7:30 inclusive of start, exclusive of end+1 min.
const yasinClampStartMinutes = 4 * 60;
const yasinClampEndMinutes = 7 * 60 + 30;

/// Evening learned max: next calendar day 02:00 as minutes from day start
/// of the prayer day (26:00 from prayer day's midnight = next day 2:00).
const eveningMaxMinutesFromPrayerDay = 26 * 60;

int clampYasinMinutes(int minutes) =>
    minutes.clamp(yasinClampStartMinutes, yasinClampEndMinutes);

/// Clamps [minutesFromMidnight] for an evening surah whose prayer started at
/// [prayerStart] on [prayerDay] (date-only). Result may land after midnight.
DateTime clampEveningFire({
  required DateTime prayerDay,
  required DateTime prayerStart,
  required int minutesFromMidnight,
}) {
  final dayStart = DateTime(prayerDay.year, prayerDay.month, prayerDay.day);
  var candidate = dayStart.add(Duration(minutes: minutesFromMidnight));
  final minT = prayerStart;
  final maxT = dayStart.add(
    const Duration(minutes: eveningMaxMinutesFromPrayerDay),
  );
  if (candidate.isBefore(minT)) candidate = minT;
  if (candidate.isAfter(maxT)) candidate = maxT;
  return candidate;
}

/// Next fire after applying learn-offset (−2 min) to a stored open time.
int learnedFireMinutes(int openMinutesFromMidnight) =>
    openMinutesFromMidnight - 2;

RecommendedSurah timedSurahNotificationAt(
  DateTime when, {
  TimedSurahEdge? kind,
}) {
  if (kind != null) {
    switch (kind) {
      case TimedSurahEdge.morning:
        return RecommendedSurahResolver.yasin;
      case TimedSurahEdge.evening:
        return RecommendedSurahResolver.waqiah;
      case TimedSurahEdge.dukhan:
        return RecommendedSurahResolver.dukhan;
    }
  }

  if (when.hour == RecommendedSurahResolver.yasinStartHour) {
    return RecommendedSurahResolver.yasin;
  }
  if (when.hour == RecommendedSurahResolver.eveningStartHour) {
    return RecommendedSurahResolver.waqiah;
  }
  if (when.hour == RecommendedSurahResolver.dukhanStartHour) {
    return RecommendedSurahResolver.dukhan;
  }
  return RecommendedSurahResolver.resolve(when);
}

bool shouldNotifyKahfAtMorning(DateTime morning) =>
    morning.weekday == DateTime.friday;

bool shouldNotifyDukhanAt(DateTime when) =>
    when.weekday == DateTime.thursday &&
    when.hour == RecommendedSurahResolver.dukhanStartHour;

/// Resolves the clock for یاسین / واقعہ / ملک for [day].
DateTime? resolveSurahNotifyTime({
  required int surah,
  required DateTime day,
  required Map<int, int> learnedMinutes,
  DayPrayerTimes? prayers,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final learned = learnedMinutes[surah];

  if (surah == RecommendedSurahResolver.yasin.surah) {
    int minutes;
    if (learned != null) {
      minutes = clampYasinMinutes(learnedFireMinutes(learned));
    } else if (prayers != null) {
      final fajrPlus = prayers.fajr.add(const Duration(minutes: 30));
      minutes = clampYasinMinutes(fajrPlus.hour * 60 + fajrPlus.minute);
    } else {
      minutes = RecommendedSurahResolver.yasinStartHour * 60;
    }
    return dayStart.add(Duration(minutes: minutes));
  }

  if (surah == RecommendedSurahResolver.waqiah.surah) {
    if (prayers == null && learned == null) {
      return DateTime(
        day.year,
        day.month,
        day.day,
        RecommendedSurahResolver.eveningStartHour,
      );
    }
    final prayerStart = prayers?.maghrib ??
        DateTime(day.year, day.month, day.day, 18, 0);
    if (learned != null) {
      return clampEveningFire(
        prayerDay: dayStart,
        prayerStart: prayerStart,
        minutesFromMidnight: learnedFireMinutes(learned),
      );
    }
    final raw = prayerStart.add(const Duration(minutes: 30));
    return clampEveningFire(
      prayerDay: dayStart,
      prayerStart: prayerStart,
      minutesFromMidnight: raw.hour * 60 +
          raw.minute +
          (raw.day != dayStart.day ? 24 * 60 : 0),
    );
  }

  if (surah == RecommendedSurahResolver.mulk.surah) {
    if (prayers == null && learned == null) {
      return DateTime(
        day.year,
        day.month,
        day.day,
        RecommendedSurahResolver.eveningStartHour,
      );
    }
    final prayerStart =
        prayers?.isha ?? DateTime(day.year, day.month, day.day, 19, 30);
    if (learned != null) {
      return clampEveningFire(
        prayerDay: dayStart,
        prayerStart: prayerStart,
        minutesFromMidnight: learnedFireMinutes(learned),
      );
    }
    final raw = prayerStart.add(const Duration(minutes: 30));
    return clampEveningFire(
      prayerDay: dayStart,
      prayerStart: prayerStart,
      minutesFromMidnight: raw.hour * 60 +
          raw.minute +
          (raw.day != dayStart.day ? 24 * 60 : 0),
    );
  }

  return null;
}

String formatClockUr(DateTime t) {
  final h24 = t.hour;
  final isPm = h24 >= 12;
  var h12 = h24 % 12;
  if (h12 == 0) h12 = 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return '$h12:$mm ${isPm ? 'PM' : 'AM'}';
}
