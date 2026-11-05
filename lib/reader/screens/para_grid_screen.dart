import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_dimens.dart';
import '../../data/quran_metadata.dart';
import '../index_bookmark_store.dart';
import '../reader_nav_scope.dart';
import '../widgets/index_bookmark_strip.dart';
import '../widgets/index_grid_card.dart';
import '../widgets/reader_page_scaffold.dart';
import '../widgets/search_query_field.dart';

/// Searchable two-column grid of all 30 paras.
class ParaGridScreen extends StatefulWidget {
  const ParaGridScreen({
    super.key,
    required this.indexBookmarkStore,
  });

  final IndexBookmarkStore indexBookmarkStore;

  @override
  State<ParaGridScreen> createState() => _ParaGridScreenState();
}

class _ParaGridScreenState extends State<ParaGridScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<JuzMeta> _all = const [];
  List<JuzMeta> _filtered = const [];
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
  void didUpdateWidget(covariant ParaGridScreen oldWidget) {
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
    final stars = await widget.indexBookmarkStore.loadParas();
    if (!mounted) return;
    setState(() {
      _all = meta.juz;
      _filtered = meta.juz;
      _starred = stars;
      _ready = true;
    });
  }

  Future<void> _loadStars() async {
    final forProfile = widget.indexBookmarkStore.profileId;
    final stars = await widget.indexBookmarkStore.loadParas();
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
    final scored = <({JuzMeta item, int score})>[];
    for (final j in _all) {
      final score = j.queryScore(q);
      if (score > 0) scored.add((item: j, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.item.juz.compareTo(b.item.juz);
    });
    setState(() {
      _filtered = scored.map((e) => e.item).toList(growable: false);
    });
  }

  void _openPara(JuzMeta para) {
    ReaderNavScope.maybeOf(context)?.nav.jumpToAyah(
      para.startSurah,
      para.startAyah,
    );
  }

  Future<void> _toggleStar(int para) async {
    final next = !_starred.contains(para);
    setState(() {
      if (next) {
        _starred = [..._starred, para];
      } else {
        _starred = [..._starred]..remove(para);
      }
    });
    await widget.indexBookmarkStore.setParaBookmarked(para, next);
  }

  Map<int, String> _bookmarkLabels() {
    final out = <int, String>{};
    for (final id in _starred) {
      JuzMeta? meta;
      for (final j in _all) {
        if (j.juz == id) {
          meta = j;
          break;
        }
      }
      final name = meta?.displayName ?? '';
      out[id] = name.isEmpty ? 'Para $id' : 'Para $id · $name';
    }
    return out;
  }

  void _openParaById(int juz) {
    for (final para in _all) {
      if (para.juz == juz) {
        _openPara(para);
        return;
      }
    }
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
      title: 'Para list',
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
              hintText: 'Search paras',
              autofocus: false,
              onChanged: _onQueryChanged,
            ),
          ),
          if (_ready && _starred.isNotEmpty)
            IndexBookmarkStrip(
              labels: _bookmarkLabels(),
              ink: ink,
              muted: muted,
              onTap: _openParaById,
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
        final para = _filtered[index];
        return IndexGridCard(
          fill: tileFill,
          badge: '${para.juz}',
          title: para.displayName,
          ink: ink,
          onTap: () => _openPara(para),
          starred: _starred.contains(para.juz),
          onStarTap: () => _toggleStar(para.juz),
        );
      },
    );
  }
}
