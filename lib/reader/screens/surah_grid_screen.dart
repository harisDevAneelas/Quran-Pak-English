import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_dimens.dart';
import '../../data/quran_metadata.dart';
import '../index_bookmark_store.dart';
import '../pinned_surah_store.dart';
import '../reader_nav_scope.dart';
import '../widgets/index_bookmark_strip.dart';
import '../widgets/index_grid_card.dart';
import '../widgets/reader_page_scaffold.dart';
import '../widgets/search_query_field.dart';

/// Searchable two-column grid of all 114 surahs.
class SurahGridScreen extends StatefulWidget {
  const SurahGridScreen({
    super.key,
    required this.indexBookmarkStore,
    required this.pinnedSurahStore,
  });

  final IndexBookmarkStore indexBookmarkStore;
  final PinnedSurahStore pinnedSurahStore;

  @override
  State<SurahGridScreen> createState() => _SurahGridScreenState();
}

class _SurahGridScreenState extends State<SurahGridScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<SurahMeta> _all = const [];
  List<SurahMeta> _filtered = const [];
  /// Mark order (first bookmarked first).
  List<int> _starred = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.indexBookmarkStore.addListener(_onStoreChanged);
    _load();
  }

  @override
  void dispose() {
    widget.indexBookmarkStore.removeListener(_onStoreChanged);
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SurahGridScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indexBookmarkStore != widget.indexBookmarkStore) {
      oldWidget.indexBookmarkStore.removeListener(_onStoreChanged);
      widget.indexBookmarkStore.addListener(_onStoreChanged);
      _loadStars();
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _loadStars();
  }

  Future<void> _load() async {
    final meta = await QuranMetadata.load();
    final stars = await widget.indexBookmarkStore.loadSurahs();
    if (!mounted) return;
    setState(() {
      _all = meta.surahs;
      _filtered = meta.surahs;
      _starred = stars;
      _ready = true;
    });
  }

  Future<void> _loadStars() async {
    final forProfile = widget.indexBookmarkStore.profileId;
    final stars = await widget.indexBookmarkStore.loadSurahs();
    if (!mounted) return;
    if (widget.indexBookmarkStore.profileId != forProfile) return;
    setState(() => _starred = stars);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _applyFilter(value);
    });
  }

  void _applyFilter(String raw) {
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() => _filtered = _all);
      return;
    }
    final scored = <({SurahMeta item, int score})>[];
    for (final s in _all) {
      final score = s.queryScore(q);
      if (score > 0) scored.add((item: s, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.item.surah.compareTo(b.item.surah);
    });
    setState(() {
      _filtered = scored.map((e) => e.item).toList(growable: false);
    });
  }

  void _openSurah(int surah) {
    ReaderNavScope.maybeOf(context)?.nav.jumpToSurah(surah);
  }

  Future<void> _toggleStar(int surah) async {
    final next = !_starred.contains(surah);
    setState(() {
      if (next) {
        _starred = [..._starred, surah];
      } else {
        _starred = [..._starred]..remove(surah);
      }
    });
    await widget.indexBookmarkStore.setSurahBookmarked(surah, next);
    await widget.pinnedSurahStore.setPinned(surah, next);
  }

  Map<int, String> _bookmarkLabels() {
    final out = <int, String>{};
    for (final id in _starred) {
      final meta = id >= 1 && id <= _all.length ? _all[id - 1] : null;
      out[id] = meta?.listTitle.isNotEmpty == true
          ? meta!.listTitle
          : '$id';
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final isDark = theme.brightness == Brightness.dark;
    final tileFill =
        isDark ? const Color(0xFF1C2420) : const Color(0xFFF7F3EE);

    return ReaderPageScaffold(
      title: 'Surah list',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.indexPadH,
              AppDimens.indexPadV,
              AppDimens.indexPadH,
              8,
            ),
            child: SearchQueryField(
              controller: _query,
              ink: ink,
              muted: muted,
              hintText: 'Search surahs',
              autofocus: false,
              onChanged: _onQueryChanged,
            ),
          ),
          if (_ready && _starred.isNotEmpty)
            IndexBookmarkStrip(
              labels: _bookmarkLabels(),
              ink: ink,
              muted: muted,
              onTap: _openSurah,
              onUnstar: _toggleStar,
            ),
          Expanded(
            child: !_ready
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No results',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: muted),
                        ),
                      )
                    : _buildGrid(
                        ink: ink,
                        tileFill: tileFill,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid({
    required Color ink,
    required Color tileFill,
  }) {
    final minHeight = AppDimens.indexTileMinHeightOf(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.indexPadH,
        4,
        AppDimens.indexPadH,
        AppDimens.indexPadV,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppDimens.indexGap,
        mainAxisSpacing: AppDimens.indexGap,
        mainAxisExtent: minHeight,
      ),
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final surah = _filtered[index];
        return IndexGridCard(
          fill: tileFill,
          badge: '${surah.surah}',
          title: surah.listTitle,
          ink: ink,
          onTap: () => _openSurah(surah.surah),
          starred: _starred.contains(surah.surah),
          onStarTap: () => _toggleStar(surah.surah),
        );
      },
    );
  }
}
