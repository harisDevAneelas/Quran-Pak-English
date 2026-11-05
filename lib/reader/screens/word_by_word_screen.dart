import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/app_theme.dart';
import '../../core/mushaf_layout.dart';
import '../../core/quran_font.dart';
import '../../core/surah_ayah_counts.dart';
import '../../data/quran_metadata.dart';
import '../../data/quran_repository.dart';
import '../../data/word_by_word_repository.dart';
import '../reader_settings.dart';
import '../widgets/mushaf_pinch_zoom.dart';
import '../widgets/reader_page_scaffold.dart';
import '../widgets/surah_ayah_picker_sheet.dart';
import '../widgets/surah_header_banner.dart';

/// Continuous word-by-word reader using the same mushaf list indices / scrolling
/// as [QuranReaderScreen].
///
/// Each cell is one `[arabic: urdu]` pair from `WordsbyWordsPaired`. Arabic is
/// painted with the IndoPak face that matches that wording.
///
/// Pops with `({int surah, int ayah})` for the ayah the user was viewing.
class WordByWordScreen extends StatefulWidget {
  const WordByWordScreen({
    super.key,
    required this.surah,
    required this.ayah,
    required this.settings,
  });

  final int surah;
  final int ayah;
  final ReaderSettings settings;

  @override
  State<WordByWordScreen> createState() => _WordByWordScreenState();
}

class _WordByWordScreenState extends State<WordByWordScreen> {
  late final Future<void> _bootstrap;
  late final int _initialScrollIndex;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  final Set<int> _loadedSurahs = {};
  final Set<int> _loadingSurahs = {};

  /// Paired glosses for ayahs already loaded. Avoids a map lookup rebuild.
  final Map<String, List<WordByWordPair>> _pairCache = {};

  late int _visibleSurah;
  late int _visibleAyah;

  final GlobalKey _pinchKey = GlobalKey();
  int? _pinchAnchorIndex;
  double? _pinchAnchorAlignment;

  @override
  void initState() {
    super.initState();
    final surah = widget.surah.clamp(1, 114);
    final ayah = widget.ayah.clamp(1, SurahAyahCounts.of(surah));
    _initialScrollIndex = MushafLayout.indexOfAyah(surah, ayah);
    _visibleSurah = surah;
    _visibleAyah = ayah;

    _bootstrap = _ensureSurah(_visibleSurah);
    widget.settings.addListener(_onSettingsChanged);
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    super.dispose();
  }

  void _onSettingsChanged() {
    // Font size only affects layout metrics; keep pair cache.
    if (mounted) setState(() {});
  }

  void _onPinchStarted(Offset localFocal) {
    final box = _pinchKey.currentContext?.findRenderObject() as RenderBox?;
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

  void _onItemPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    ItemPosition? topAyah;
    ItemPosition? topAny;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0) continue;
      if (p.itemLeadingEdge >= 1) continue;
      if (p.index < 0 || p.index >= MushafLayout.itemCount) continue;

      if (topAny == null || p.itemLeadingEdge < topAny.itemLeadingEdge) {
        topAny = p;
      }
      if (MushafLayout.slotAt(p.index) is! MushafAyahSlot) continue;
      if (topAyah == null || p.itemLeadingEdge < topAyah.itemLeadingEdge) {
        topAyah = p;
      }
    }

    final index = topAyah?.index ?? topAny?.index;
    if (index == null) return;

    final slot = MushafLayout.slotAt(index);
    final surah = switch (slot) {
      MushafHeaderSlot(:final surah) => surah,
      MushafAyahSlot(:final surah) => surah,
    };
    final ayah = switch (slot) {
      MushafHeaderSlot() => 1,
      MushafAyahSlot(:final ayah) => ayah,
    };

    if (surah == _visibleSurah && ayah == _visibleAyah) return;
    setState(() {
      _visibleSurah = surah;
      _visibleAyah = ayah;
    });
  }

  Future<void> _openSurahAyahPicker() async {
    final picked = await showSurahAyahPickerSheet(
      context: context,
      initialSurah: _visibleSurah,
      initialAyah: _visibleAyah,
    );
    if (!mounted || picked == null) return;
    _jumpToAyah(picked.surah, picked.ayah);
  }

  void _jumpToAyah(int surah, int ayah) {
    final clampedSurah = surah.clamp(1, 114);
    final clampedAyah = ayah.clamp(1, SurahAyahCounts.of(clampedSurah));
    final index = MushafLayout.indexOfAyah(
      clampedSurah,
      clampedAyah,
    ).clamp(0, MushafLayout.itemCount - 1);
    setState(() {
      _visibleSurah = clampedSurah;
      _visibleAyah = clampedAyah;
    });
    if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: index, alignment: 0);
    }
    _ensureSurah(clampedSurah);
  }

  Widget _surahAyahTitle(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: _openSurahAyahPicker,
      behavior: HitTestBehavior.opaque,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: QuranMetadata.surahOrNull(_visibleSurah)?.listTitle ??
                  QuranMetadata.nameArOrEmpty(_visibleSurah),
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: QuranFont.family,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            TextSpan(
              text: '  ·  $_visibleAyah',
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
  }

  Future<void> _ensureSurah(int surah) async {
    if (surah < 1 || surah > 114) return;
    if (_loadedSurahs.contains(surah) || _loadingSurahs.contains(surah)) {
      return;
    }
    _loadingSurahs.add(surah);
    try {
      await WordByWordRepository.ensureSurahLoaded(surah);
      if (!mounted) return;
      // Urdu just arrived — invalidate cached pairs for this surah.
      _pairCache.removeWhere((key, _) => key.startsWith('$surah:'));
      setState(() {
        _loadedSurahs.add(surah);
        _loadingSurahs.remove(surah);
      });
    } catch (error, stack) {
      debugPrint('WBW surah $surah load failed: $error\n$stack');
      if (!mounted) return;
      setState(() => _loadingSurahs.remove(surah));
      rethrow;
    }
  }

  void _prefetchAround(int listIndex) {
    if (listIndex < 0 || listIndex >= MushafLayout.itemCount) return;
    final slot = MushafLayout.slotAt(listIndex);
    final surah = switch (slot) {
      MushafHeaderSlot(:final surah) => surah,
      MushafAyahSlot(:final surah) => surah,
    };
    final surahs = <int>{surah};
    if (surah > 1) surahs.add(surah - 1);
    if (surah < 114) surahs.add(surah + 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final s in surahs) {
        _ensureSurah(s);
      }
    });
  }

  void _popWithVisibleAyah() {
    Navigator.of(context).pop<({int surah, int ayah})>((
      surah: _visibleSurah,
      ayah: _visibleAyah,
    ));
  }

  List<WordByWordPair> _pairsFor(int surah, int ayah) {
    final key = '$surah:$ayah';
    final cached = _pairCache[key];
    if (cached != null && cached.isNotEmpty) return cached;

    final pairs = WordByWordRepository.pairsFor(surah: surah, ayah: ayah);
    if (_loadedSurahs.contains(surah)) {
      _pairCache[key] = pairs;
    }
    return pairs;
  }

  /// Smaller text → more boxes per row (about 2–3 at large sizes).
  static int columnsForFontSize(double fontSize) {
    if (fontSize >= 48) return 2;
    if (fontSize >= 36) return 3;
    if (fontSize >= 28) return 4;
    return 5;
  }

  /// Caps columns so each IndoPak box stays wide enough on narrow phones.
  static int columnsForWidth({
    required double fontSize,
    required double maxWidth,
  }) {
    const gap = 6.0;
    final byFont = columnsForFontSize(fontSize);
    final arabicSize = (fontSize * 0.72).clamp(16.0, 44.0);
    final minBox = arabicSize * 2.2;
    var columns = byFont;
    while (columns > 2) {
      final boxW = (maxWidth - gap * (columns - 1)) / columns;
      if (boxW >= minBox) break;
      columns--;
    }
    return columns;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = widget.settings.fontSize;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popWithVisibleAyah();
      },
      child: ReaderPageScaffold(
        title: 'Word by word',
        titleWidget: _surahAyahTitle(context),
        body: FutureBuilder<void>(
          future: _bootstrap,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Translation could not be loaded.\nPlease restart the app',
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              );
            }

            return Directionality(
              textDirection: TextDirection.ltr,
              child: MushafPinchZoom(
                key: _pinchKey,
                fontSize: fontSize,
                onPinchStarted: _onPinchStarted,
                onPinchEnded: _onPinchEnded,
                onFontSizeChanged: _onPinchFontSize,
                child: Builder(
                  builder: (context) {
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ScrollablePositionedList.builder(
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        physics: MushafPinchLock.of(context)
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        initialScrollIndex: _initialScrollIndex.clamp(
                          0,
                          MushafLayout.itemCount - 1,
                        ),
                        itemCount: MushafLayout.itemCount,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        // Prefetch more off-screen rows so fling stays smooth.
                        minCacheExtent: 1200,
                        addAutomaticKeepAlives: false,
                        itemBuilder: (context, index) {
                          _prefetchAround(index);
                          final slot = MushafLayout.slotAt(index);
                          return switch (slot) {
                            MushafHeaderSlot(:final surah) => _SurahHeader(
                              key: ValueKey('wbw-h-$surah'),
                              surah: surah,
                            ),
                            MushafAyahSlot(:final surah, :final ayah) =>
                              _AyahBlock(
                                key: ValueKey('wbw-a-$surah-$ayah'),
                                surah: surah,
                                ayah: ayah,
                                pairs: _pairsFor(surah, ayah),
                                fontSize: fontSize,
                                loadingUrdu: !_loadedSurahs.contains(surah) &&
                                    _loadingSurahs.contains(surah),
                              ),
                          };
                        },
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({super.key, required this.surah});

  final int surah;

  @override
  Widget build(BuildContext context) {
    final header = MushafLayout.headerFor(surah);
    return SurahHeaderBanner(
      surah: header.surah,
      nameAr: header.nameAr,
      bismillah: QuranDataRepository().bismillah,
    );
  }
}

class _AyahBlock extends StatelessWidget {
  const _AyahBlock({
    super.key,
    required this.surah,
    required this.ayah,
    required this.pairs,
    required this.fontSize,
    required this.loadingUrdu,
  });

  final int surah;
  final int ayah;
  final List<WordByWordPair> pairs;
  final double fontSize;
  final bool loadingUrdu;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = QuranMetadata.surahOrNull(surah);
    final titleName = meta?.listTitle.isNotEmpty == true
        ? meta!.listTitle
        : 'Surah $surah';

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(
              '$titleName · Ayah $ayah',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.orangeDeep.withValues(alpha: 0.9),
              ),
            ),
          ),
          if (loadingUrdu && pairs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (pairs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Word-by-word is not available for this ayah',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = _WordByWordScreenState.columnsForWidth(
                  fontSize: fontSize,
                  maxWidth: constraints.maxWidth,
                );
                final boxWidth =
                    (constraints.maxWidth - _gap * (columns - 1)) / columns;
                return Column(
                  children: [
                    for (var start = 0; start < pairs.length; start += columns)
                      Padding(
                        padding: const EdgeInsets.only(bottom: _gap),
                        child: IntrinsicHeight(
                          child: Row(
                            textDirection: TextDirection.rtl,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var index = start;
                                index < start + columns && index < pairs.length;
                                index++
                              )
                                Padding(
                                  padding: EdgeInsetsDirectional.only(
                                    start: index == start ? 0 : _gap,
                                  ),
                                  child: SizedBox(
                                    width: boxWidth,
                                    child: _WordBox(
                                      arabic: pairs[index].arabic,
                                      gloss: pairs[index].gloss,
                                      fontSize: fontSize,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
    );
  }
}

/// Arabic from `Quran.words`, painted with the IndoPak face.
class _WordBox extends StatelessWidget {
  const _WordBox({
    required this.arabic,
    required this.gloss,
    required this.fontSize,
  });

  final String arabic;
  final String gloss;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    final arabicSize = (fontSize * 0.72).clamp(16.0, 44.0);
    final glossSize = (fontSize * 0.34).clamp(11.0, 18.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.7,
        ),
      ),
      // IndoPak ink exceeds metrics — do not clip mid-glyph.
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize >= 40 ? 8 : 6,
          vertical: fontSize >= 40 ? 10 : 8,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              arabic,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              softWrap: true,
              style: TextStyle(
                fontFamily: QuranFont.wordByWordFamily,
                fontFamilyFallback: const [],
                fontSize: arabicSize,
                height: QuranFont.wordByWordLineHeight,
                letterSpacing: 0,
                wordSpacing: 0,
                color: ink,
              ),
            ),
            if (gloss.isNotEmpty) ...[
              SizedBox(height: fontSize >= 40 ? 5 : 3),
              Text(
                gloss,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                softWrap: true,
                style: TextStyle(
                  fontSize: glossSize,
                  height: 1.3,
                  letterSpacing: 0,
                  color: ink.withValues(alpha: 0.72),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
