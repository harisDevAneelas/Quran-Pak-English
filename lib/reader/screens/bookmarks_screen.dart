import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/quran_metadata.dart';
import '../bookmark_store.dart';
import '../index_bookmark_store.dart';
import '../pinned_surah_store.dart';
import '../widgets/reader_page_scaffold.dart';

/// Jump target from Bookmarks (surah header, para start, or ayah).
typedef BookmarkJump = ({int surah, int ayah, bool openAtSurahHeader});

/// Saved surah / para / ayah bookmarks. Pops with a [BookmarkJump].
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({
    super.key,
    required this.bookmarkStore,
    required this.indexBookmarkStore,
    required this.pinnedSurahStore,
  });

  final BookmarkStore bookmarkStore;
  final IndexBookmarkStore indexBookmarkStore;
  final PinnedSurahStore pinnedSurahStore;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<int> _surahs = const [];
  List<int> _paras = const [];
  List<({int surah, int ayah})> _ayahs = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await QuranMetadata.load();
    final surahs = await widget.indexBookmarkStore.loadSurahs();
    final paras = await widget.indexBookmarkStore.loadParas();
    final ayahs = await widget.bookmarkStore.load();
    if (!mounted) return;
    setState(() {
      // Keep mark order (first bookmarked first), not surah/para number.
      _surahs = List<int>.from(surahs);
      _paras = List<int>.from(paras);
      _ayahs = ayahs;
      _ready = true;
    });
  }

  Future<void> _removeSurah(int surah) async {
    await widget.indexBookmarkStore.setSurahBookmarked(surah, false);
    await widget.pinnedSurahStore.setPinned(surah, false);
    await _reload();
  }

  Future<void> _removePara(int para) async {
    await widget.indexBookmarkStore.setParaBookmarked(para, false);
    await _reload();
  }

  Future<void> _removeAyah(({int surah, int ayah}) item) async {
    await widget.bookmarkStore.remove(surah: item.surah, ayah: item.ayah);
    await _reload();
  }

  bool get _isEmpty =>
      _surahs.isEmpty && _paras.isEmpty && _ayahs.isEmpty;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;

    return ReaderPageScaffold(
      title: 'Bookmarks',
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _isEmpty
              ? Center(
                  child: Text(
                    'No bookmarks yet',
                    style: TextStyle(fontSize: 16, color: ink),
                  ),
                )
              : ListView(
                  children: [
                    if (_surahs.isNotEmpty) ...[
                      _SectionHeader(label: 'Surah', ink: ink),
                      for (final surah in _surahs)
                        _SurahRow(
                          surah: surah,
                          onTap: () {
                            Navigator.of(context).pop<BookmarkJump>((
                              surah: surah,
                              ayah: 1,
                              openAtSurahHeader: true,
                            ));
                          },
                          onRemove: () => _removeSurah(surah),
                        ),
                    ],
                    if (_paras.isNotEmpty) ...[
                      _SectionHeader(label: 'Para', ink: ink),
                      for (final para in _paras)
                        _ParaRow(
                          para: para,
                          onTap: () {
                            final meta = QuranMetadata.juzOrNull(para);
                            if (meta == null) return;
                            Navigator.of(context).pop<BookmarkJump>((
                              surah: meta.startSurah,
                              ayah: meta.startAyah,
                              openAtSurahHeader: false,
                            ));
                          },
                          onRemove: () => _removePara(para),
                        ),
                    ],
                    if (_ayahs.isNotEmpty) ...[
                      _SectionHeader(label: 'Ayahs', ink: ink),
                      for (final item in _ayahs)
                        _AyahRow(
                          item: item,
                          onTap: () {
                            Navigator.of(context).pop<BookmarkJump>((
                              surah: item.surah,
                              ayah: item.ayah,
                              openAtSurahHeader: false,
                            ));
                          },
                          onRemove: () => _removeAyah(item),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.ink});

  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppTheme.orangeDeep,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SurahRow extends StatelessWidget {
  const _SurahRow({
    required this.surah,
    required this.onTap,
    required this.onRemove,
  });

  final int surah;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = QuranMetadata.surahOrNull(surah);
    final title = meta?.listTitle.isNotEmpty == true
        ? meta!.listTitle
        : 'Surah $surah';
    return ListTile(
      onTap: onTap,
      title: Text(title),
      subtitle: Text('Surah $surah'),
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _ParaRow extends StatelessWidget {
  const _ParaRow({
    required this.para,
    required this.onTap,
    required this.onRemove,
  });

  final int para;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = QuranMetadata.juzOrNull(para);
    final name = meta?.displayName ?? '';
    final title = name.isEmpty ? 'Para $para' : 'Para $para · $name';
    return ListTile(
      onTap: onTap,
      title: Text(title),
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _AyahRow extends StatelessWidget {
  const _AyahRow({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final ({int surah, int ayah}) item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = QuranMetadata.surahOrNull(item.surah);
    final title = meta?.listTitle.isNotEmpty == true
        ? meta!.listTitle
        : 'Surah ${item.surah}';
    final subtitleParts = <String>[
      'Ayah ${item.ayah}',
      if (meta?.juzNum != null) 'Para ${meta!.juzNum}',
    ];
    return ListTile(
      onTap: onTap,
      title: Text(title),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: onRemove,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}
