import 'package:flutter/foundation.dart';

class NotificationTarget {
  const NotificationTarget.todaysRecitation()
      : todaysRecitation = true,
        hub = false,
        surah = null;

  const NotificationTarget.hub()
      : todaysRecitation = false,
        hub = true,
        surah = null;

  const NotificationTarget.surah(this.surah)
      : todaysRecitation = false,
        hub = false;

  final bool todaysRecitation;
  final bool hub;
  final int? surah;
}

abstract final class NotificationRoute {
  static const todaysRecitationPayload = 'todays_recitation';
  static const hubPayload = 'hub';
  static const surahPayloadPrefix = 'surah:';

  static bool pendingTodaysRecitation = false;
  static bool pendingHub = false;
  static int? pendingSurah;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static String surahPayload(int surah) => '$surahPayloadPrefix$surah';

  static int? surahFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(surahPayloadPrefix)) {
      return null;
    }
    final surah = int.tryParse(payload.substring(surahPayloadPrefix.length));
    if (surah == null || surah < 1 || surah > 114) return null;
    return surah;
  }

  static void requestFromPayload(String? payload) {
    final surah = surahFromPayload(payload);
    if (surah != null) {
      pendingTodaysRecitation = false;
      pendingHub = false;
      if (pendingSurah == surah) return;
      pendingSurah = surah;
      changes.value++;
      return;
    }
    if (payload == todaysRecitationPayload) {
      requestTodaysRecitation();
      return;
    }
    if (payload == hubPayload) {
      pendingSurah = null;
      pendingTodaysRecitation = false;
      if (pendingHub) return;
      pendingHub = true;
      changes.value++;
    }
  }

  static void requestTodaysRecitation() {
    pendingSurah = null;
    if (pendingTodaysRecitation) return;
    pendingTodaysRecitation = true;
    changes.value++;
  }

  static NotificationTarget? take() {
    final surah = pendingSurah;
    if (surah != null) {
      pendingSurah = null;
      pendingTodaysRecitation = false;
      pendingHub = false;
      return NotificationTarget.surah(surah);
    }
    if (pendingHub) {
      pendingHub = false;
      pendingTodaysRecitation = false;
      return const NotificationTarget.hub();
    }
    if (!pendingTodaysRecitation) return null;
    pendingTodaysRecitation = false;
    return const NotificationTarget.todaysRecitation();
  }

  static bool takeTodaysRecitation() {
    final target = take();
    return target?.todaysRecitation ?? false;
  }
}
