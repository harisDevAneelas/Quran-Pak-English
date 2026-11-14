import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/azaan_catalog.dart';
import '../data/quran_metadata.dart';
import '../data/recommended_surah.dart';
import 'daily_plan.dart';
import 'learned_notify_store.dart';
import 'notification_route.dart';
import 'prayer_time_service.dart';
import 'reader_settings.dart';
import 'reminder_schedule.dart';

/// Schedules daily-plan, timed-surah, and namaz-start local notifications.
class AppNotificationScheduler {
  AppNotificationScheduler._();

  static final AppNotificationScheduler instance = AppNotificationScheduler._();

  static const _confirmId = 1000;
  static const _dailyId = 1001;
  static const _timedBaseId = 2000;
  static const _prayerBaseId = 3000;
  static const _reminderChannelId = 'com.quran_app.reminders';
  static const _reminderChannelName = 'Reminders';
  static const _namazChannelName = 'Prayer azaan';
  static const _androidIcon = 'ic_stat_notify';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  AndroidScheduleMode _androidMode = AndroidScheduleMode.inexactAllowWhileIdle;
  ReaderSettings? _settings;

  /// Binds profile settings so namaz notifications use the chosen azaan.
  void bindSettings(ReaderSettings settings) {
    _settings = settings;
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_ready) return;

    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('Timezone fallback to UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@drawable/ic_stat_notify');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      NotificationRoute.requestFromPayload(
        launch!.notificationResponse?.payload,
      );
    }

    _ready = true;
  }

  void _onResponse(NotificationResponse response) {
    NotificationRoute.requestFromPayload(response.payload);
  }

  Future<bool> _ensurePermission({bool requestExact = false}) async {
    if (kIsWeb) return false;
    if (!_ready) await initialize();

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      var exact = await android?.canScheduleExactNotifications();
      if (requestExact && exact != true) {
        await android?.requestExactAlarmsPermission();
        exact = await android?.canScheduleExactNotifications();
      }
      _androidMode = exact == true
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      return granted ?? true;
    }

    return false;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          _reminderChannelName,
          channelDescription: 'Today\'s recitation and surah reminders',
          icon: _androidIcon,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
        ),
      );

  /// English title for timed-surah notifications (`Sura.EngName` when loaded).
  static String _surahNotifyTitle(RecommendedSurah surah) {
    final en = QuranMetadata.surahOrNull(surah.surah)?.englishName.trim();
    if (en != null && en.isNotEmpty) return en;
    return surah.titleUr;
  }

  Future<NotificationDetails> _namazDetails() async {
    if (!(_settings?.azaanEnabled ?? true)) return _details;

    final azaan = AzaanCatalog.byId(_settings?.azaanId);
    final channelId = 'com.quran_app.namaz_azaan_${azaan.id}';
    final sound = RawResourceAndroidNotificationSound(azaan.androidRawName);

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          _namazChannelName,
          description: 'Namaz start with azaan',
          importance: Importance.high,
          playSound: true,
          sound: sound,
        ),
      );
    }

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _namazChannelName,
        channelDescription: 'Namaz start with azaan',
        icon: _androidIcon,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        playSound: true,
        sound: sound,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        sound: azaan.iosSoundFile,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  /// Cancels and reschedules from the plan + prayer/learned surah windows.
  Future<bool> rescheduleAll({
    DailyPlan? plan,
    LearnedNotifyStore? learnedNotifyStore,
    bool confirm = false,
    int? confirmSurah,
    int? confirmLearnedMinutes,
  }) async {
    if (kIsWeb) {
      debugPrint('Notifications: skipped on web (no OS local notifications).');
      return false;
    }
    if (!_ready) await initialize();

    final allowed = await _ensurePermission(requestExact: true);
    if (!allowed) {
      debugPrint('Notifications: permission denied; left existing schedule.');
      return false;
    }

    await _plugin.cancel(_confirmId);
    await _plugin.cancel(_dailyId);
    for (var i = 0; i < 64; i++) {
      await _plugin.cancel(_timedBaseId + i);
    }
    for (var i = 0; i < 40; i++) {
      await _plugin.cancel(_prayerBaseId + i);
    }

    DateTime? nextDaily;
    if (plan != null && plan.reminderEnabled) {
      nextDaily = await _scheduleDailyReminder(plan);
    }

    final learned = learnedNotifyStore == null
        ? <int, int>{}
        : await learnedNotifyStore.loadAll();
    final nextSurah = await _scheduleTimedSurahs(learned);
    final prayerCount = await _schedulePrayerStarts();

    assert(() {
      debugPrint(
        'Notifications: scheduled '
        'daily=${nextDaily != null} '
        'nextSurah=$nextSurah '
        'prayers=$prayerCount '
        'coords=${PrayerTimeService.instance.hasCoords} '
        'exact=${_androidMode == AndroidScheduleMode.exactAllowWhileIdle}',
      );
      return true;
    }());

    if (confirm) {
      await _showConfirm(
        plan: plan,
        nextDaily: nextDaily,
        confirmSurah: confirmSurah,
        confirmLearnedMinutes: confirmLearnedMinutes,
        nextSurahFallback: nextSurah,
      );
    }
    return true;
  }

  Future<void> _showConfirm({
    DailyPlan? plan,
    DateTime? nextDaily,
    int? confirmSurah,
    int? confirmLearnedMinutes,
    DateTime? nextSurahFallback,
  }) async {
    String title = 'Reminder';
    String body = 'Reminder is set.';

    if (confirmSurah != null) {
      final surah = OccasionSurahs.byId(confirmSurah) ??
          RecommendedSurahResolver.resolve();
      final title = _surahNotifyTitle(surah);
      DateTime? next;
      if (confirmLearnedMinutes != null) {
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1));
        next = resolveSurahNotifyTime(
          surah: confirmSurah,
          day: day,
          learnedMinutes: {confirmSurah: confirmLearnedMinutes},
          prayers: PrayerTimeService.instance.timesFor(day),
        );
      }
      next ??= nextSurahFallback;
      if (next != null) {
        body = 'Next reminder for $title: ${formatClockUr(next)}';
      } else {
        body = 'Reminder set for $title.';
      }
    } else if (plan != null && plan.reminderEnabled && nextDaily != null) {
      body =
          'Next today\'s recitation reminder: ${formatClockUr(nextDaily)}';
    }

    await _plugin.show(
      _confirmId,
      title,
      body,
      _details,
      payload: confirmSurah != null
          ? NotificationRoute.surahPayload(confirmSurah)
          : NotificationRoute.todaysRecitationPayload,
    );
  }

  Future<DateTime> _scheduleDailyReminder(DailyPlan plan) async {
    final next = _nextInstanceOfTime(plan.hour24, plan.minute);
    await _plugin.zonedSchedule(
      _dailyId,
      'Today\'s recitation',
      'It is time for today\'s recitation.',
      next,
      _details,
      androidScheduleMode: _androidMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: NotificationRoute.todaysRecitationPayload,
    );
    return next;
  }

  Future<DateTime?> _scheduleTimedSurahs(Map<int, int> learned) async {
    final now = tz.TZDateTime.now(tz.local);
    var slot = 0;
    DateTime? firstUpcoming;

    Future<void> scheduleOne(
      DateTime localWhen,
      RecommendedSurah surah,
    ) async {
      final when = tz.TZDateTime.from(localWhen, tz.local);
      if (!when.isAfter(now)) return;
      final title = _surahNotifyTitle(surah);
      await _plugin.zonedSchedule(
        _timedBaseId + slot,
        title,
        'Time to read $title (${surah.reasonUr}).',
        when,
        _details,
        androidScheduleMode: _androidMode,
        payload: NotificationRoute.surahPayload(surah.surah),
      );
      slot++;
      firstUpcoming ??= localWhen;
    }

    for (var day = 0; day < 7; day++) {
      final base = DateTime(now.year, now.month, now.day)
          .add(Duration(days: day));
      final prayers = PrayerTimeService.instance.timesFor(base);

      final yasinWhen = resolveSurahNotifyTime(
        surah: RecommendedSurahResolver.yasin.surah,
        day: base,
        learnedMinutes: learned,
        prayers: prayers,
      );
      if (yasinWhen != null) {
        await scheduleOne(yasinWhen, RecommendedSurahResolver.yasin);
      }

      if (shouldNotifyKahfAtMorning(
        DateTime(base.year, base.month, base.day, 6),
      )) {
        final kahf = DateTime(
          base.year,
          base.month,
          base.day,
          RecommendedSurahResolver.yasinStartHour,
        );
        await scheduleOne(kahf, RecommendedSurahResolver.kahf);
      }

      final waqiahWhen = resolveSurahNotifyTime(
        surah: RecommendedSurahResolver.waqiah.surah,
        day: base,
        learnedMinutes: learned,
        prayers: prayers,
      );
      if (waqiahWhen != null) {
        await scheduleOne(waqiahWhen, RecommendedSurahResolver.waqiah);
      }

      final mulkWhen = resolveSurahNotifyTime(
        surah: RecommendedSurahResolver.mulk.surah,
        day: base,
        learnedMinutes: learned,
        prayers: prayers,
      );
      if (mulkWhen != null) {
        await scheduleOne(mulkWhen, RecommendedSurahResolver.mulk);
      }

      final dukhan = DateTime(
        base.year,
        base.month,
        base.day,
        RecommendedSurahResolver.dukhanStartHour,
      );
      if (shouldNotifyDukhanAt(dukhan)) {
        await scheduleOne(dukhan, RecommendedSurahResolver.dukhan);
      }
    }

    return firstUpcoming;
  }

  /// Returns how many namaz alerts were queued (0 if no location yet).
  Future<int> _schedulePrayerStarts() async {
    final now = tz.TZDateTime.now(tz.local);
    var slot = 0;
    final namazDetails = await _namazDetails();

    if (!PrayerTimeService.instance.hasCoords) {
      debugPrint('Notifications: no location — namaz alerts not scheduled.');
      return 0;
    }

    for (var day = 0; day < 7; day++) {
      final base = DateTime(now.year, now.month, now.day)
          .add(Duration(days: day));
      final prayers = PrayerTimeService.instance.timesFor(base);
      if (prayers == null) continue;

      for (final name in NamazName.values) {
        final localWhen = prayers.startOf(name);
        final when = tz.TZDateTime.from(localWhen, tz.local);
        if (!when.isAfter(now)) continue;
        if (slot >= 40) return slot;
        await _plugin.zonedSchedule(
          _prayerBaseId + slot,
          'Prayer time',
          'It is time for ${name.labelUr}.',
          when,
          namazDetails,
          androidScheduleMode: _androidMode,
          payload: NotificationRoute.hubPayload,
        );
        slot++;
      }
    }
    return slot;
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
