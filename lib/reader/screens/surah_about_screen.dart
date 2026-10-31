import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../core/app_dimens.dart';
import '../../data/quran_metadata.dart';
import '../widgets/reader_page_scaffold.dart';

/// Surah facts and intro from the `Sura` table.
/// Pops `true` when the reader should jump there.
class SurahAboutScreen extends StatelessWidget {
  const SurahAboutScreen({super.key, required this.surah});

  final int surah;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ReaderPageScaffold(
      title: 'About this surah',
      body: FutureBuilder<QuranMetadata>(
        future: QuranMetadata.load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final catalog = snap.data!;
          final meta = catalog.surahs[surah - 1];
          final juz = meta.juzNum != null ? catalog.juzAt(meta.juzNum!) : null;
          final revelation = meta.revelationLabel;

          return Directionality(
            textDirection: TextDirection.ltr,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                if (meta.nameAr.isNotEmpty)
                  Text(
                    meta.nameAr,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: QuranFont.family,
                      fontSize: 40,
                      height: QuranFont.recommendedLineHeight,
                    ),
                  ),
                if (meta.englishName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    meta.englishName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                if (meta.englishNameTranslation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    meta.englishNameTranslation,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                _FactRow(label: 'Number', value: '${meta.surah}'),
                _FactRow(label: 'Ayahs', value: '${meta.ayahCount}'),
                if (revelation.isNotEmpty)
                  _FactRow(label: 'Revelation', value: revelation),
                if (meta.juzNum != null)
                  _FactRow(
                    label: 'Para',
                    value: juz == null
                        ? '${meta.juzNum}'
                        : '${meta.juzNum} · ${juz.displayName}',
                  ),
                if (meta.pageNum != null)
                  _FactRow(label: 'Page', value: '${meta.pageNum}'),
                if (meta.chronologicalOrder != null)
                  _FactRow(
                    label: 'Revelation order',
                    value: '${meta.chronologicalOrder} / 114',
                  ),
                if (meta.intro.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Introduction',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.orangeDeep,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    meta.intro,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.75,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Center(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(200, 48),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const ScreenFitText(
                      'Go to this surah',
                      maxLines: 1,
                      minFontSize: AppDimens.fontSurahJumpMin,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppDimens.fontSurahJump,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}
