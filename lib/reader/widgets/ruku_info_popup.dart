import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../data/mushaf_divisions.dart';
import '../../data/quran_metadata.dart';

/// Short card of facts for the ruku that ends on [mark].
Future<void> showRukuInfoPopup({
  required BuildContext context,
  required RukuMarkInfo mark,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    // Instant blur — fading BackdropFilter looks delayed.
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _RukuInfoPopup(mark: mark);
    },
  );
}

class _RukuInfoPopup extends StatelessWidget {
  const _RukuInfoPopup({required this.mark});

  final RukuMarkInfo mark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final veil = isDark
        ? Colors.black.withValues(alpha: 0.62)
        : Colors.black.withValues(alpha: 0.38);
    final card = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final rowFill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : theme.colorScheme.onSurface.withValues(alpha: 0.05);
    final surahName = QuranMetadata.nameArOrEmpty(mark.end.surah);

    final para = MushafDivisions.cached?.paraOf(mark.end.surah, mark.end.ayah);
    final paraName = para == null ? '' : _paraName(para);
    final paraValue = para == null
        ? '—'
        : paraName.isEmpty
        ? '$para'
        : '$para · $paraName';

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: ColoredBox(color: veil),
            ),
          ),
          Center(
        child: Directionality(
          textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 280,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.orange.withValues(
                          alpha: isDark ? 0.55 : 0.35,
                        ),
                        width: 1.1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.orange.withValues(
                            alpha: isDark ? 0.14 : 0.1,
                          ),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          // Warm wash across the whole top of the card.
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 110,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      AppTheme.orange.withValues(
                                        alpha: isDark ? 0.28 : 0.18,
                                      ),
                                      AppTheme.orange.withValues(
                                        alpha: isDark ? 0.12 : 0.08,
                                      ),
                                      card.withValues(alpha: 0),
                                    ],
                                    stops: const [0.0, 0.45, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SingleChildScrollView(
                            child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  2,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: AppTheme.barGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.orange.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: const Text(
                                        'ع',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Ruku details',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                        color: ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  12,
                                ),
                                child: Column(
                                  children: [
                                    _Fact(
                                      label: 'Ruku in the para',
                                      value: '${mark.indexInPara}',
                                      ink: ink,
                                      muted: muted,
                                      rowFill: rowFill,
                                    ),
                                    _Fact(
                                      label: 'Ruku in the surah',
                                      value: '${mark.indexInSurah}',
                                      ink: ink,
                                      muted: muted,
                                      rowFill: rowFill,
                                    ),
                                    _Fact(
                                      label: 'Ayahs in this ruku',
                                      value: '${mark.ayahCount}',
                                      ink: ink,
                                      muted: muted,
                                      rowFill: rowFill,
                                    ),
                                    _Fact(
                                      label: 'Surah',
                                      value:
                                          surahName.isEmpty ? '—' : surahName,
                                      ink: ink,
                                      muted: muted,
                                      rowFill: rowFill,
                                      arabicValue: surahName.isNotEmpty,
                                    ),
                                    _Fact(
                                      label: 'Para',
                                      value: paraValue,
                                      ink: ink,
                                      muted: muted,
                                      rowFill: rowFill,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _paraName(int para) {
    final meta = QuranMetadata.cached;
    if (meta == null) return '';
    for (final juz in meta.juz) {
      if (juz.juz == para) return juz.displayName;
    }
    return '';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.ink,
    required this.muted,
    required this.rowFill,
    this.arabicValue = false,
  });

  final String label;
  final String value;
  final Color ink;
  final Color muted;
  final Color rowFill;
  final bool arabicValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: rowFill,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: AppTheme.orange.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  textDirection: arabicValue
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: arabicValue ? QuranFont.family : null,
                    fontSize: arabicValue ? 15 : 13,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: arabicValue
                        ? QuranFont.recommendedLineHeight * 0.75
                        : 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
