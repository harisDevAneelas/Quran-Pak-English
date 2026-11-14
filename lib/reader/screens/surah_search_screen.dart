import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../data/arabic_verse_search.dart';
import '../../data/quran_metadata.dart';
import '../widgets/reader_page_scaffold.dart';

/// Arabic mushaf-word search. Pops with `(surah, ayah)` for the chosen hit.
class SurahSearchScreen extends StatefulWidget {
  const SurahSearchScreen({super.key});

  @override
  State<SurahSearchScreen> createState() => _SurahSearchScreenState();
}

class _SurahSearchScreenState extends State<SurahSearchScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  bool _indexReady = false;
  String? _indexError;
  List<ArabicVerseHit> _hits = const [];
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _prepareIndex();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _prepareIndex() async {
    try {
      await QuranMetadata.load();
      await ArabicVerseSearch.ensureReady();
      if (!mounted) return;
      setState(() {
        _indexReady = true;
        _indexError = null;
      });
      _runSearch(_query.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _indexReady = false;
        _indexError = e.toString();
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _runSearch(value);
    });
  }

  void _runSearch(String raw) {
    if (!_indexReady) {
      setState(() {
        _hits = const [];
        _activeQuery = raw.trim();
      });
      return;
    }
    final hits = ArabicVerseSearch.search(raw);
    setState(() {
      _hits = hits;
      _activeQuery = raw.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;

    return ReaderPageScaffold(
      title: 'Search',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _SearchQueryField(
              controller: _query,
              ink: ink,
              muted: muted,
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(child: _body(context, ink: ink, muted: muted)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required Color ink,
    required Color muted,
  }) {
    if (_indexError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Search could not be prepared.\nPlease restart the app',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: muted, height: 1.5),
          ),
        ),
      );
    }

    if (!_indexReady) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeQuery.isEmpty) {
      return Center(
        child: Text(
          'Type an Arabic word from the Quran',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 15, color: muted),
        ),
      );
    }

    if (_hits.isEmpty) {
      return Center(
        child: Text(
          'No results',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 15, color: muted),
        ),
      );
    }

    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hit = _hits[index];
        final surahName = QuranMetadata.nameArOrEmpty(hit.surah);
        final label = surahName.isEmpty
            ? 'Surah ${hit.surah} · Ayah ${hit.ayah}'
            : '$surahName · Ayah ${hit.ayah}';
        return ListTile(
          onTap: () => Navigator.of(context).pop<({int surah, int ayah})>((
            surah: hit.surah,
            ayah: hit.ayah,
          )),
          title: Text(
            hit.word,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: QuranFont.family,
              fontSize: 22,
              height: QuranFont.recommendedLineHeight * 0.85,
              color: ink,
            ),
          ),
          subtitle: Text(
            label,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        );
      },
    );
  }
}

/// Outline drawn by us; Material borders are all [InputBorder.none] so M3 cannot
/// paint its filled active-indicator line when the field has text.
class _SearchQueryField extends StatefulWidget {
  const _SearchQueryField({
    required this.controller,
    required this.ink,
    required this.muted,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Color ink;
  final Color muted;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<_SearchQueryField> {
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final borderColor =
        focused ? AppTheme.orange : widget.muted.withValues(alpha: 0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        textDirection: TextDirection.rtl,
        autofocus: true,
        onChanged: widget.onChanged,
        autocorrect: false,
        enableSuggestions: false,
        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
        style: TextStyle(fontSize: 18, color: widget.ink),
        cursorColor: AppTheme.orange,
        decoration: InputDecoration(
          hintText: 'Type an Arabic word',
          hintTextDirection: TextDirection.rtl,
          hintStyle: TextStyle(color: widget.muted, fontSize: 16),
          prefixIcon: Icon(Icons.search, color: widget.muted),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
