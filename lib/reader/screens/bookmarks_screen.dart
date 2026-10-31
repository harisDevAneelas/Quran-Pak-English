import 'package:flutter/material.dart';

import '../../data/quran_metadata.dart';
import '../bookmark_store.dart';
import '../widgets/reader_page_scaffold.dart';

/// Saved ayah bookmarks. Pops with the chosen surah and ayah.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key, required this.bookmarkStore});

  final BookmarkStore bookmarkStore;

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<({int surah, int ayah})> _items = const [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await QuranMetadata.load();
    final items = await widget.bookmarkStore.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _ready = true;
    });
  }

  Future<void> _remove(({int surah, int ayah}) item) async {
    await widget.bookmarkStore.remove(surah: item.surah, ayah: item.ayah);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderPageScaffold(
      title: 'Bookmarks',
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Text(
                'No bookmarks yet',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            )
          : Directionality(
              textDirection: TextDirection.ltr,
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final meta = QuranMetadata.surahOrNull(item.surah);
                  final title = meta?.listTitle ??
                      (QuranMetadata.nameArOrEmpty(item.surah).isEmpty
                          ? 'Surah ${item.surah}'
                          : QuranMetadata.nameArOrEmpty(item.surah));
                  final subtitleParts = <String>[
                    'Ayah ${item.ayah}',
                    if (meta?.juzNum != null) 'Para ${meta!.juzNum}',
                  ];
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(item),
                    title: Text(
                      title,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                    ),
                    subtitle: Text(
                      subtitleParts.join(' · '),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _remove(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
