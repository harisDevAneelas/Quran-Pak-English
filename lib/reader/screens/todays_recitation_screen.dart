import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/app_dimens.dart';
import '../../core/app_theme.dart';
import '../../core/mushaf_layout.dart';
import '../../core/quran_font.dart';
import '../../data/ayah_ref.dart';
import '../../data/mushaf_divisions.dart';
import '../../data/quran_metadata.dart';
import '../../data/quran_models.dart';
import '../../data/quran_repository.dart';
import '../../data/recommended_surah.dart';
import '../daily_plan.dart';
import '../daily_range.dart';
import '../playing_ayah_follow.dart';
import '../profile_manager.dart';
import '../reader_nav_scope.dart';
import '../reader_settings.dart';
import '../tilawat_position_store.dart';
import '../widgets/mushaf_pinch_zoom.dart';
import '../widgets/orange_app_bar.dart';
import '../widgets/quran_ayah_widget.dart';
import '../widgets/reader_page_scaffold.dart';
import '../widgets/recitation_bismillah.dart';
import '../widgets/surah_header_banner.dart';
import '../widgets/ruku_info_popup.dart';
import 'daily_recitation_screen.dart';

enum _EndPrompt { hidden, askComplete }

enum _CompletionKind { readMore, sadaqaAllah, surah }

class _CompletionChoice {
  const _CompletionChoice._(this.kind, [this.surah]);

  const _CompletionChoice.readMore() : this._(_CompletionKind.readMore);
  const _CompletionChoice.sadaqaAllah() : this._(_CompletionKind.sadaqaAllah);
  const _CompletionChoice.surah(int surah)
      : this._(_CompletionKind.surah, surah);

  final _CompletionKind kind;
  final int? surah;
}

/// Today's recitation: full mushaf when no plan; daily portion + completion when ترتیب is set.
class TodaysRecitationScreen extends StatefulWidget {
  const TodaysRecitationScreen({
    super.key,
    required this.settings,
    required this.dailyPlanStore,
    required this.tilawatPositionStore,
    required this.profiles,
  });

  final ReaderSettings settings;
  final DailyPlanStore dailyPlanStore;
  final TilawatPositionStore tilawatPositionStore;
  final ProfileManager profiles;

  @override
  State<TodaysRecitationScreen> createState() => _TodaysRecitationScreenState();
}

class _TodaysRecitationScreenState extends State<TodaysRecitationScreen>
    with SingleTickerProviderStateMixin {
  final QuranDataRepository _repo = QuranDataRepository();

  /// Full-mushaf list.
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  /// Portion-mode list.
  final ScrollController _portionScroll = ScrollController();

  late final AnimationController _promptAnim;
  late final Animation<double> _promptFactor;
  late final ValueNotifier<double> _promptChrome;

  /// Overlay prompt only — does not rebuild the mushaf list.
  final ValueNotifier<bool> _chromeVisible = ValueNotifier(false);

  static const _positionSaveDebounce = Duration(milliseconds: 400);

  List<QuranAyahChunk> _ayahs = const [];
  DailyPlan? _plan;
  AyahWindow? _window;
  bool _portionMode = false;
  bool _loading = true;
  String? _error;

  Timer? _positionSaveTimer;
  Timer? _introChromeTimer;
  int? _visibleSurah;
  int? _visibleAyah;
  ({int surah, int ayah})? _pendingPositionSave;
  bool _scrollActive = false;
  int _initialScrollIndex = 0;

  bool _advanced = false;
  bool _offeredReadMore = false;
  bool _ignorePortionScroll = false;
  int _askGeneration = 0;
  _EndPrompt _prompt = _EndPrompt.hidden;

  final GlobalKey _pinchKey = GlobalKey();
  int? _pinchAnchorIndex;
  double? _pinchAnchorAlignment;
  double? _pinchPortionScrollFrac;

  /// Standalone page bismillah only when the list does not open on a surah header.
  bool get _showPageBismillah =>
      _ayahs.isNotEmpty && _ayahs.first.ayah != 1;

  int get _leadSlots => _showPageBismillah ? 1 : 0;

  /// Portion adds a trailing completion footer.
  int get _itemCount {
    if (_ayahs.isEmpty) return 0;
    final tail = _portionMode ? 1 : 0;
    return _ayahs.length + _leadSlots + tail;
  }

  bool _showSurahHeader(int ayahIndex) {
    final chunk = _ayahs[ayahIndex];
    if (ayahIndex == 0) return chunk.ayah == 1;
    return _ayahs[ayahIndex - 1].surah != chunk.surah;
  }

  @override
  void initState() {
    super.initState();
    _promptAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _promptFactor = CurvedAnimation(
      parent: _promptAnim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _promptChrome = ValueNotifier(0);
    _promptAnim.addListener(_onPromptTick);
    _portionScroll.addListener(_onPortionScroll);
    _positions.itemPositions.addListener(_onItemPositionsChanged);
    _load();
  }

  @override
  void dispose() {
    _positionSaveTimer?.cancel();
    _introChromeTimer?.cancel();
    _portionScroll.removeListener(_onPortionScroll);
    _portionScroll.dispose();
    _promptAnim.removeListener(_onPromptTick);
    _promptAnim.dispose();
    _promptChrome.dispose();
    _positions.itemPositions.removeListener(_onItemPositionsChanged);
    _chromeVisible.dispose();
    if (!_portionMode) _flushPositionSave();
    super.dispose();
  }

  void _onPromptTick() {
    _pinPortionToEnd();
    _promptChrome.value =
        _EndPromptBar.contentHeight * _promptFactor.value;
  }

  Future<void> _showIntroChromeIfNeeded() async {
    if (_portionMode) return;
    final show =
        await widget.tilawatPositionStore.shouldShowArrangementPrompt();
    if (!mounted || !show) return;
    await widget.tilawatPositionStore.markArrangementPromptShown();
    if (!mounted) return;
    _introChromeTimer?.cancel();
    _chromeVisible.value = true;
    _introChromeTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      _chromeVisible.value = false;
    });
  }

  void _hideChrome() {
    _introChromeTimer?.cancel();
    _introChromeTimer = null;
    if (_chromeVisible.value) _chromeVisible.value = false;
  }

  bool _onFullScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null && delta != 0) {
        _scrollActive = true;
      }
    } else if (notification is ScrollEndNotification) {
      _scrollActive = false;
      _flushPositionSave();
    }
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _hideChrome();
    }
    return false;
  }

  Future<void> _load({bool scrollToTop = false}) async {
    _askGeneration++;
    setState(() {
      _loading = true;
      _error = null;
      _advanced = false;
      _offeredReadMore = false;
      _prompt = _EndPrompt.hidden;
    });
    _promptAnim.value = 0;
    _promptChrome.value = 0;
    _hideChrome();

    try {
      await QuranMetadata.load();
      final divisions = await MushafDivisions.load();
      final plan = await widget.dailyPlanStore.load();
      if (!mounted) return;

      if (plan == null) {
        await _loadFullMushaf();
        return;
      }

      final window = DailyRangeResolver.resolve(plan, divisions);
      final processed = await _repo.loadWindow(window);
      final ayahs = <QuranAyahChunk>[
        for (final item in processed.items)
          if (item is AyahItem) item.chunk,
      ];
      if (!mounted) return;

      setState(() {
        _plan = plan;
        _window = window;
        _ayahs = ayahs;
        _portionMode = true;
        _initialScrollIndex = 0;
        _visibleSurah = ayahs.isEmpty ? null : ayahs.first.surah;
        _visibleAyah = ayahs.isEmpty ? null : ayahs.first.ayah;
        _loading = false;
      });
      if (scrollToTop) {
        await _ensurePortionScrollAtTop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFullMushaf() async {
    final processed = await _repo.loadFull();
    final ayahs = <QuranAyahChunk>[
      for (final item in processed.items)
        if (item is AyahItem) item.chunk,
    ];
    final saved = await widget.tilawatPositionStore.load();
    if (!mounted) return;

    final lead = ayahs.isNotEmpty && ayahs.first.ayah != 1 ? 1 : 0;
    var initialIndex = 0;
    if (saved != null) {
      final i = ayahs.indexWhere(
        (a) => a.surah == saved.surah && a.ayah == saved.ayah,
      );
      if (i >= 0) initialIndex = i + lead;
      _visibleSurah = saved.surah;
      _visibleAyah = saved.ayah;
    } else if (ayahs.isNotEmpty) {
      _visibleSurah = ayahs.first.surah;
      _visibleAyah = ayahs.first.ayah;
    }

    setState(() {
      _plan = null;
      _window = null;
      _ayahs = ayahs;
      _portionMode = false;
      _initialScrollIndex = initialIndex;
      _loading = false;
    });
    unawaited(_showIntroChromeIfNeeded());
  }

  Future<void> _ensurePortionScrollAtTop() async {
    _ignorePortionScroll = true;
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_portionScroll.hasClients) {
        _portionScroll.jumpTo(0);
      }
    }
    if (!mounted) return;
    _ignorePortionScroll = false;
  }

  void _onPortionScroll() {
    if (_ignorePortionScroll || !_portionScroll.hasClients || _ayahs.isEmpty) {
      return;
    }
    if (_promptAnim.isAnimating) return;
    final pos = _portionScroll.position;
    if (!pos.hasContentDimensions) return;
    final remaining = pos.maxScrollExtent - pos.pixels;
    if (remaining <= 20) {
      if (_prompt == _EndPrompt.hidden && !_advanced) {
        unawaited(_revealPrompt(_EndPrompt.askComplete));
      }
    } else if (remaining > 140 && _prompt != _EndPrompt.hidden) {
      unawaited(_hidePrompt());
    }
  }

  bool _nearPortionEnd() {
    if (!_portionScroll.hasClients) return false;
    final pos = _portionScroll.position;
    if (!pos.hasContentDimensions) return false;
    return pos.maxScrollExtent - pos.pixels <= 20;
  }

  void _pinPortionToEnd() {
    if (_promptAnim.status != AnimationStatus.forward) return;
    if (!_portionScroll.hasClients) return;
    final pos = _portionScroll.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    final max = pos.maxScrollExtent;
    if ((pos.pixels - max).abs() > 0.5) {
      _portionScroll.jumpTo(max);
    }
  }

  Future<void> _revealPrompt(_EndPrompt next) async {
    final wasHidden = _prompt == _EndPrompt.hidden;
    _ignorePortionScroll = true;
    setState(() => _prompt = next);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _pinPortionToEnd();
    if (wasHidden || _promptAnim.value < 1) {
      await _promptAnim.forward();
    }
    if (!mounted) return;
    _ignorePortionScroll = false;
  }

  Future<void> _hidePrompt() async {
    _ignorePortionScroll = true;
    await _promptAnim.reverse();
    if (!mounted) return;
    setState(() => _prompt = _EndPrompt.hidden);
    _ignorePortionScroll = false;
  }

  Future<void> _onCompleteYes() async {
    final plan = _plan;
    final window = _window;
    if (plan == null || window == null || _advanced) return;
    final generation = ++_askGeneration;

    final next = DailyRangeResolver.nextStartAfter(window);
    final updated = plan.copyWith(
      startSurah: next.surah,
      startAyah: next.ayah,
    );
    await widget.dailyPlanStore.save(updated);
    await widget.dailyPlanStore.markCompletedToday();
    if (!mounted) return;
    setState(() {
      _plan = updated;
      _advanced = true;
    });
    await _hidePrompt();
    if (!mounted || _offeredReadMore || generation != _askGeneration) return;
    _offeredReadMore = true;
    final choice = await showDialog<_CompletionChoice>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => _CompletionDialog(surahs: _todaysSurahs()),
    );
    if (!mounted || choice == null) return;
    switch (choice.kind) {
      case _CompletionKind.readMore:
        await _load(scrollToTop: true);
      case _CompletionKind.surah:
        final surah = choice.surah;
        if (surah != null) {
          ReaderNavScope.maybeOf(context)?.nav.jumpToSurah(surah);
        }
      case _CompletionKind.sadaqaAllah:
        break;
    }
  }

  /// Daily occasion surahs plus timed hub recommendations for this clock window.
  static List<RecommendedSurah> _todaysSurahs() {
    final seen = <int>{};
    final out = <RecommendedSurah>[];
    void add(RecommendedSurah surah) {
      if (seen.add(surah.surah)) out.add(surah);
    }

    add(OccasionSurahs.muzammil);
    add(OccasionSurahs.rahman);
    for (final surah in RecommendedSurahResolver.resolveMany()) {
      add(surah);
    }
    return out;
  }

  Future<void> _onCompleteNo() async {
    if (_advanced) return;
    final generation = ++_askGeneration;
    await _hidePrompt();
    if (!mounted || _advanced || generation != _askGeneration) return;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted || _advanced || generation != _askGeneration) return;
    if (_prompt != _EndPrompt.hidden || !_nearPortionEnd()) return;
    await _revealPrompt(_EndPrompt.askComplete);
  }

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

  void _onItemPositionsChanged() {
    if (_portionMode || _ayahs.isEmpty) return;
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;

    final topIndex = _topVisibleItemIndex(positions);
    if (topIndex == null) return;

    final ayahIndex = topIndex <= _leadSlots ? 0 : topIndex - _leadSlots;
    if (ayahIndex < 0 || ayahIndex >= _ayahs.length) return;
    final chunk = _ayahs[ayahIndex];
    _updateVisibleAyah(chunk.surah, chunk.ayah);
  }

  void _updateVisibleAyah(int surah, int ayah) {
    if (_portionMode) return;
    if (_visibleSurah == surah && _visibleAyah == ayah) return;
    _visibleSurah = surah;
    _visibleAyah = ayah;
    if (_scrollActive) {
      _pendingPositionSave = (surah: surah, ayah: ayah);
      return;
    }
    _schedulePositionSave(surah, ayah);
  }

  void _schedulePositionSave(int surah, int ayah) {
    _pendingPositionSave = (surah: surah, ayah: ayah);
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(_positionSaveDebounce, _flushPositionSave);
  }

  void _flushPositionSave() {
    if (_portionMode) return;
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    final pending = _pendingPositionSave;
    if (pending != null) {
      _pendingPositionSave = null;
      unawaited(
        widget.tilawatPositionStore.save(
          surah: pending.surah,
          ayah: pending.ayah,
        ),
      );
      return;
    }
    final surah = _visibleSurah;
    final ayah = _visibleAyah;
    if (surah == null || ayah == null) return;
    unawaited(widget.tilawatPositionStore.save(surah: surah, ayah: ayah));
  }

  Future<void> _openArrangement() async {
    if (!_portionMode) _flushPositionSave();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DailyRecitationScreen(
          dailyPlanStore: widget.dailyPlanStore,
          profiles: widget.profiles,
        ),
      ),
    );
    if (!mounted) return;
    await _load(scrollToTop: true);
  }

  Widget _ayahRow(BuildContext context, QuranAyahChunk chunk, bool showHeader) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            SurahHeaderBanner(
              surah: chunk.surah,
              nameAr: MushafLayout.headerFor(chunk.surah).nameAr,
              bismillah: _repo.bismillah,
              fontSize: widget.settings.fontSize,
              inkColor: ink,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: QuranAyahWidget(
              ayah: chunk,
              fontSize: widget.settings.fontSize,
              tajweedEnabled: widget.settings.tajweedEnabled,
              inkColor: ink,
              emphasizedWordCount: QuranMetadata.paraOpeningWordCount(
                chunk.surah,
                chunk.ayah,
              ),
              showRubMarker: MushafDivisions.cached?.isQuarterEnd(
                    chunk.surah,
                    chunk.ayah,
                  ) ??
                  false,
              rukuMark: MushafDivisions.cached?.rukuMarkAt(
                chunk.surah,
                chunk.ayah,
              ),
              onRukuAinTap: () {
                final mark = MushafDivisions.cached?.rukuMarkAt(
                  chunk.surah,
                  chunk.ayah,
                );
                if (mark == null) return;
                showRukuInfoPopup(context: context, mark: mark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _portionFooter(BuildContext context) {
    final chipReserve = playingAyahBarListReserve(
      audioActive:
          ReaderNavScope.maybeOf(context)?.nav.playingBar.value != null,
      barHeight: AppDimens.scaled(context, AppDimens.playingAyahBarHeight),
      gap: AppDimens.scaled(context, AppDimens.playingAyahBarGap),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chipReserve > 0) SizedBox(height: chipReserve),
        SizeTransition(
          sizeFactor: _promptFactor,
          alignment: Alignment.bottomCenter,
          child: _EndPromptBar(
            title: "Have you finished today's recitation?",
            onYes: _onCompleteYes,
            onNo: _onCompleteNo,
          ),
        ),
      ],
    );
  }

  Widget _buildPortionList(Color ink) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.settings,
        ?ReaderNavScope.maybeOf(context)?.nav.playingBar,
      ]),
      builder: (context, _) {
        return ListView.builder(
          controller: _portionScroll,
          physics: MushafPinchLock.of(context)
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: const EdgeInsets.only(top: 12),
          itemCount: _itemCount,
          itemBuilder: (context, index) {
            if (_showPageBismillah && index == 0) {
              return RecitationBismillah(
                text: QuranMetadata.bismillahTextOrEmpty(),
                fontSize: widget.settings.fontSize,
                inkColor: ink,
              );
            }
            if (index == _itemCount - 1) {
              return _portionFooter(context);
            }
            final ayahIndex = index - _leadSlots;
            final chunk = _ayahs[ayahIndex];
            return _ayahRow(context, chunk, _showSurahHeader(ayahIndex));
          },
        );
      },
    );
  }

  Widget _buildFullList(Color ink) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onFullScrollNotification,
      child: ScrollConfiguration(
        behavior:
            ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ScrollablePositionedList.builder(
          itemScrollController: _itemScroll,
          itemPositionsListener: _positions,
          physics: MushafPinchLock.of(context)
              ? const NeverScrollableScrollPhysics()
              : null,
          initialScrollIndex: _initialScrollIndex,
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          itemCount: _itemCount,
          itemBuilder: (context, index) {
            if (_showPageBismillah && index == 0) {
              return RecitationBismillah(
                text: QuranMetadata.bismillahTextOrEmpty(),
                fontSize: widget.settings.fontSize,
                inkColor: ink,
              );
            }
            final ayahIndex = index - _leadSlots;
            final chunk = _ayahs[ayahIndex];
            return _ayahRow(context, chunk, _showSurahHeader(ayahIndex));
          },
        ),
      ),
    );
  }

  Widget _arrangementChrome(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: _chromeVisible,
        builder: (context, visible, child) {
          return IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              offset: visible ? Offset.zero : const Offset(0, -1.2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: visible ? 1 : 0,
                child: child,
              ),
            ),
          );
        },
        child: Material(
          color: const Color(0xFF3A3A3A),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Set a daily recitation plan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppDimens.scaled(
                          context,
                          AppDimens.fontTilawatButton,
                        ),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GoldDoneButton(
                      label: 'Create a plan',
                      onPressed: _openArrangement,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_portionMode) _flushPositionSave();
      },
      child: ReaderPageScaffold(
        title: "Today's recitation",
        showPlayingAyahBar: _portionMode,
        playingBarChromeHeight: _portionMode ? _promptChrome : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : ListenableBuilder(
                    listenable: widget.settings,
                    builder: (context, _) {
                      final ink = theme.colorScheme.onSurface;
                      return Directionality(
                        textDirection: TextDirection.ltr,
                        child: Stack(
                          children: [
                            MushafPinchZoom(
                              key: _pinchKey,
                              fontSize: widget.settings.fontSize,
                              onPinchStarted: _onPinchStarted,
                              onPinchEnded: _onPinchEnded,
                              onFontSizeChanged: _onPinchFontSize,
                              child: _portionMode
                                  ? _buildPortionList(ink)
                                  : _buildFullList(ink),
                            ),
                            if (!_portionMode) _arrangementChrome(context),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  void _onPinchStarted(Offset localFocal) {
    if (_portionMode) {
      if (_portionScroll.hasClients) {
        final pos = _portionScroll.position;
        final max = pos.maxScrollExtent;
        _pinchPortionScrollFrac =
            max <= 0 ? 0.0 : (pos.pixels / max).clamp(0.0, 1.0);
      }
      _pinchAnchorIndex = null;
      _pinchAnchorAlignment = null;
      return;
    }

    _pinchPortionScrollFrac = null;
    final box = _pinchKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 1.0;
    final frac = (localFocal.dy / height).clamp(0.0, 1.0);
    final positions = _positions.itemPositions.value;
    ItemPosition? hit;
    for (final position in positions) {
      if (position.itemLeadingEdge <= frac &&
          position.itemTrailingEdge > frac) {
        hit = position;
        break;
      }
    }
    hit ??= _topVisibleItemPosition(positions);
    if (hit == null) {
      _pinchAnchorIndex = null;
      _pinchAnchorAlignment = null;
      return;
    }
    _pinchAnchorIndex = hit.index;
    _pinchAnchorAlignment = hit.itemLeadingEdge.clamp(0.0, 0.9);
  }

  ItemPosition? _topVisibleItemPosition(Iterable<ItemPosition> positions) {
    ItemPosition? top;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0) continue;
      if (position.itemLeadingEdge >= 1) continue;
      if (top == null || position.itemLeadingEdge < top.itemLeadingEdge) {
        top = position;
      }
    }
    return top;
  }

  void _onPinchFontSize(double size) {
    widget.settings.setFontSize(size);
    _restorePinchAnchor();
  }

  void _onPinchEnded() {
    _restorePinchAnchor();
    _pinchAnchorIndex = null;
    _pinchAnchorAlignment = null;
    _pinchPortionScrollFrac = null;
  }

  void _restorePinchAnchor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_portionMode) {
        final frac = _pinchPortionScrollFrac;
        if (frac == null || !_portionScroll.hasClients) return;
        final max = _portionScroll.position.maxScrollExtent;
        _portionScroll.jumpTo((frac * max).clamp(0.0, max));
        return;
      }
      final index = _pinchAnchorIndex;
      final alignment = _pinchAnchorAlignment;
      if (index == null || alignment == null) return;
      if (!_itemScroll.isAttached) return;
      if (index < 0 || index >= _itemCount) return;
      _itemScroll.jumpTo(index: index, alignment: alignment);
    });
  }
}

class _EndPromptBar extends StatelessWidget {
  const _EndPromptBar({
    required this.title,
    required this.onYes,
    required this.onNo,
  });

  static const double _padTop = 16;
  static const double _padBottom = 18;
  static const double _titleGap = 12;
  static const double _buttonHeight = 44;
  static const double _titleHeight = 16 * 1.45;
  static const double contentHeight =
      _padTop + _titleHeight + _titleGap + _buttonHeight + _padBottom;

  final String title;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1C140C);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AppTheme.bottomBarGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 16,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, _padTop, 16, _padBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: _titleGap),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ink,
                          minimumSize: const Size.fromHeight(_buttonHeight),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onYes,
                        child: const Text(
                          'Yes',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.black.withValues(alpha: 0.22),
                          side: const BorderSide(color: Colors.white, width: 1.4),
                          minimumSize: const Size.fromHeight(_buttonHeight),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onNo,
                        child: const Text(
                          'No',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionDialog extends StatelessWidget {
  const _CompletionDialog({required this.surahs});

  final List<RecommendedSurah> surahs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;

    final tileH = AppDimens.hubTileHeightOf(context);
    const tileRadius = BorderRadius.all(Radius.circular(14));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 640),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.orange.withValues(alpha: isDark ? 0.55 : 0.35),
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'اَلْحَمْدُ لِلّٰهِ',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: QuranFont.base.copyWith(
                      color: AppTheme.orange,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      height: QuranFont.recommendedLineHeight * 0.85,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Today's recitation is complete. May Allah accept it.",
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.orange,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius: tileRadius,
                        ),
                      ),
                      onPressed: () => Navigator.of(context)
                          .pop(const _CompletionChoice.readMore()),
                      child: const Text(
                        'Read more today',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (surahs.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Today's surahs",
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final gap = AppDimens.hubGap;
                          final tileW = (constraints.maxWidth - gap) / 2;
                          return SingleChildScrollView(
                            child: Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final item in surahs)
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: tileRadius,
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        borderRadius: tileRadius,
                                        onTap: () => Navigator.of(context).pop(
                                          _CompletionChoice.surah(item.surah),
                                        ),
                                        child: Ink(
                                          decoration: const BoxDecoration(
                                            gradient: AppTheme.barGradient,
                                            borderRadius: tileRadius,
                                          ),
                                          child: Center(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal:
                                                    AppDimens.hubTilePadH,
                                                vertical:
                                                    AppDimens.hubTilePadV,
                                              ),
                                              child: Text(
                                                item.titleUr,
                                                textAlign: TextAlign.center,
                                                textDirection:
                                                    TextDirection.rtl,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: AppDimens.scaled(
                                                    context,
                                                    AppDimens.fontHubTile,
                                                  ),
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        side: BorderSide(color: ink.withValues(alpha: 0.35)),
                        shape: const RoundedRectangleBorder(
                          borderRadius: tileRadius,
                        ),
                      ),
                      onPressed: () => Navigator.of(context)
                          .pop(const _CompletionChoice.sadaqaAllah()),
                      child: Text(
                        'صدق اللہ العظیم',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
