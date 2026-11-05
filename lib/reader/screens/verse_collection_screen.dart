import 'package:flutter/material.dart';

import '../../data/ayah_ref.dart';
import '../../data/quran_metadata.dart';
import '../../data/quran_models.dart';
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

  final VerseCollection collection;
  final ReaderSettings settings;

  @override
  State<VerseCollectionScreen> createState() => _VerseCollectionScreenState();
}

class _VerseCollectionScreenState extends State<VerseCollectionScreen> {
  late final Future<QuranMetadata> _metaFuture = QuranMetadata.load();
  final ScrollController _scroll = ScrollController();
  double? _pinchScrollFrac;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onPinchStarted(Offset _) {
    if (!_scroll.hasClients) {
      _pinchScrollFrac = null;
      return;
    }
    final pos = _scroll.position;
    final max = pos.maxScrollExtent;
    _pinchScrollFrac = max <= 0 ? 0.0 : (pos.pixels / max).clamp(0.0, 1.0);
  }

  void _onPinchFontSize(double size) {
    widget.settings.setFontSize(size);
    _restoreScrollFraction();
  }

  void _onPinchEnded() {
    _restoreScrollFraction();
    _pinchScrollFrac = null;
  }

  void _restoreScrollFraction() {
    final frac = _pinchScrollFrac;
    if (frac == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((frac * max).clamp(0.0, max));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ReaderPageScaffold(
      title: widget.collection.title,
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final ink = theme.colorScheme.onSurface;
          final groups = widget.collection.groups;
          return FutureBuilder<QuranMetadata>(
            future: _metaFuture,
            builder: (context, snap) {
              final bismillah = snap.hasData
                  ? snap.data!.bismillahWords.join(' ')
                  : QuranMetadata.bismillahTextOrEmpty();
              return MushafPinchZoom(
                fontSize: widget.settings.fontSize,
                onPinchStarted: _onPinchStarted,
                onPinchEnded: _onPinchEnded,
                onFontSizeChanged: _onPinchFontSize,
                child: Builder(
                  builder: (context) {
                    return ListView.builder(
                      controller: _scroll,
                      physics: MushafPinchLock.of(context)
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                      itemCount: groups.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return RecitationBismillah(
                            text: bismillah,
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
