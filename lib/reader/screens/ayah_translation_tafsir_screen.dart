import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/quran_metadata.dart';
import '../../data/quran_models.dart';
import '../../data/quran_repository.dart';
import '../../data/translation_catalog.dart';
import '../../data/translation_repository.dart';
import '../reader_settings.dart';
import '../widgets/quran_ayah_widget.dart';
import '../widgets/reader_page_scaffold.dart';

/// One ayah: all translation columns, then tafsir-style works.
class AyahTranslationTafsirScreen extends StatefulWidget {
  const AyahTranslationTafsirScreen({
    super.key,
    required this.surah,
    required this.ayah,
    required this.settings,
  });

  final int surah;
  final int ayah;
  final ReaderSettings settings;

  @override
  State<AyahTranslationTafsirScreen> createState() =>
      _AyahTranslationTafsirScreenState();
}

class _AyahTranslationTafsirScreenState
    extends State<AyahTranslationTafsirScreen> {
  final _translations = TranslationRepository();
  QuranAyahChunk? _chunk;
  Map<String, String> _texts = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await QuranMetadata.load();
      final full = await QuranDataRepository().loadFull();
      final chunk = full.ayahAt(widget.surah, widget.ayah);
      final texts = await _translations.textsForAyah(
        widget.surah,
        widget.ayah,
      );
      if (!mounted) return;
      setState(() {
        _chunk = chunk;
        _texts = texts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final name = QuranMetadata.nameArOrEmpty(widget.surah);
    final heading = name.isEmpty
        ? 'Surah ${widget.surah} · Ayah ${widget.ayah}'
        : '$name · Ayah ${widget.ayah}';

    final translations = <TranslationOption>[
      for (final option in TranslationCatalog.all)
        if (!TranslationCatalog.isTafsir(option.id) &&
            (_texts[option.id]?.isNotEmpty ?? false))
          option,
    ];
    final tafsirs = <TranslationOption>[
      for (final option in TranslationCatalog.all)
        if (TranslationCatalog.isTafsir(option.id) &&
            (_texts[option.id]?.isNotEmpty ?? false))
          option,
    ];

    return ReaderPageScaffold(
      title: 'Translation and tafsir',
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
                return Directionality(
                  textDirection: TextDirection.ltr,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Text(
                        heading,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.orange,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_chunk != null)
                        QuranAyahWidget(
                          ayah: _chunk!,
                          fontSize: widget.settings.fontSize,
                          tajweedEnabled: widget.settings.tajweedEnabled,
                          inkColor: ink,
                        ),
                      const SizedBox(height: 20),
                      _SectionTitle(label: 'Translations'),
                      const SizedBox(height: 8),
                      for (final option in translations)
                        _TextCard(
                          title: option.label,
                          text: _texts[option.id]!,
                          ltr: TranslationCatalog.isLtr(option.id),
                        ),
                      if (translations.isEmpty)
                        const _EmptyNote(text: 'No translation is available for this ayah'),
                      const SizedBox(height: 20),
                      _SectionTitle(label: 'Tafsir'),
                      const SizedBox(height: 8),
                      for (final option in tafsirs)
                        _TextCard(
                          title: option.label,
                          text: _texts[option.id]!,
                          ltr: TranslationCatalog.isLtr(option.id),
                        ),
                      if (tafsirs.isEmpty)
                        const _EmptyNote(text: 'Tafsir for this ayah is not available yet'),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTheme.orange,
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.title,
    required this.text,
    required this.ltr,
  });

  final String title;
  final String text;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : AppTheme.orange.withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textDirection: ltr ? TextDirection.ltr : TextDirection.ltr,
                textAlign: ltr ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.7,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
