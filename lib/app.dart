import 'dart:async';

import 'package:arabic_text_justification/arabic_text_justification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/app_theme.dart';
import 'data/mushaf_divisions.dart';
import 'data/quran_database.dart';
import 'data/quran_metadata.dart';
import 'quran/rendering/kfgqpc_font_path.dart';
import 'quran/rendering/kfgqpc_font_scope.dart';
import 'reader/app_notification_scheduler.dart';
import 'reader/bookmark_store.dart';
import 'reader/daily_plan.dart';
import 'reader/index_bookmark_store.dart';
import 'reader/learned_notify_store.dart';
import 'reader/pinned_surah_store.dart';
import 'reader/prayer_time_service.dart';
import 'reader/profile_manager.dart';
import 'reader/quran_reader_controller.dart';
import 'reader/quran_reader_screen.dart';
import 'reader/reader_nav_scope.dart';
import 'reader/reader_route_observer.dart';
import 'reader/reader_settings.dart';
import 'reader/reading_position_store.dart';
import 'reader/tilawat_position_store.dart';

class QuranApp extends StatefulWidget {
  const QuranApp({super.key});

  @override
  State<QuranApp> createState() => _QuranAppState();
}

class _QuranAppState extends State<QuranApp> {
  final ProfileManager _profiles = ProfileManager();
  final ReaderSettings _settings = ReaderSettings();

  /// Placeholder id until [ProfileManager.initialize] finishes.
  late final ReadingPositionStore _positionStore =
      ReadingPositionStore(profileId: '_boot');
  late final BookmarkStore _bookmarkStore = BookmarkStore(profileId: '_boot');
  late final IndexBookmarkStore _indexBookmarkStore =
      IndexBookmarkStore(profileId: '_boot');
  late final DailyPlanStore _dailyPlanStore =
      DailyPlanStore(profileId: '_boot');
  late final PinnedSurahStore _pinnedSurahStore =
      PinnedSurahStore(profileId: '_boot');
  late final TilawatPositionStore _tilawatPositionStore =
      TilawatPositionStore(profileId: '_boot');
  late final LearnedNotifyStore _learnedNotifyStore =
      LearnedNotifyStore(profileId: '_boot');
  late final QuranReaderController _controller =
      QuranReaderController(positionStore: _positionStore);
  final ReaderNavController _nav = ReaderNavController();
  late final ReaderRouteObserver _routeObserver = ReaderRouteObserver(_nav);

  bool _ready = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_persistSettingsIfNeeded);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _revealFlutterSplash();

      final fontWarm = KfgqpcFontPath.resolveAll().then((paths) async {
        await Future.wait([
          for (final path in paths.values) warmJustificationShaper(path),
        ]);
      });
      final metaWarm = QuranMetadata.load();

      await QuranDatabase.warmUp();
      final divisionsWarm = MushafDivisions.load();
      await _profiles.initialize();
      final id = _profiles.activeProfileId!;
      _bindStores(id);
      await _settings.load(id);
      _controller.prepareScript(_settings.mushafScript);
      AppNotificationScheduler.instance.bindSettings(_settings);
      _applyPrayerCalculation();

      await Future.wait<void>([
        fontWarm,
        metaWarm,
        divisionsWarm,
        _controller.initialize(),
      ]);

      if (!mounted) return;
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_rescheduleNotifications());
      });
    } finally {
      FlutterNativeSplash.remove();
    }
  }

  /// Decodes the splash PNG into the image cache, then allows the first
  /// Flutter frame so [_BootstrapSplash] replaces the OS splash.
  Future<void> _revealFlutterSplash() async {
    final stream = _BootstrapSplash.image.resolve(
      const ImageConfiguration(devicePixelRatio: 3),
    );
    final done = Completer<void>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo _, bool _) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _, StackTrace? _) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      },
    );
    stream.addListener(listener);
    try {
      await done.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      stream.removeListener(listener);
    }
    if (!mounted) return;
    FlutterNativeSplash.remove();
  }

  Future<void> _rescheduleNotifications() async {
    try {
      await AppNotificationScheduler.instance.initialize();
      _applyPrayerCalculation();
      await PrayerTimeService.instance.ensureLocation();
      final plan = await _dailyPlanStore.load();
      await AppNotificationScheduler.instance.rescheduleAll(
        plan: plan,
        learnedNotifyStore: _learnedNotifyStore,
      );
    } catch (e, st) {
      debugPrint('Notification schedule failed: $e\n$st');
    }
  }

  void _applyPrayerCalculation() {
    PrayerTimeService.instance.applyCalculation(
      methodId: _settings.prayerMethodId,
      fiqahId: _settings.prayerFiqahId,
    );
  }

  void _bindStores(String profileId) {
    _positionStore.bind(profileId);
    _bookmarkStore.bind(profileId);
    _indexBookmarkStore.bind(profileId);
    _dailyPlanStore.bind(profileId);
    _pinnedSurahStore.bind(profileId);
    _tilawatPositionStore.bind(profileId);
    _learnedNotifyStore.bind(profileId);
  }

  void _persistSettingsIfNeeded() {
    if (!_ready || _switching || _settings.applyingProfile) return;
    final id = _profiles.activeProfileId;
    if (id == null) return;
    _settings.save(id);
    if (_controller.mushafScript != _settings.mushafScript) {
      unawaited(_controller.setMushafScript(_settings.mushafScript));
    }
  }

  /// Saves the current profile, activates [id], and reloads prefs + position.
  Future<({int surah, int ayah, bool openAtSurahHeader})?> switchProfile(
    String id,
  ) async {
    if (!_ready || _switching) return null;
    final current = _profiles.activeProfileId;
    if (current == null || current == id) return null;

    _switching = true;
    try {
      await _settings.save(current);
      await _profiles.select(id);
      _bindStores(id);
      await _settings.load(id);
      await _controller.setMushafScript(_settings.mushafScript);
      await _rescheduleNotifications();
      return await _controller.reloadSavedPosition();
    } finally {
      _switching = false;
    }
  }

  /// Deletes [id]. If the active profile is removed, reloads the replacement
  /// and returns its reading position so the reader can jump.
  Future<({int surah, int ayah, bool openAtSurahHeader})?> deleteProfile(
    String id,
  ) async {
    if (!_ready || _switching) return null;
    final current = _profiles.activeProfileId;
    final switchedTo = await _profiles.delete(id);
    if (switchedTo == null || switchedTo == current) return null;
    _switching = true;
    try {
      _bindStores(switchedTo);
      await _settings.load(switchedTo);
      await _controller.setMushafScript(_settings.mushafScript);
      await _rescheduleNotifications();
      return await _controller.reloadSavedPosition();
    } finally {
      _switching = false;
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_persistSettingsIfNeeded);
    _settings.dispose();
    _controller.dispose();
    _profiles.dispose();
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const _BootstrapSplash();
    }

    return ListenableBuilder(
      listenable: Listenable.merge([_settings, _profiles, _controller]),
      child: QuranReaderScreen(
        controller: _controller,
        settings: _settings,
        profiles: _profiles,
        bookmarkStore: _bookmarkStore,
        indexBookmarkStore: _indexBookmarkStore,
        positionStore: _positionStore,
        dailyPlanStore: _dailyPlanStore,
        pinnedSurahStore: _pinnedSurahStore,
        tilawatPositionStore: _tilawatPositionStore,
        learnedNotifyStore: _learnedNotifyStore,
        readerNav: _nav,
        onSwitchProfile: switchProfile,
        onDeleteProfile: deleteProfile,
      ),
      builder: (context, child) {
        return KfgqpcFontScope(
          script: _controller.mushafScript,
          child: MaterialApp(
            title: 'Quran with English',
            debugShowCheckedModeBanner: false,
            themeMode: _settings.themeMode,
            theme: AppTheme.build(Brightness.light),
            darkTheme: AppTheme.build(Brightness.dark),
            navigatorObservers: [_routeObserver],
            locale: const Locale('en', 'US'),
            builder: (context, navigator) {
              return Directionality(
                textDirection: TextDirection.ltr,
                child: ReaderNavScope(
                  settings: _settings,
                  profileName: _profiles.activeProfile?.name ?? 'Profile',
                  nav: _nav,
                  child: navigator ?? const SizedBox.shrink(),
                ),
              );
            },
            home: child,
          ),
        );
      },
    );
  }
}

/// Full-screen splash artwork. Android 12+ cannot show this JPEG as the
/// system splash, so Flutter paints it until bootstrap finishes.
class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash();

  static const image = AssetImage('assets/splash/splash_screen.png');
  static const _color = Color(0xFFE6500A);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _color,
      child: SizedBox.expand(
        child: Image(
          image: image,
          fit: BoxFit.fill,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
