import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../core/app_dimens.dart';
import '../../data/quran_metadata.dart';
import '../../data/recommended_surah.dart';
import '../pinned_surah_store.dart';
import '../reader_nav_scope.dart';
import '../widgets/namaz_time_bar.dart';
import '../widgets/playing_ayah_bar.dart';
import '../widgets/reader_sidebar.dart';
import '../widgets/surah_ayah_picker_sheet.dart';

class HubMenuScreen extends StatefulWidget {
  const HubMenuScreen({
    super.key,
    required this.initialSurah,
    required this.initialAyah,
    required this.pinnedSurahStore,
    required this.onJumpToSurah,
    required this.onJumpToAyah,
    required this.onOpenManzilList,
    required this.onOpenTodaysRecitation,
    required this.onOpenDailyArrangement,
    required this.onOpenAyatEShifa,
    required this.onOpenFortyRabbana,
    required this.onOpenRuqyahShariah,
    this.onLocationUpdated,
  });

  final int initialSurah;
  final int initialAyah;
  final PinnedSurahStore pinnedSurahStore;
  final ValueChanged<int> onJumpToSurah;
  final void Function(int surah, int ayah) onJumpToAyah;
  final VoidCallback onOpenManzilList;
  final VoidCallback onOpenTodaysRecitation;
  final VoidCallback onOpenDailyArrangement;
  final VoidCallback onOpenAyatEShifa;
  final VoidCallback onOpenFortyRabbana;
  final VoidCallback onOpenRuqyahShariah;
  /// After hub bar obtains/refreshes GPS for namaz + prayer-anchored surah alerts.
  final Future<void> Function()? onLocationUpdated;

  @override
  State<HubMenuScreen> createState() => _HubMenuScreenState();
}

class _HubMenuScreenState extends State<HubMenuScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Set<int> _pinned = {};
  bool _pinsReady = false;
  String? _loadedForProfile;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    widget.pinnedSurahStore.addListener(_onPinnedStoreChanged);
    _loadPins();
  }

  @override
  void dispose() {
    widget.pinnedSurahStore.removeListener(_onPinnedStoreChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HubMenuScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pinnedSurahStore != widget.pinnedSurahStore) {
      oldWidget.pinnedSurahStore.removeListener(_onPinnedStoreChanged);
      widget.pinnedSurahStore.addListener(_onPinnedStoreChanged);
      _loadPins();
    }
  }

  void _onPinnedStoreChanged() {
    if (!mounted) return;
    _loadPins();
  }

  Future<void> _loadPins() async {
    final gen = ++_loadGen;
    final forProfile = widget.pinnedSurahStore.profileId;
    final pins = await widget.pinnedSurahStore.load();
    if (!mounted || gen != _loadGen) return;
    if (widget.pinnedSurahStore.profileId != forProfile) return;
    setState(() {
      _pinned = pins;
      _pinsReady = true;
      _loadedForProfile = forProfile;
    });
  }

  Future<void> _openSurahPicker() async {
    final surah = await showSurahListPickerSheet(
      context: context,
      initialSurah: widget.initialSurah,
    );
    if (!mounted || surah == null) return;
    widget.onJumpToSurah(surah);
  }

  Future<void> _openParaPicker() async {
    final picked = await showParaListPickerSheet(
      context: context,
      initialSurah: widget.initialSurah,
      initialAyah: widget.initialAyah,
    );
    if (!mounted || picked == null) return;
    widget.onJumpToAyah(picked.surah, picked.ayah);
  }

  Future<void> _openPinSheet() async {
    // Prefer store profile pins (not stale UI) after a mid-session switch.
    if (_loadedForProfile != widget.pinnedSurahStore.profileId) {
      await _loadPins();
      if (!mounted) return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PinnedSurahSheet(
        initial: Set<int>.from(_pinned),
        onChanged: (next) async {
          await widget.pinnedSurahStore.save(next);
          if (!mounted) return;
          if (widget.pinnedSurahStore.profileId != _loadedForProfile) {
            await _loadPins();
            return;
          }
          setState(() => _pinned = next);
        },
      ),
    );
  }

  List<_HubTile> _tiles(BuildContext context) {
    final timed = RecommendedSurahResolver.resolveMany();
    final timedIds = {for (final surah in timed) surah.surah};
    final shown = <int>{};
    final surahTiles = <_HubTile>[];

    void addSurah(RecommendedSurah surah, {required bool highlighted}) {
      if (!shown.add(surah.surah)) return;
      surahTiles.add(
        _HubTile(
          label: surah.titleUr,
          highlighted: highlighted,
          onTap: () => widget.onJumpToSurah(surah.surah),
        ),
      );
    }

    for (final id in _pinned) {
      final surah = OccasionSurahs.byId(id);
      if (surah != null) {
        addSurah(surah, highlighted: timedIds.contains(id));
      }
    }
    for (final surah in timed) {
      addSurah(surah, highlighted: true);
    }

    return [
      _HubTile(label: 'Surah list', onTap: _openSurahPicker),
      _HubTile(label: 'Para list', onTap: _openParaPicker),
      _HubTile(
        label: "Today's recitation",
        highlighted: true,
        onTap: widget.onOpenTodaysRecitation,
      ),
      _HubTile(label: 'Quick list', onTap: _openPinSheet),
      ...surahTiles,
      _HubTile(label: 'Ayaat-e-shifa', onTap: widget.onOpenAyatEShifa),
      _HubTile(label: 'Forty Rabbana', onTap: widget.onOpenFortyRabbana),
      _HubTile(label: 'Manzil', onTap: widget.onOpenManzilList),
      _HubTile(label: 'Ruqyah Shariah', onTap: widget.onOpenRuqyahShariah),
      _HubTile(
        label: 'Daily recitation plan',
        onTap: widget.onOpenDailyArrangement,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = _pinsReady ? _tiles(context) : const <_HubTile>[];
    final nav = ReaderNavScope.maybeOf(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: nav == null
          ? null
          : ReaderMenuDrawer(
              settings: nav.settings,
              activeProfileName: nav.profileName,
              onSurahSelected: nav.nav.jumpToSurah,
              onAyahSelected: nav.nav.jumpToAyah,
              onDestination: (destination) {
                _scaffoldKey.currentState?.closeDrawer();
                nav.nav.openDestination(destination);
              },
            ),
      appBar: AppBar(
        centerTitle: true,
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
        leading: nav == null
            ? null
            : IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu, size: 30),
              ),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 26),
          ),
        ],
        title: FutureBuilder<QuranMetadata>(
          future: QuranMetadata.load(),
          builder: (context, snap) {
            final text = snap.hasData
                ? snap.data!.bismillahWords.join(' ')
                : QuranMetadata.bismillahTextOrEmpty();
            return ScreenFitText(
              text,
              maxLines: 1,
              minFontSize: AppDimens.fontHubTitleMin,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: QuranFont.family,
                color: Colors.white,
                fontSize: AppDimens.fontHubTitle,
                fontWeight: FontWeight.w600,
                height: QuranFont.recommendedLineHeight * 0.75,
              ),
            );
          },
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = AppDimens.hubGap;
                  final tileHeight = AppDimens.hubTileHeightOf(context);
                  final tileWidth =
                      AppDimens.hubTileWidthOf(constraints.maxWidth);

                  const pad = EdgeInsets.fromLTRB(
                    AppDimens.hubPadH,
                    AppDimens.hubPadV,
                    AppDimens.hubPadH,
                    AppDimens.hubPadV,
                  );
                  final rows = (tiles.length / 2).ceil();
                  final needed = pad.vertical +
                      72 +
                      gap +
                      rows * tileHeight +
                      (rows - 1).clamp(0, 100) * gap;
                  final overflow = needed > constraints.maxHeight;

                  final content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NamazTimeBar(
                        onLocationUpdated: widget.onLocationUpdated,
                      ),
                      SizedBox(height: gap),
                      if (!_pinsReady)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        Align(
                          alignment: Alignment.topCenter,
                          child: Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final tile in tiles)
                                SizedBox(
                                  width: tileWidth,
                                  height: tileHeight,
                                  child: _HubTileButton(tile: tile),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );

                  if (!overflow) {
                    return Padding(padding: pad, child: content);
                  }

                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: pad,
                    child: content,
                  );
                },
              ),
            ),
          ),
          const Positioned.fill(child: PlayingAyahBarHost()),
        ],
      ),
    );
  }
}

class _PinnedSurahSheet extends StatefulWidget {
  const _PinnedSurahSheet({
    required this.initial,
    required this.onChanged,
  });

  final Set<int> initial;
  final ValueChanged<Set<int>> onChanged;

  @override
  State<_PinnedSurahSheet> createState() => _PinnedSurahSheetState();
}

class _PinnedSurahSheetState extends State<_PinnedSurahSheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<int>.from(widget.initial);
  }

  void _toggle(int surahId) {
    setState(() {
      if (_selected.contains(surahId)) {
        _selected.remove(surahId);
      } else {
        _selected.add(surahId);
      }
    });
    widget.onChanged(Set<int>.from(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Quick list',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Surahs you pick stay on the menu',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ink.withValues(alpha: 0.65),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.48,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: OccasionSurahs.all.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final surah = OccasionSurahs.all[index];
                    final selected = _selected.contains(surah.surah);
                    return Material(
                      color: selected
                          ? AppTheme.orange.withValues(alpha: 0.12)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: selected
                              ? AppTheme.orange
                              : ink.withValues(alpha: isDark ? 0.12 : 0.08),
                          width: selected ? 1.4 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _toggle(surah.surah),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected
                                    ? AppTheme.orange
                                    : ink.withValues(alpha: 0.28),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  surah.titleUr,
                                  textAlign: TextAlign.left,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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

class _HubTile {
  const _HubTile({
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool highlighted;
}

class _HubTileButton extends StatelessWidget {
  const _HubTileButton({required this.tile});

  final _HubTile tile;

  static const _tileGrey = Color(0xFF5A5A5A);

  static const _highlightGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppTheme.orangeDeep,
      AppTheme.orange,
      AppTheme.orangeLight,
      AppTheme.orange,
      AppTheme.orangeDeep,
    ],
    stops: [0.0, 0.22, 0.5, 0.78, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(14));

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: tile.onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: tile.highlighted ? null : _tileGrey,
            gradient: tile.highlighted ? _highlightGradient : null,
            borderRadius: radius,
          ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.hubTilePadH,
                vertical: AppDimens.hubTilePadV,
              ),
              child: Center(
                child: ScreenFitText(
                  tile.label,
                  maxLines: 2,
                  minFontSize: AppDimens.fontHubTileMin,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppDimens.scaled(context, AppDimens.fontHubTile),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
          ),
        ),
      ),
    );
  }
}
