import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/mushaf_script.dart';
import '../../data/ayah_ref.dart';
import '../../data/quran_metadata.dart';
import '../../data/quran_models.dart';
import '../../data/quran_repository.dart';
import '../../data/verse_collection_repository.dart';
import '../../data/verse_collections.dart';
import '../reader_settings.dart';
import '../widgets/mushaf_pinch_zoom.dart';
import '../widgets/quran_ayah_widget.dart';
import '../widgets/reader_page_scaffold.dart';
import '../widgets/recitation_bismillah.dart';

class VerseCollectionScreen extends StatefulWidget {
  const VerseCollectionScreen({
    super.key,
    required this.collection,
    required this.settings,
  });

  /// Seeded IndoPak `DuaWords` + ayah refs from `QuraniDua`.
  final VerseCollection collection;
  final ReaderSettings settings;

  @override
  State<VerseCollectionScreen> createState() => _VerseCollectionScreenState();
}

class _VerseCollectionScreenState extends State<VerseCollectionScreen> {
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final GlobalKey _pinchKey = GlobalKey();

  int? _pinchAnchorIndex;
  double? _pinchAnchorAlignment;
  int _initialScrollIndex = 0;
  double _initialAlignment = 0;
  int _listEpoch = 0;

  late MushafScript _script = widget.settings.mushafScript;
  VerseCollection? _resolved;
  String? _bismillah;
  bool _loading = true;
  int _loadGen = 0;

  int get _itemCount {
    final groups = _resolved?.groups.length ?? 0;
    return groups + 1;
  }

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    _reloadForScript(_script);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    final next = widget.settings.mushafScript;
    if (next == _script && _resolved != null) return;
    _captureScrollAnchorForScriptSwitch();
    _script = next;
    _reloadForScript(next, preserveVisible: true);
  }

  void _captureScrollAnchorForScriptSwitch() {
    final top = _topVisibleItemPosition(_positions.itemPositions.value);
    if (top == null) {
      _initialScrollIndex = 0;
      _initialAlignment = 0;
      return;
    }
    _initialScrollIndex = top.index;
    _initialAlignment = top.itemLeadingEdge.clamp(0.0, 0.85);
  }

  Future<void> _reloadForScript(
    MushafScript script, {
    bool preserveVisible = false,
  }) async {
    final gen = ++_loadGen;
    setState(() => _loading = true);
    final resolved =
        await VerseCollectionRepository.forScript(widget.collection, script);
    final repo = QuranDataRepository.forScript(script);
    if (repo.bismillah == null) {
      await repo.loadWindow(
        const AyahWindow(start: AyahRef.first, end: AyahRef(1, 1)),
      );
    }
    final bismillah = repo.bismillah?.words.map((w) => w.text).join(' ') ??
        QuranMetadata.bismillahTextOrEmpty(script: script);
    if (!mounted || gen != _loadGen) return;
    setState(() {
      _resolved = resolved;
      _bismillah = bismillah;
      if (preserveVisible) _listEpoch++;
      _loading = false;
    });
  }

  void _onPinchStarted(Offset localFocal) {
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
  }

  void _restorePinchAnchor() {
    final index = _pinchAnchorIndex;
    final alignment = _pinchAnchorAlignment;
    if (index == null || alignment == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScroll.isAttached) return;
      if (index < 0 || index >= _itemCount) return;
      _itemScroll.jumpTo(index: index, alignment: alignment);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = _resolved;

    return ReaderPageScaffold(
      title: widget.collection.title,
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final ink = theme.colorScheme.onSurface;
          if (_loading || resolved == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = resolved.groups;
          return MushafPinchZoom(
            key: _pinchKey,
            fontSize: widget.settings.fontSize,
            onPinchStarted: _onPinchStarted,
            onPinchEnded: _onPinchEnded,
            onFontSizeChanged: _onPinchFontSize,
            child: Builder(
              builder: (context) {
                return ScrollablePositionedList.builder(
                  key: ValueKey<String>(
                    'collection-${_script.name}-$_listEpoch',
                  ),
                  itemScrollController: _itemScroll,
                  itemPositionsListener: _positions,
                  initialScrollIndex: _initialScrollIndex.clamp(
                    0,
                    groups.isEmpty ? 0 : groups.length,
                  ),
                  initialAlignment: _initialAlignment,
                  physics: MushafPinchLock.of(context)
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                  itemCount: groups.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return RecitationBismillah(
                        text: _bismillah ?? '',
                        fontSize: widget.settings.fontSize,
                        inkColor: ink,
                      );
                    }
                    final group = groups[index - 1];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _VerseGroupCard(
                        group: group,
                        fontSize: widget.settings.fontSize,
                        tajweedEnabled: widget.settings.tajweedEnabled,
                        inkColor: ink,
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _VerseGroupCard extends StatelessWidget {
  const _VerseGroupCard({
    required this.group,
    required this.fontSize,
    required this.tajweedEnabled,
    required this.inkColor,
  });

  final VerseGroup group;
  final double fontSize;
  final bool tajweedEnabled;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final refs = group.ayahs;
    final first = refs.isEmpty ? const AyahRef(1, 1) : refs.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${group.number}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _refLabel(refs),
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (group.verses.isEmpty)
            Text(
              'Ayah is not available',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            )
          else
            for (var i = 0; i < group.verses.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: QuranAyahWidget(
                  key: ValueKey<String>(
                    '${i < refs.length ? refs[i].surah : first.surah}:'
                    '${i < refs.length ? refs[i].ayah : first.ayah}:'
                    '${group.verses[i].length}',
                  ),
                  ayah: QuranAyahChunk(
                    surah: i < refs.length ? refs[i].surah : first.surah,
                    ayah: i < refs.length ? refs[i].ayah : first.ayah,
                    words: group.verses[i],
                  ),
                  fontSize: fontSize,
                  tajweedEnabled: tajweedEnabled,
                  inkColor: inkColor,
                ),
              ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  String _refLabel(List<AyahRef> refs) {
    if (refs.isEmpty) return '';
    final first = refs.first;
    final name = QuranMetadata.nameArOrEmpty(first.surah);
    final surahLabel = name.isEmpty ? 'Surah ${first.surah}' : name;
    if (refs.length == 1) {
      return '$surahLabel · Ayah ${first.ayah}';
    }
    final last = refs.last;
    if (first.surah == last.surah) {
      return '$surahLabel · Ayah ${first.ayah}–${last.ayah}';
    }
    return '$surahLabel · Ayah ${first.ayah}…';
  }
}
