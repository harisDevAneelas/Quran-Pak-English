import 'dart:async';

import 'package:arabic_text_justification/arabic_text_justification.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/app_theme.dart';
import '../core/mushaf_layout.dart';
import '../core/mushaf_script.dart';
import '../quran/rendering/kfgqpc_font_scope.dart';
import '../data/ayah_repeat_mode.dart';
import '../data/mushaf_divisions.dart';
import '../data/quran_metadata.dart';
import '../data/quran_models.dart';
import '../data/reciter_catalog.dart';
import '../data/translation_catalog.dart';
import '../data/translation_repository.dart';
import '../data/verse_collection_repository.dart';
import '../data/verse_collections.dart';
import 'ayah_audio_controller.dart';
import 'ayah_audio_handler.dart';
import 'app_notification_scheduler.dart';
import 'bookmark_store.dart';
import 'daily_plan.dart';
import 'index_bookmark_store.dart';
import 'learned_notify_store.dart';
import 'notification_route.dart';
import 'pinned_surah_store.dart';
import 'playing_ayah_follow.dart';
import 'profile_manager.dart';
import 'quran_reader_controller.dart';
import 'reader_nav_scope.dart';
import 'reader_routes.dart';
import 'reader_settings.dart';
import 'reading_position_store.dart';
import 'tilawat_position_store.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/daily_recitation_screen.dart';
import 'screens/hub_menu_screen.dart';
import 'screens/mushaf_script_picker_screen.dart';
import 'screens/option_list_screen.dart';
import 'screens/para_grid_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/audio_language_list_screen.dart';
import 'screens/reciter_list_screen.dart';
import 'screens/surah_about_screen.dart';
import 'screens/surah_grid_screen.dart';
import 'screens/surah_search_screen.dart';
import 'screens/ayah_translation_tafsir_screen.dart';
import 'screens/todays_recitation_screen.dart';
import 'screens/verse_collection_screen.dart';
import 'screens/word_by_word_screen.dart';
import 'prayer_time_service.dart';
import 'widgets/ayah_actions_popup.dart';
import 'widgets/location_consent_dialog.dart';
import 'widgets/mushaf_pinch_zoom.dart';
import 'widgets/playing_ayah_bar.dart';
import 'widgets/quran_ayah_widget.dart';
import 'widgets/ruku_info_popup.dart';
import 'widgets/reader_sidebar.dart';
import 'widgets/surah_ayah_picker_sheet.dart';
import 'widgets/surah_header_banner.dart';
import 'widgets/tilawat_order_dialog.dart';

class QuranReaderScreen extends StatefulWidget {
  const QuranReaderScreen({
    super.key,
    required this.controller,
    required this.settings,
    required this.profiles,
    required this.bookmarkStore,
    required this.indexBookmarkStore,
    required this.positionStore,
    required this.dailyPlanStore,
    required this.pinnedSurahStore,
    required this.tilawatPositionStore,
    required this.learnedNotifyStore,
    required this.readerNav,
    required this.onSwitchProfile,
    required this.onDeleteProfile,
  });

  final QuranReaderController controller;
  final ReaderSettings settings;
  final ProfileManager profiles;
  final BookmarkStore bookmarkStore;
  final IndexBookmarkStore indexBookmarkStore;
  final ReadingPositionStore positionStore;
  final DailyPlanStore dailyPlanStore;
  final PinnedSurahStore pinnedSurahStore;
  final TilawatPositionStore tilawatPositionStore;
  final LearnedNotifyStore learnedNotifyStore;
  final ReaderNavController readerNav;
  final Future<({int surah, int ayah, bool openAtSurahHeader})?> Function(
    String id,
  ) onSwitchProfile;
  final Future<({int surah, int ayah, bool openAtSurahHeader})?> Function(
    String id,
  ) onDeleteProfile;

  @override
  State<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends State<QuranReaderScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final TranslationRepository _translations = TranslationRepository();
  final AyahAudioController _audio = AyahAudioController();
  bool _audioSessionReady = false;

  int? _audioScrollSurah;
  int? _audioScrollAyah;
  bool _scrollForward = true;
  bool _shapeWarmScheduled = false;
  bool _audioErrorShown = false;

  /// Guards snap / jump so programmatic [scrollTo] does not re-enter snap.
  bool _isSnapping = false;

  /// Orientation restore: last top ayah list index (not Surah header).
  int? _topVisibleAyahItemIndex;
  Orientation? _lastOrientation;
  bool _isRestoringOrientation = false;

  /// Pinch-zoom anchor: keep this list index under the fingers while size changes.
  final GlobalKey _mushafPinchKey = GlobalKey();
  int? _pinchAnchorIndex;
  double? _pinchAnchorAlignment;
  bool _pinchActive = false;

  /// After a mushaf-script remount, restore this list index + viewport alignment.
  int? _scriptAnchorIndex;
  double _scriptAnchorAlignment = 0;
  bool _translationsReady = false;
  List<String> _loadedTranslatorIds = const [];
  int _translationLoadGen = 0;

  /// Playing ayah for row highlight. Separate from the body [ListenableBuilder]
  /// so audio ticks do not rebuild the mushaf list.
  final ValueNotifier<({int? surah, int? ayah})> _playingAyah =
      ValueNotifier((surah: null, ayah: null));

  /// User left the playing ayah (scroll or another page). Follow stays off.
  final ValueNotifier<bool> _followDetached = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureNamazLocationOnOpen());
    });
    widget.controller.initialize();
    widget.readerNav.attach(
      jumpToSurah: _jumpToSurahFromNav,
      jumpToAyah: _jumpToAyahFromNav,
      openDestination: _onSidebarDestination,
      onPlayingBarTap: _onPlayingBarTapped,
      onPlayingBarPlay: _onBottomPlayPressed,
      onPlayingBarClose: _onPlayingBarClosed,
    );
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    widget.settings.addListener(_onSettingsChanged);
    _audio.addListener(_onAudioChanged);
    widget.readerNav.pageAboveHome.addListener(_onPageAboveHome);
    NotificationRoute.changes.addListener(_consumeNotificationRoute);
    _initBackgroundAudio();
    _reloadTranslations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeNotificationRoute();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handleOrientationChange(MediaQuery.orientationOf(context));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      PrayerTimeService.instance.endForegroundLocation();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!widget.settings.backgroundRecitation && _audio.playing) {
        unawaited(_audio.pausePlayback());
      }
    }
    if (state == AppLifecycleState.resumed) {
      _consumeNotificationRoute();
      unawaited(() async {
        await PrayerTimeService.instance.ensureLocation();
        if (!mounted) return;
        if (PrayerTimeService.instance.hasCoords) {
          await _rescheduleNotificationsAfterLocation();
        }
      }());
    }
  }

  Future<void> _ensureNamazLocationOnOpen() async {
    if (!mounted || kIsWeb) return;
    final service = PrayerTimeService.instance;
    if (await service.shouldAskLocationConsentOnOpen()) {
      if (!mounted) return;
      final allowed = await showLocationConsentDialog(context);
      await service.markLocationConsentAsked();
      if (!mounted) return;
      if (allowed) {
        await service.beginForegroundLocation(afterUserConsent: true);
        if (!mounted) return;
        await _rescheduleNotificationsAfterLocation();
      }
      return;
    }
    final hadCoords = service.hasCoords;
    await service.ensureLocation();
    if (!mounted) return;
    if (service.hasCoords && !hadCoords) {
      await _rescheduleNotificationsAfterLocation();
    }
  }

  Future<void> _rescheduleNotificationsAfterLocation() async {
    if (kIsWeb) return;
    try {
      final plan = await widget.dailyPlanStore.load();
      await AppNotificationScheduler.instance.rescheduleAll(
        plan: plan,
        learnedNotifyStore: widget.learnedNotifyStore,
      );
    } catch (e, st) {
      debugPrint('Location notify reschedule failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.readerNav.detach();
    widget.readerNav.pageAboveHome.removeListener(_onPageAboveHome);
    NotificationRoute.changes.removeListener(_consumeNotificationRoute);
    _audio.removeListener(_onAudioChanged);
    AyahAudioServiceHost.handler?.detach();
    _audio.dispose();
    widget.settings.removeListener(_onSettingsChanged);
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    widget.controller.flushPositionSave();
    _playingAyah.dispose();
    _followDetached.dispose();
    super.dispose();
  }

  Future<void> _initBackgroundAudio() async {
    await _syncBackgroundRecitation();
  }

  Future<void> _ensureAudioSession() async {
    if (kIsWeb || _audioSessionReady) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _audioSessionReady = true;
    } catch (e, st) {
      debugPrint('Audio session configure failed: $e\n$st');
    }
  }

  Future<void> _syncBackgroundRecitation() async {
    if (kIsWeb || !widget.settings.backgroundRecitation) {
      AyahAudioServiceHost.handler?.setBackgroundEnabled(false);
      return;
    }
    await _ensureAudioSession();
    final handler = await AyahAudioServiceHost.ensureInitialized();
    if (!mounted || handler == null) return;
    handler.attach(_audio);
    handler.setBackgroundEnabled(true);
  }

  void _consumeNotificationRoute() {
    if (!mounted) return;
    final target = NotificationRoute.take();
    if (target == null) return;
    final surah = target.surah;
    if (surah != null) {
      unawaited(_learnSurahOpenFromNotification(surah));
      _jumpToSurahFromNav(surah);
      return;
    }
    if (target.hub) {
      _openHubMenu();
      return;
    }
    if (target.todaysRecitation) {
      _openTodaysRecitation();
    }
  }

  Future<void> _learnSurahOpenFromNotification(int surah) async {
    try {
      await widget.learnedNotifyStore.recordOpenNow(surah);
      final learnedMinutes = await widget.learnedNotifyStore.loadMinutes(surah);
      final plan = await widget.dailyPlanStore.load();
      await AppNotificationScheduler.instance.rescheduleAll(
        plan: plan,
        learnedNotifyStore: widget.learnedNotifyStore,
        confirm: true,
        confirmSurah: surah,
        confirmLearnedMinutes: learnedMinutes,
      );
    } catch (e, st) {
      debugPrint('Learn notify failed: $e\n$st');
    }
  }

  void _onSettingsChanged() {
    unawaited(_syncBackgroundRecitation());
    if (widget.settings.applyingProfile) {
      if (_audio.isActive) unawaited(_audio.stop());
    } else if (_audio.isActive) {
      _audio.ayahRepeatMode = widget.settings.ayahRepeatMode;
      final expectedLanguage = _effectiveAudioLanguageId();
      final voiceChanged = _audio.reciterId != widget.settings.reciterId ||
          _audio.tilawatOrder != widget.settings.tilawatOrder ||
          _audio.audioLanguageId != expectedLanguage;
      if (voiceChanged) {
        if (_audio.playing) {
          unawaited(_playAyah(_audio.surah!, _audio.ayah!));
        } else {
          unawaited(_audio.stop());
        }
      }
    }
    final ids = List<String>.from(widget.settings.translatorIds);
    final needsReload = ids.any((id) => !_translations.isLoaded(id));
    if (needsReload) {
      _reloadTranslations();
    } else if (mounted) {
      setState(() {
        _translationsReady = ids.isNotEmpty;
        _loadedTranslatorIds = ids;
      });
    }
  }

  void _onAudioChanged() {
    if (!mounted) return;
    if (_audio.failed && !_audioErrorShown) {
      _audioErrorShown = true;
      final surah = _audio.surah;
      final ayah = _audio.ayah;
      final ref = surah == null || ayah == null
          ? ''
          : ' (${QuranMetadata.nameArOrEmpty(surah)} · $ayah)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recitation is not available for this ayah$ref',
            textDirection: TextDirection.ltr,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (!_audio.failed) _audioErrorShown = false;

    final nextPlaying = (surah: _audio.surah, ayah: _audio.ayah);
    if (_playingAyah.value != nextPlaying) {
      _playingAyah.value = nextPlaying;
    }

    final surah = _audio.surah;
    final ayah = _audio.ayah;
    if (surah != null &&
        ayah != null &&
        (surah != _audioScrollSurah || ayah != _audioScrollAyah)) {
      _audioScrollSurah = surah;
      _audioScrollAyah = ayah;
      if (shouldFollowPlayingAyah(
        followDetached: _followDetached.value,
        pageAboveHome: widget.readerNav.pageAboveHome.value,
      )) {
        _jumpToAyah(surah, ayah);
      }
    }
    if (!_audio.isActive) {
      _audioScrollSurah = null;
      _audioScrollAyah = null;
      if (_followDetached.value) _followDetached.value = false;
    } else {
      _syncFollowDetached();
    }
    _publishPlayingBar();
  }

  void _publishPlayingBar() {
    final surah = _audio.surah;
    final ayah = _audio.ayah;
    if (!_audio.isActive || surah == null || ayah == null) {
      widget.readerNav.publishPlayingBar(null);
      return;
    }
    widget.readerNav.publishPlayingBar(
      PlayingAyahBarSession(
        surah: surah,
        ayah: ayah,
        playing: _audio.playing,
        loading: _audio.loading,
      ),
    );
  }

  Future<void> _reloadTranslations() async {
    final gen = ++_translationLoadGen;
    final ids = List<String>.from(widget.settings.translatorIds);
    debugPrint('Loading translations: $ids');

    final loaded = <String>[];
    for (final id in ids) {
      try {
        await _translations.ensureLoaded(id);
        if (_translations.isLoaded(id)) loaded.add(id);
      } catch (error, stack) {
        debugPrint('Translation failed for $id: $error\n$stack');
      }
    }

    if (!mounted || gen != _translationLoadGen) return;
    setState(() {
      _loadedTranslatorIds = loaded;
      _translationsReady = loaded.isNotEmpty;
    });
    debugPrint('Translations ready: $_loadedTranslatorIds');
  }

  /// Current Surah = greatest header whose list index is `<=` top visible item.
  /// Also tracks the top visible ayah index for orientation restore.
  void _onItemPositionsChanged() {
    if (widget.controller.state != QuranLoadState.ready) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final topIndex = _topVisibleItemIndex(positions);
    if (topIndex == null) return;

    final slot = MushafLayout.slotAt(topIndex);
    final surah = switch (slot) {
      MushafHeaderSlot(:final surah) => surah,
      MushafAyahSlot(:final surah) => surah,
    };
    final ayah = switch (slot) {
      MushafHeaderSlot() => 1,
      MushafAyahSlot(:final ayah) => ayah,
    };

    widget.controller.updateVisibleAyah(surah, ayah);

    if (!_isRestoringOrientation) {
      final ayahItemIndex = _topVisibleAyahItemIndexFrom(positions);
      if (ayahItemIndex != null) {
        _topVisibleAyahItemIndex = ayahItemIndex;
      }
    }
    _syncFollowDetached();
  }

  /// Smallest [ItemPosition.itemLeadingEdge] among items intersecting the
  /// viewport — that item is treated as the top of the screen.
  int? _topVisibleItemIndex(Iterable<ItemPosition> positions) {
    ItemPosition? top;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0) continue;
      if (position.itemLeadingEdge >= 1) continue;
      if (top == null || position.itemLeadingEdge < top.itemLeadingEdge) {
        top = position;
      }
    }
    return top?.index;
  }

  /// Topmost visible list index that is an ayah row (orientation anchor).
  int? _topVisibleAyahItemIndexFrom(Iterable<ItemPosition> positions) {
    ItemPosition? topAyah;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0) continue;
      if (position.itemLeadingEdge >= 1) continue;
      if (position.index < 0 || position.index >= MushafLayout.itemCount) {
        continue;
      }
      if (MushafLayout.slotAt(position.index) is! MushafAyahSlot) continue;
      if (topAyah == null ||
          position.itemLeadingEdge < topAyah.itemLeadingEdge) {
        topAyah = position;
      }
    }
    return topAyah?.index;
  }

  void _handleOrientationChange(Orientation orientation) {
    if (_lastOrientation == null) {
      _lastOrientation = orientation;
      return;
    }
    if (_lastOrientation == orientation) return;

    final savedIndex = _topVisibleAyahItemIndex;
    _lastOrientation = orientation;

    if (savedIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreTopAyahAfterOrientation(savedIndex);
    });
  }

  Future<void> _restoreTopAyahAfterOrientation(int index) async {
    if (!_itemScrollController.isAttached) return;
    if (_isRestoringOrientation) return;
    if (index < 0 || index >= MushafLayout.itemCount) return;
    if (MushafLayout.slotAt(index) is! MushafAyahSlot) return;

    _isRestoringOrientation = true;
    _isSnapping = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(index: index, alignment: 0);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      _isRestoringOrientation = false;
      _isSnapping = false;
    }
  }

  /// Soft-lock a Surah header that is already near the viewport top.
  Future<void> _snapVisibleSurahHeader() async {
    if (_isSnapping || _isRestoringOrientation) return;
    if (!_itemScrollController.isAttached) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    ItemPosition? candidate;

    for (final position in positions) {
      if (position.index < 0 || position.index >= MushafLayout.itemCount) {
        continue;
      }

      if (MushafLayout.slotAt(position.index) is! MushafHeaderSlot) continue;

      if (position.itemLeadingEdge >= -0.05 &&
          position.itemLeadingEdge <= 0.18) {
        if (candidate == null ||
            position.itemLeadingEdge.abs() < candidate.itemLeadingEdge.abs()) {
          candidate = position;
        }
      }
    }

    if (candidate == null) return;
    if (candidate.itemLeadingEdge.abs() < 0.01) return;

    _isSnapping = true;
    try {
      await _itemScrollController.scrollTo(
        index: candidate.index,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isSnapping = false;
    }
  }

  /// `surah → MushafLayout header index → scrollTo`.
  Future<void> _jumpToSurah(int surah) async {
    if (_isSnapping || _isRestoringOrientation) return;

    if (!widget.controller.isFullyLoaded) {
      await widget.controller.ensureSurahAvailable(surah);
      if (!mounted) return;
    }

    final index = widget.controller.itemIndexForSurah(surah);
    if (!_itemScrollController.isAttached) return;

    widget.controller.updateVisibleAyah(surah, 1);

    _isSnapping = true;
    try {
      await _itemScrollController.scrollTo(
        index: index,
        alignment: 0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isSnapping = false;
    }
  }

  /// `surah+ayah → MushafLayout ayah index → scrollTo`.
  Future<void> _jumpToAyah(int surah, int ayah, {bool animate = true}) async {
    if (_isSnapping || _isRestoringOrientation) return;

    if (!widget.controller.isFullyLoaded &&
        !widget.controller.hasAyah(surah, ayah)) {
      await widget.controller.ensureAyahAvailable(surah, ayah);
      if (!mounted) return;
    }

    final index = widget.controller.itemIndexForAyah(surah, ayah);
    if (!_itemScrollController.isAttached) return;

    widget.controller.updateVisibleAyah(surah, ayah);

    _isSnapping = true;
    try {
      if (!animate) {
        _itemScrollController.jumpTo(index: index, alignment: 0);
        return;
      }
      await _itemScrollController.scrollTo(
        index: index,
        alignment: 0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isSnapping = false;
    }
  }

  void _popToReader() {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.popUntil((route) => route.isFirst);
    _scaffoldKey.currentState?.closeDrawer();
  }

  bool _popForMainOpen(String mainName) {
    final nav = Navigator.of(context);
    var kept = false;
    nav.popUntil((route) {
      if (route.settings.name == mainName) {
        kept = true;
        return true;
      }
      return route.isFirst;
    });
    return kept;
  }

  void _popToNearestMainOrRoot() {
    Navigator.of(context).popUntil((route) {
      if (ReaderRoutes.isMainName(route.settings.name)) return true;
      return route.isFirst;
    });
  }

  void _afterStackSettle(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  void _jumpToSurahFromNav(int surah) {
    _popToReader();
    _afterStackSettle(() => _jumpToSurah(surah));
  }

  void _jumpToAyahFromNav(int surah, int ayah) {
    _popToReader();
    _afterStackSettle(() => _jumpToAyah(surah, ayah));
  }

  void _onPlayingBarTapped() {
    final surah = _audio.surah;
    final ayah = _audio.ayah;
    if (surah == null || ayah == null) return;
    _followDetached.value = false;
    _jumpToAyahFromNav(surah, ayah);
  }

  void _onPlayingBarClosed() {
    unawaited(_audio.stop());
  }

  void _onPageAboveHome() {
    _syncFollowDetached();
  }

  void _syncFollowDetached() {
    if (!_audio.isActive) {
      if (_followDetached.value) _followDetached.value = false;
      return;
    }
    if (widget.readerNav.pageAboveHome.value) return;
    if (_isPlayingAyahVisible()) {
      if (_followDetached.value) _followDetached.value = false;
    } else if (!_isSnapping && !_isRestoringOrientation) {
      if (!_followDetached.value) _followDetached.value = true;
    }
  }

  bool _isPlayingAyahVisible() {
    final surah = _audio.surah;
    final ayah = _audio.ayah;
    if (surah == null || ayah == null) return false;
    final index = widget.controller.itemIndexForAyah(surah, ayah);
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index != index) continue;
      if (position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openSurahAyahPicker() async {
    final picked = await showSurahAyahPickerSheet(
      context: context,
      initialSurah: widget.controller.currentSurah,
      initialAyah: widget.controller.currentAyah,
    );
    if (!mounted || picked == null) return;
    await _jumpToAyah(picked.surah, picked.ayah);
  }

  void _openTodaysRecitation() {
    if (_popForMainOpen(ReaderRoutes.todaysRecitation)) return;
    _afterStackSettle(() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: ReaderRoutes.todaysRecitation),
          builder: (_) => TodaysRecitationScreen(
            settings: widget.settings,
            dailyPlanStore: widget.dailyPlanStore,
            tilawatPositionStore: widget.tilawatPositionStore,
            profiles: widget.profiles,
            learnedNotifyStore: widget.learnedNotifyStore,
          ),
        ),
      );
    });
  }

  void _openDailyArrangement() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DailyRecitationScreen(
          dailyPlanStore: widget.dailyPlanStore,
          profiles: widget.profiles,
          learnedNotifyStore: widget.learnedNotifyStore,
        ),
      ),
    );
  }

  void _openHubMenu() {
    if (_popForMainOpen(ReaderRoutes.hub)) return;
    _afterStackSettle(() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: ReaderRoutes.hub),
          builder: (_) => HubMenuScreen(
            pinnedSurahStore: widget.pinnedSurahStore,
            indexBookmarkStore: widget.indexBookmarkStore,
            onJumpToSurah: _jumpToSurahFromNav,
            onOpenManzilList: () {
              _openVerseCollectionById(VerseCollectionIds.manzil);
            },
            onOpenTodaysRecitation: _openTodaysRecitation,
            onOpenDailyArrangement: _openDailyArrangement,
            onOpenAyatEShifa: () {
              _openVerseCollectionById(VerseCollectionIds.shifa);
            },
            onOpenFortyRabbana: () {
              _openVerseCollectionById(VerseCollectionIds.rabbana);
            },
            onOpenRuqyahShariah: () {
              _openVerseCollectionById(VerseCollectionIds.ruqyah);
            },
            onLocationUpdated: _rescheduleNotificationsAfterLocation,
          ),
        ),
      );
    });
  }

  void _openVerseCollectionById(String listId) {
    unawaited(_pushVerseCollection(listId));
  }

  Future<void> _pushVerseCollection(String listId) async {
    final collection = await VerseCollectionRepository.load(listId);
    if (!mounted || collection == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerseCollectionScreen(
          collection: collection,
          settings: widget.settings,
        ),
      ),
    );
  }

  void _onSidebarDestination(SidebarDestination destination) {
    _scaffoldKey.currentState?.closeDrawer();
    _afterStackSettle(() => _openSidebarDestination(destination));
  }

  void _openSidebarDestination(SidebarDestination destination) {
    switch (destination) {
      case SidebarDestination.dailyRecitation:
        _openTodaysRecitation();
      case SidebarDestination.profiles:
        unawaited(_openProfiles());
      case SidebarDestination.shareApp:
        unawaited(_shareApp());
      case SidebarDestination.textSize:
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: false,
          builder: (context) =>
              TextSizeBottomSheet(settings: widget.settings),
        );
      case SidebarDestination.dailyArrangement:
        _openNestedFromDrawer(_openDailyArrangement);
      case SidebarDestination.surahList:
        _openNestedFromDrawer(_openSurahGrid);
      case SidebarDestination.paraList:
        _openNestedFromDrawer(_openParaGrid);
      case SidebarDestination.manzil:
        _openNestedFromDrawer(
          () => _openVerseCollectionById(VerseCollectionIds.manzil),
        );
      case SidebarDestination.search:
        _openNestedFromDrawer(() => unawaited(_openSearch()));
      case SidebarDestination.bookmarks:
        _openNestedFromDrawer(() => unawaited(_openBookmarks()));
      case SidebarDestination.reciter:
        _openNestedFromDrawer(() => unawaited(_openReciterPicker()));
      case SidebarDestination.audioLanguage:
        _openNestedFromDrawer(() => unawaited(_openAudioLanguagePicker()));
      case SidebarDestination.translator:
        _openNestedFromDrawer(() => unawaited(_openTranslatorPicker()));
      case SidebarDestination.mushafScript:
        _openNestedFromDrawer(_openMushafScriptPicker);
    }
  }

  void _openNestedFromDrawer(VoidCallback open) {
    _popToNearestMainOrRoot();
    _afterStackSettle(open);
  }

  void _openSurahGrid() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SurahGridScreen(
          indexBookmarkStore: widget.indexBookmarkStore,
          pinnedSurahStore: widget.pinnedSurahStore,
        ),
      ),
    );
  }

  void _openParaGrid() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParaGridScreen(
          indexBookmarkStore: widget.indexBookmarkStore,
        ),
      ),
    );
  }

  void _openMushafScriptPicker() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: ReaderRoutes.mushafScript),
        builder: (_) => MushafScriptPickerScreen(
          settings: widget.settings,
          apply: _applyMushafScript,
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    final picked = await Navigator.of(context).push<({int surah, int ayah})>(
      MaterialPageRoute(builder: (_) => const SurahSearchScreen()),
    );
    if (!mounted || picked == null) return;
    _jumpToAyahFromNav(picked.surah, picked.ayah);
  }

  Future<void> _openBookmarks() async {
    final picked = await Navigator.of(context).push<BookmarkJump>(
      MaterialPageRoute(
        builder: (_) => BookmarksScreen(
          bookmarkStore: widget.bookmarkStore,
          indexBookmarkStore: widget.indexBookmarkStore,
          pinnedSurahStore: widget.pinnedSurahStore,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked.openAtSurahHeader) {
      _jumpToSurahFromNav(picked.surah);
    } else {
      _jumpToAyahFromNav(picked.surah, picked.ayah);
    }
  }

  Future<void> _applyMushafScript(MushafScript script) async {
    _captureScriptScrollAnchor();
    widget.settings.setMushafScript(script);
    await widget.controller.setMushafScript(script);
  }

  /// Remember the top visible ayah’s place in the viewport before remount.
  void _captureScriptScrollAnchor() {
    final positions = _itemPositionsListener.itemPositions.value;
    ItemPosition? topAyah;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0) continue;
      if (position.itemLeadingEdge >= 1) continue;
      if (position.index < 0 || position.index >= MushafLayout.itemCount) {
        continue;
      }
      if (MushafLayout.slotAt(position.index) is! MushafAyahSlot) continue;
      if (topAyah == null ||
          position.itemLeadingEdge < topAyah.itemLeadingEdge) {
        topAyah = position;
      }
    }
    if (topAyah == null) {
      _scriptAnchorIndex = widget.controller.itemIndexForAyah(
        widget.controller.currentSurah,
        widget.controller.currentAyah,
      );
      _scriptAnchorAlignment = 0;
      return;
    }
    _scriptAnchorIndex = topAyah.index;
    _scriptAnchorAlignment = topAyah.itemLeadingEdge.clamp(0.0, 0.85);
  }

  Future<void> _openProfiles() async {
    if (_popForMainOpen(ReaderRoutes.profile)) return;
    final result =
        Completer<({int surah, int ayah, bool openAtSurahHeader})?>();
    _afterStackSettle(() async {
      if (!mounted) {
        result.complete(null);
        return;
      }
      final jumpTo = await Navigator.of(context)
          .push<({int surah, int ayah, bool openAtSurahHeader})?>(
            MaterialPageRoute(
              settings: const RouteSettings(name: ReaderRoutes.profile),
              builder: (_) => ProfileScreen(
                profiles: widget.profiles,
                settings: widget.settings,
                dailyPlanStore: widget.dailyPlanStore,
                tilawatPositionStore: widget.tilawatPositionStore,
                learnedNotifyStore: widget.learnedNotifyStore,
                onSwitchProfile: widget.onSwitchProfile,
                onDeleteProfile: widget.onDeleteProfile,
                applyMushafScript: _applyMushafScript,
              ),
            ),
          );
      if (!result.isCompleted) result.complete(jumpTo);
    });
    final jumpTo = await result.future;
    if (!mounted || jumpTo == null) return;
    await _audio.stop();
    if (jumpTo.openAtSurahHeader) {
      await _jumpToSurah(jumpTo.surah);
    } else {
      await _jumpToAyah(jumpTo.surah, jumpTo.ayah, animate: false);
    }
  }

  Future<void> _openReciterPicker() async {
    final choice = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        settings: const RouteSettings(name: ReaderRoutes.reciter),
        builder: (_) => ReciterListScreen(
          selectedLabel: widget.settings.reciterLabel,
        ),
      ),
    );
    if (choice == null) return;
    widget.settings.setReciter(choice);
  }

  Future<void> _openAudioLanguagePicker() async {
    final choice = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        settings: const RouteSettings(name: ReaderRoutes.spokenTranslation),
        builder: (_) => AudioLanguageListScreen(
          selectedLabel: widget.settings.audioLanguageLabel,
        ),
      ),
    );
    if (choice == null) return;
    widget.settings.setAudioLanguage(choice);
  }

  Future<void> _openTranslatorPicker() async {
    final choice = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        settings: const RouteSettings(name: ReaderRoutes.onScreenTranslation),
        builder: (_) => TranslationMultiSelectScreen(
          selectedIds: widget.settings.translatorIds,
        ),
      ),
    );
    if (!mounted || choice == null) return;
    widget.settings.setTranslatorIds(choice);
    if (choice.isEmpty) {
      if (!widget.settings.hideTranslation) {
        widget.settings.setHideTranslation(true);
      }
    } else if (widget.settings.hideTranslation) {
      widget.settings.setHideTranslation(false);
    }
    await _reloadTranslations();
  }

  Future<void> _shareApp() async {
    await Clipboard.setData(
      const ClipboardData(
        text: 'The Quran — daily recitation, translation, and Tajweed.',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied', textDirection: TextDirection.ltr),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _persistReadingPosition(
    int surah,
    int ayah, {
    String? message,
  }) async {
    await widget.positionStore.save(surah: surah, ayah: ayah);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message ??
              'Saved: ${QuranMetadata.nameArOrEmpty(surah)} · $ayah',
              textDirection: TextDirection.ltr,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Topmost ayah currently on screen (or the first ayah under a header).
  ({int surah, int ayah}) _topAyahOnScreen() {
    final index = _topVisibleAyahItemIndex ??
        _topVisibleAyahItemIndexFrom(
          _itemPositionsListener.itemPositions.value,
        );
    if (index != null &&
        index >= 0 &&
        index < MushafLayout.itemCount) {
      final slot = MushafLayout.slotAt(index);
      if (slot is MushafAyahSlot) {
        return (surah: slot.surah, ayah: slot.ayah);
      }
    }
    return (
      surah: widget.controller.currentSurah,
      ayah: widget.controller.currentAyah,
    );
  }

  /// Spoken translation language used for playback (`none` when toggle is off).
  String _effectiveAudioLanguageId() => widget.settings.audioLanguageId;

  Future<void> _playAyah(int surah, int ayah) async {
    if (widget.settings.backgroundRecitation) {
      await _ensureAudioSession();
      await AyahAudioServiceHost.ensureInitialized();
      AyahAudioServiceHost.handler?.attach(_audio);
      AyahAudioServiceHost.handler?.setBackgroundEnabled(true);
    }
    await _audio.play(
      reciterId: widget.settings.reciterId,
      audioLanguageId: _effectiveAudioLanguageId(),
      tilawatOrder: widget.settings.tilawatOrder,
      ayahRepeatMode: widget.settings.ayahRepeatMode,
      surah: surah,
      ayah: ayah,
    );
  }

  void _cycleAyahRepeatMode() {
    widget.settings.cycleAyahRepeatMode();
    _audio.ayahRepeatMode = widget.settings.ayahRepeatMode;
  }

  Future<void> _openTilawatOrder() async {
    final choice = await showTilawatOrderDialog(
      context: context,
      selected: widget.settings.tilawatOrder,
    );
    if (!mounted || choice == null) return;
    widget.settings.setTilawatOrder(choice);
  }

  Future<void> _playTopAyah() async {
    final top = _topAyahOnScreen();
    await _playAyah(top.surah, top.ayah);
  }

  Future<void> _onBottomPlayPressed() async {
    if (_audio.playing) {
      await _audio.toggle();
      return;
    }
    if (_audio.isActive && !_audio.failed) {
      await _audio.toggle();
      return;
    }
    await _playTopAyah();
  }

  Future<void> _onBottomSkipPrevious() async {
    if (_audio.isActive) {
      await _audio.skipPrevious();
      return;
    }
    final top = _topAyahOnScreen();
    final previous = ReciterCatalog.previousAyah(top.surah, top.ayah) ??
        (surah: top.surah, ayah: top.ayah);
    await _playAyah(previous.surah, previous.ayah);
  }

  Future<void> _onBottomSkipNext() async {
    if (_audio.isActive) {
      await _audio.skipNext();
      return;
    }
    final top = _topAyahOnScreen();
    final next = ReciterCatalog.nextAyah(top.surah, top.ayah) ??
        (surah: top.surah, ayah: top.ayah);
    await _playAyah(next.surah, next.ayah);
  }

  Future<void> _onAyahTapped(int surah, int ayah) async {
    final action = await showAyahActionsPopup(context: context);
    if (!mounted || action == null) return;

    final name = QuranMetadata.nameArOrEmpty(surah);
    final ref = name.isEmpty ? 'Surah $surah · Ayah $ayah' : '$name · Ayah $ayah';

    switch (action) {
      case AyahAction.bookmark:
        await widget.bookmarkStore.add(surah: surah, ayah: ayah);
        if (!mounted) return;
        await _persistReadingPosition(
          surah,
          ayah,
          message: 'Bookmark saved',
        );
      case AyahAction.share:
        await Clipboard.setData(ClipboardData(text: ref));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ayah reference copied',
              textDirection: TextDirection.ltr,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case AyahAction.aboutSurah:
        final open = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => SurahAboutScreen(surah: surah),
          ),
        );
        if (open == true && mounted) await _jumpToSurah(surah);
      case AyahAction.tilawat:
        await _playAyah(surah, ayah);
      case AyahAction.tafsir:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AyahTranslationTafsirScreen(
              surah: surah,
              ayah: ayah,
              settings: widget.settings,
            ),
          ),
        );
      case AyahAction.wordByWord:
        final jumped = await Navigator.of(context)
            .push<({int surah, int ayah})>(
          MaterialPageRoute<({int surah, int ayah})>(
            builder: (_) => WordByWordScreen(
              surah: surah,
              ayah: ayah,
              settings: widget.settings,
            ),
          ),
        );
        if (!mounted || jumped == null) return;
        await _jumpToAyah(jumped.surah, jumped.ayah);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.settings,
        widget.controller,
      ]),
      builder: (context, _) {
        final background =
            widget.settings.customBackground ?? theme.scaffoldBackgroundColor;
        final state = widget.controller.state;
        final ready = state == QuranLoadState.ready;

        final body = switch (state) {
          QuranLoadState.idle || QuranLoadState.loading => const _LoadingView(),
          QuranLoadState.error => _ErrorView(
            error: widget.controller.error,
            onRetry: widget.controller.initialize,
          ),
          QuranLoadState.ready => MushafPinchZoom(
            key: _mushafPinchKey,
            fontSize: widget.settings.fontSize,
            onPinchStarted: _onMushafPinchStarted,
            onPinchEnded: _onMushafPinchEnded,
            onFontSizeChanged: _onMushafPinchFontSize,
            child: _ReaderList(
              key: ValueKey<String>(
                'mushaf-${widget.controller.mushafScript.name}-'
                '${widget.controller.mushafListEpoch}',
              ),
              controller: widget.controller,
              bismillah: widget.controller.bismillah,
              initialScrollIndex: widget.controller.mushafListEpoch == 0
                  ? widget.controller.initialScrollIndex
                  : (_scriptAnchorIndex ??
                      widget.controller.itemIndexForAyah(
                        widget.controller.currentSurah,
                        widget.controller.currentAyah,
                      )),
              initialAlignment: widget.controller.mushafListEpoch == 0
                  ? 0
                  : _scriptAnchorAlignment,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              inkColor: theme.colorScheme.onSurface,
              fontSize: widget.settings.fontSize,
              tajweedEnabled: widget.settings.tajweedEnabled,
              showTranslation: !widget.settings.hideTranslation,
              selectedTranslatorIds: _translationsReady
                  ? _loadedTranslatorIds
                  : const <String>[],
              translationTextAt: _translationsReady
                  ? _translations.textAt
                  : null,
              onScrollEnd: _onMushafScrollEnd,
              onScrollDelta: _onMushafScrollDelta,
              onAyahTap: _onAyahTapped,
              playingAyah: _playingAyah,
            ),
          ),
        };

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: background,
          drawer: ready
              ? ReaderMenuDrawer(
                  settings: widget.settings,
                  activeProfileName:
                      widget.profiles.activeProfile?.name ?? 'Profile',
                  onDestination: _onSidebarDestination,
                )
              : null,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            forceMaterialTransparency: true,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: const SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppTheme.topBarGradient),
              ),
            ),
            automaticallyImplyLeading: false,
            centerTitle: true,
            leadingWidth: _ReaderBottomBar.sideSlotWidth,
            leading: ready
                ? IconButton(
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu, size: 30),
                  )
                : null,
            title: ListenableBuilder(
              listenable: Listenable.merge([
                widget.controller,
                widget.controller.positionListenable,
              ]),
              builder: (context, _) {
                final loadState = widget.controller.state;
                if (loadState != QuranLoadState.ready) {
                  return Text(
                    'القرآن الكريم',
                    textDirection: TextDirection.rtl,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  );
                }

                return GestureDetector(
                  onTap: _openSurahAyahPicker,
                  behavior: HitTestBehavior.opaque,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: QuranMetadata.surahOrNull(
                                widget.controller.currentSurah,
                              )?.listTitle ??
                              QuranMetadata.nameArOrEmpty(
                                widget.controller.currentSurah,
                              ),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ${widget.controller.currentAyah}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
            actionsPadding: EdgeInsets.zero,
            actions: [
              if (ready)
                SizedBox(
                  width: _ReaderBottomBar.sideSlotWidth,
                  child: IconButton(
                    tooltip: 'Home',
                    onPressed: _openHubMenu,
                    icon: const Icon(Icons.grid_view_rounded, size: 28),
                  ),
                ),
            ],
          ),
          body: Stack(
            children: [
              body,
              if (ready)
                Positioned.fill(
                  child: PlayingAyahBarHost(
                    followDetached: _followDetached,
                    transportHeight: _ReaderBottomBar.contentHeight,
                  ),
                ),
              if (ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      widget.settings,
                      _audio,
                    ]),
                    builder: (context, _) => _ReaderBottomBar(
                      onTilawatOrderPressed: _openTilawatOrder,
                      ayahRepeatMode: widget.settings.ayahRepeatMode,
                      onRepeatPressed: _cycleAyahRepeatMode,
                      ayahRepeatPulse: _audio.repeatPulse,
                      audioPlaying: _audio.playing,
                      audioLoading: _audio.loading,
                      onPlayPressed: _onBottomPlayPressed,
                      onPreviousPressed: _onBottomSkipPrevious,
                      onNextPressed: _onBottomSkipNext,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _onMushafPinchStarted(Offset localFocal) {
    _pinchActive = true;
    final box =
        _mushafPinchKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 1.0;
    final frac = (localFocal.dy / height).clamp(0.0, 1.0);
    final positions = _itemPositionsListener.itemPositions.value;

    ItemPosition? hit;
    for (final position in positions) {
      if (position.itemLeadingEdge <= frac &&
          position.itemTrailingEdge > frac) {
        hit = position;
        break;
      }
    }
    hit ??= () {
      ItemPosition? top;
      for (final position in positions) {
        if (position.itemTrailingEdge <= 0) continue;
        if (position.itemLeadingEdge >= 1) continue;
        if (top == null ||
            position.itemLeadingEdge < top.itemLeadingEdge) {
          top = position;
        }
      }
      return top;
    }();

    if (hit == null) {
      _pinchAnchorIndex = null;
      _pinchAnchorAlignment = null;
      return;
    }
    _pinchAnchorIndex = hit.index;
    _pinchAnchorAlignment = hit.itemLeadingEdge.clamp(0.0, 0.9);
  }

  void _onMushafPinchFontSize(double size) {
    widget.settings.setFontSize(size);
    _restorePinchAnchor();
  }

  void _onMushafPinchEnded() {
    _restorePinchAnchor();
    _pinchActive = false;
    _pinchAnchorIndex = null;
    _pinchAnchorAlignment = null;
  }

  void _restorePinchAnchor() {
    final index = _pinchAnchorIndex;
    final alignment = _pinchAnchorAlignment;
    if (index == null || alignment == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      if (index < 0 || index >= MushafLayout.itemCount) return;
      _itemScrollController.jumpTo(index: index, alignment: alignment);
    });
  }

  /// Tracks scroll direction for ahead-of-viewport shaping. Transport stays put.
  void _onMushafScrollDelta(double delta) {
    if (_isSnapping || _isRestoringOrientation || _pinchActive) return;
    widget.controller.setScrollActive(true);
    PreparedLineCache.deferMisses = true;
    if (delta > 2.5) {
      _scrollForward = true;
    } else if (delta < -2.5) {
      _scrollForward = false;
    }
    _scheduleShapeWarm();
  }

  void _scheduleShapeWarm() {
    if (_shapeWarmScheduled) return;
    _shapeWarmScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _shapeWarmScheduled = false;
      if (!mounted) return;
      _warmAyahAhead();
    });
  }

  /// Queues HarfBuzz for several uncached ayahs ahead of the viewport (off
  /// the scroll build) so a fast fling still has outlines ready to paint.
  void _warmAyahAhead() {
    final fontPath = KfgqpcFontScope.maybeOf(context);
    if (fontPath == null || peekJustificationShaper(fontPath) == null) return;
    final positions = _itemPositionsListener.itemPositions.value;
    final top = _topVisibleItemIndex(positions);
    if (top == null) return;
    final direction = _scrollForward ? 1 : -1;
    final maxWidth = (MediaQuery.sizeOf(context).width - 40).clamp(
      120.0,
      4000.0,
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final fontSize = widget.settings.fontSize;
    const maxSteps = 40;
    const maxAyahsPerFrame = 4;
    var queuedAyahs = 0;
    for (var step = 1; step <= maxSteps; step++) {
      final index = top + direction * step;
      if (index < 0 || index >= MushafLayout.itemCount) return;
      final slot = MushafLayout.slotAt(index);
      if (slot is! MushafAyahSlot) continue;
      final chunk = widget.controller.ayahAt(slot.surah, slot.ayah);
      if (chunk == null) continue;
      final queued = warmQuranAyahLines(
        ayah: chunk,
        fontSize: fontSize,
        maxWidth: maxWidth,
        fontPath: fontPath,
        devicePixelRatio: dpr,
        emphasizedWordCount: QuranMetadata.paraOpeningWordCount(
          slot.surah,
          slot.ayah,
        ),
        showEndMarker: true,
        showRubMarker:
            MushafDivisions.cached?.isQuarterEnd(slot.surah, slot.ayah) ??
            false,
      );
      if (!queued) continue;
      queuedAyahs++;
      if (queuedAyahs >= maxAyahsPerFrame) return;
    }
  }

  void _onMushafScrollEnd() {
    PreparedLineCache.deferMisses = false;
    widget.controller.setScrollActive(false);
    widget.controller.flushPositionSave();
    _snapVisibleSurahHeader();
  }
}

/// Fixed bottom bar: recitation order (left), transport (center), ayah repeat (right).
class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.onTilawatOrderPressed,
    required this.ayahRepeatMode,
    required this.onRepeatPressed,
    required this.ayahRepeatPulse,
    required this.audioPlaying,
    required this.audioLoading,
    required this.onPlayPressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  /// Same corner width as the top bar. Repeat stays on the right.
  static const double sideSlotWidth = 56;

  /// Inner row height (safe-area padding is extra).
  static const double contentHeight = 68;

  /// List bottom padding so the last ayah clears this overlay.
  static double overlayReserve(double safeBottom) =>
      contentHeight + safeBottom + 12;

  final VoidCallback onTilawatOrderPressed;
  final AyahRepeatMode ayahRepeatMode;
  final VoidCallback onRepeatPressed;
  final int ayahRepeatPulse;
  final bool audioPlaying;
  final bool audioLoading;
  final VoidCallback onPlayPressed;
  final VoidCallback onPreviousPressed;
  final VoidCallback onNextPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.bottomBarGradient),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CircleTransportButton(
                    tooltip: 'Previous ayah',
                    onPressed: onPreviousPressed,
                    size: 42,
                    filled: true,
                    child: Icon(
                      Icons.fast_rewind_rounded,
                      color: AppTheme.orangeDeep,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  _CircleTransportButton(
                    tooltip: audioPlaying ? 'Pause' : 'Play',
                    onPressed: audioLoading ? null : onPlayPressed,
                    size: 56,
                    filled: true,
                    elevated: true,
                    child: audioLoading
                        ? SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppTheme.orangeDeep,
                            ),
                          )
                        : Icon(
                            audioPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: AppTheme.orangeDeep,
                            size: 36,
                          ),
                  ),
                  const SizedBox(width: 14),
                  _CircleTransportButton(
                    tooltip: 'Next ayah',
                    onPressed: onNextPressed,
                    size: 42,
                    filled: true,
                    child: Icon(
                      Icons.fast_forward_rounded,
                      color: AppTheme.orangeDeep,
                      size: 28,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: sideSlotWidth,
                  child: IconButton(
                    tooltip: 'Recitation order',
                    onPressed: onTilawatOrderPressed,
                    icon: const Icon(
                      Icons.queue_music_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: sideSlotWidth,
                  child: Center(
                    child: _AyahRepeatButton(
                      mode: ayahRepeatMode,
                      repeatPulse: ayahRepeatPulse,
                      onPressed: onRepeatPressed,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleTransportButton extends StatefulWidget {
  const _CircleTransportButton({
    required this.child,
    required this.size,
    required this.tooltip,
    this.onPressed,
    this.filled = false,
    this.elevated = false,
  });

  final Widget child;
  final double size;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final bool elevated;

  @override
  State<_CircleTransportButton> createState() => _CircleTransportButtonState();
}

class _CircleTransportButtonState extends State<_CircleTransportButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final canTap = widget.onPressed != null;
    final scale = _pressed && canTap ? 0.92 : 1.0;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: canTap ? (_) => _setPressed(true) : null,
        onTapUp: canTap ? (_) => _setPressed(false) : null,
        onTapCancel: canTap ? () => _setPressed(false) : null,
        onTap: canTap ? widget.onPressed : null,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.filled
                  ? Colors.white.withValues(alpha: canTap ? 1 : 0.55)
                  : Colors.white.withValues(alpha: 0.16),
              border: Border.all(
                color: Colors.white.withValues(alpha: canTap ? 0.95 : 0.45),
                width: widget.elevated ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _pressed ? 0.12 : (widget.elevated ? 0.28 : 0.18),
                  ),
                  blurRadius: _pressed
                      ? 2
                      : (widget.elevated ? 10 : 6),
                  offset: Offset(0, _pressed ? 1 : (widget.elevated ? 3 : 2)),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Cycles ayah audio repeat: 1 → 2 → 3 → ∞ → 1.
/// On each same-ayah restart: jump up, then bounce like a ball on the drop.
class _AyahRepeatButton extends StatefulWidget {
  const _AyahRepeatButton({
    required this.mode,
    required this.repeatPulse,
    required this.onPressed,
  });

  final AyahRepeatMode mode;
  final int repeatPulse;
  final VoidCallback onPressed;

  @override
  State<_AyahRepeatButton> createState() => _AyahRepeatButtonState();
}

class _AyahRepeatButtonState extends State<_AyahRepeatButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;
  late final Animation<double> _offsetY;
  int _bounceGen = 0;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _offsetY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -20)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -20, end: 0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 82,
      ),
    ]).animate(_bounce);
  }

  @override
  void didUpdateWidget(covariant _AyahRepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repeatPulse != oldWidget.repeatPulse &&
        widget.repeatPulse > 0) {
      unawaited(_playJumpThenBall());
    }
  }

  Future<void> _playJumpThenBall() async {
    final gen = ++_bounceGen;
    _bounce.stop();
    await _bounce.forward(from: 0);
    if (!mounted || gen != _bounceGen) return;
    _bounce.value = 1;
  }

  @override
  void dispose() {
    _bounceGen++;
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.mode.tooltip,
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _offsetY,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _offsetY.value),
              child: child,
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      color: Colors.white.withValues(alpha: 0.95),
                      size: 42,
                    ),
                    Text(
                      widget.mode.badgeLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize:
                            widget.mode == AyahRepeatMode.unlimited ? 16 : 15,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        shadows: const [
                          Shadow(
                            color: Color(0xAA000000),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Repeat',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ReaderList extends StatelessWidget {
  const _ReaderList({
    super.key,
    required this.controller,
    required this.bismillah,
    required this.initialScrollIndex,
    this.initialAlignment = 0,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.inkColor,
    required this.fontSize,
    required this.tajweedEnabled,
    required this.showTranslation,
    required this.selectedTranslatorIds,
    required this.translationTextAt,
    required this.onScrollEnd,
    required this.onScrollDelta,
    required this.onAyahTap,
    required this.playingAyah,
  });

  final QuranReaderController controller;
  final QuranAyahChunk? bismillah;
  final int initialScrollIndex;
  final double initialAlignment;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final Color inkColor;
  final double fontSize;
  final bool tajweedEnabled;
  final bool showTranslation;
  final List<String> selectedTranslatorIds;
  final String? Function(String translatorId, int surah, int ayah)?
      translationTextAt;
  final VoidCallback onScrollEnd;
  final ValueChanged<double> onScrollDelta;
  final void Function(int surah, int ayah) onAyahTap;
  final ValueListenable<({int? surah, int? ayah})> playingAyah;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            final delta = notification.scrollDelta;
            if (delta != null && delta != 0) {
              onScrollDelta(delta);
            }
          } else if (notification is ScrollEndNotification) {
            onScrollEnd();
          }
          return false;
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ScrollablePositionedList.builder(
            itemScrollController: itemScrollController,
            itemPositionsListener: itemPositionsListener,
            physics: MushafPinchLock.of(context)
                ? const NeverScrollableScrollPhysics()
                : null,
            initialScrollIndex: initialScrollIndex.clamp(
              0,
              MushafLayout.itemCount - 1,
            ),
            initialAlignment: initialAlignment,
            itemCount: MushafLayout.itemCount,
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              _ReaderBottomBar.overlayReserve(
                MediaQuery.paddingOf(context).bottom,
              ),
            ),
            minCacheExtent: 1000,
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) {
              final slot = MushafLayout.slotAt(index);
              return switch (slot) {
                MushafHeaderSlot(:final surah) => _SurahHeader(
                  header: MushafLayout.headerFor(surah),
                  bismillah: bismillah,
                  fontSize: fontSize,
                  inkColor: inkColor,
                ),
                MushafAyahSlot(:final surah, :final ayah) => _AyahRow(
                  key: ValueKey<int>(index),
                  surah: surah,
                  ayah: ayah,
                  chunk: controller.ayahAt(surah, ayah),
                  fontSize: fontSize,
                  tajweedEnabled: tajweedEnabled,
                  inkColor: inkColor,
                  showTranslation: showTranslation,
                  selectedTranslatorIds: selectedTranslatorIds,
                  translationTextAt: translationTextAt,
                  playingAyah: playingAyah,
                  onTap: () => onAyahTap(surah, ayah),
                ),
              };
            },
          ),
        ),
      ),
    );
  }
}

class _AyahTranslationLine {
  const _AyahTranslationLine({
    required this.text,
    required this.translatorLabel,
    required this.ltr,
  });

  final String text;
  final String translatorLabel;
  final bool ltr;
}

/// Loaded ayah, or a light placeholder until the background full parse fills it.
class _AyahRow extends StatefulWidget {
  const _AyahRow({
    super.key,
    required this.surah,
    required this.ayah,
    required this.chunk,
    required this.fontSize,
    required this.tajweedEnabled,
    required this.inkColor,
    required this.showTranslation,
    required this.selectedTranslatorIds,
    required this.translationTextAt,
    required this.playingAyah,
    required this.onTap,
  });

  final int surah;
  final int ayah;
  final QuranAyahChunk? chunk;
  final double fontSize;
  final bool tajweedEnabled;
  final Color inkColor;
  final bool showTranslation;
  final List<String> selectedTranslatorIds;
  final String? Function(String translatorId, int surah, int ayah)?
      translationTextAt;
  final ValueListenable<({int? surah, int? ayah})> playingAyah;
  final VoidCallback onTap;

  @override
  State<_AyahRow> createState() => _AyahRowState();
}

class _AyahRowState extends State<_AyahRow> {
  bool _pressed = false;
  bool _playing = false;
  List<_AyahTranslationLine> _translations = const [];
  int _emphasizedWordCount = 0;
  bool _showRubMarker = false;
  RukuMarkInfo? _rukuMark;
  bool _divisionsReady = false;

  @override
  void initState() {
    super.initState();
    widget.playingAyah.addListener(_syncPlaying);
    _playing = _isPlaying(widget.playingAyah.value);
    _refreshDerived();
  }

  @override
  void didUpdateWidget(_AyahRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playingAyah != widget.playingAyah) {
      oldWidget.playingAyah.removeListener(_syncPlaying);
      widget.playingAyah.addListener(_syncPlaying);
    }
    _syncPlaying();
    if (oldWidget.chunk != widget.chunk ||
        oldWidget.surah != widget.surah ||
        oldWidget.ayah != widget.ayah ||
        oldWidget.showTranslation != widget.showTranslation ||
        oldWidget.translationTextAt != widget.translationTextAt ||
        !listEquals(
          oldWidget.selectedTranslatorIds,
          widget.selectedTranslatorIds,
        )) {
      _refreshDerived();
    }
  }

  @override
  void dispose() {
    widget.playingAyah.removeListener(_syncPlaying);
    super.dispose();
  }

  bool _isPlaying(({int? surah, int? ayah}) playing) =>
      playing.surah == widget.surah && playing.ayah == widget.ayah;

  void _syncPlaying() {
    final next = _isPlaying(widget.playingAyah.value);
    if (next == _playing) return;
    setState(() => _playing = next);
  }

  void _refreshDerived() {
    _emphasizedWordCount = QuranMetadata.paraOpeningWordCount(
      widget.surah,
      widget.ayah,
    );
    final divisions = MushafDivisions.cached;
    _divisionsReady = divisions != null;
    _showRubMarker =
        divisions?.isQuarterEnd(widget.surah, widget.ayah) ?? false;
    _rukuMark = divisions?.rukuMarkAt(widget.surah, widget.ayah);
    _translations = _linesFor();
  }

  List<_AyahTranslationLine> _linesFor() {
    if (!widget.showTranslation || widget.translationTextAt == null) {
      return const [];
    }
    final showCredits = widget.selectedTranslatorIds.length > 1;
    final lines = <_AyahTranslationLine>[];
    for (final id in widget.selectedTranslatorIds) {
      final text = widget.translationTextAt!(id, widget.surah, widget.ayah)
          ?.trim();
      if (text == null || text.isEmpty) continue;
      lines.add(
        _AyahTranslationLine(
          text: text,
          translatorLabel:
              showCredits ? TranslationCatalog.creditFor(id) : '',
          ltr: TranslationCatalog.isLtr(id),
        ),
      );
    }
    return lines;
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_divisionsReady && MushafDivisions.cached != null) {
      _refreshDerived();
    }
    final chunk = widget.chunk;
    if (chunk == null) {
      return SizedBox(
        height: widget.fontSize * 2.2,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final bodySize = (widget.fontSize * 0.55).clamp(14.0, 40.0);
    final creditSize = (bodySize * 0.65).clamp(9.0, 22.0);
    final bodyColor = theme.colorScheme.onSurface.withValues(alpha: 0.88);
    final creditColor = AppTheme.orange.withValues(alpha: 0.9);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
          decoration: BoxDecoration(
            color: _pressed
                ? const Color(0xFF9E9E9E).withValues(alpha: 0.22)
                : _playing
                    ? AppTheme.orange.withValues(alpha: 0.16)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QuranAyahWidget(
                ayah: chunk,
                fontSize: widget.fontSize,
                tajweedEnabled: widget.tajweedEnabled,
                inkColor: widget.inkColor,
                emphasizedWordCount: _emphasizedWordCount,
                showRubMarker: _showRubMarker,
                rukuMark: _rukuMark,
                onRukuAinTap: _rukuMark == null
                    ? null
                    : () {
                        showRukuInfoPopup(
                          context: context,
                          mark: _rukuMark!,
                        );
                      },
              ),
              for (var i = 0; i < _translations.length; i++) ...[
                SizedBox(height: i == 0 ? 6 : 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _translations[i].text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: bodySize,
                          height: 1.55,
                          color: bodyColor,
                        ),
                      ),
                      if (_translations[i].translatorLabel.isNotEmpty)
                        TextSpan(
                          text: ' — ${_translations[i].translatorLabel}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: creditSize,
                            height: 1.55,
                            color: creditColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  textDirection: _translations[i].ltr
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  textAlign: _translations[i].ltr
                      ? TextAlign.left
                      : TextAlign.right,
                ),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({
    required this.header,
    required this.bismillah,
    required this.fontSize,
    required this.inkColor,
  });

  final QuranSurahHeader header;
  final QuranAyahChunk? bismillah;
  final double fontSize;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    return SurahHeaderBanner(
      surah: header.surah,
      nameAr: header.nameAr,
      bismillah: bismillah,
      fontSize: fontSize,
      inkColor: inkColor,
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator.adaptive(),
          SizedBox(height: 16),
          Text('Preparing Quran…'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(
              'Could not load Quran data.\n${error ?? ''}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
