import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../quran/rendering/kfgqpc_font_scope.dart';
import 'surah_header_banner.dart';

/// Shared header bismillah at the start of a recitation page.
///
/// Same family as [SurahHeaderBanner]: center wash, orange flourishes,
/// active mushaf face.
class RecitationBismillah extends StatelessWidget {
  const RecitationBismillah({
    super.key,
    required this.text,
    required this.fontSize,
    required this.inkColor,
  });

  final String text;
  final double fontSize;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final page = theme.scaffoldBackgroundColor;
    const accent = AppTheme.orangeDeep;

    final wash = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: isDark
          ? [
              page,
              page,
              const Color(0xFF1C1914),
              const Color(0xFF2A2218),
              const Color(0xFF1C1914),
              page,
              page,
            ]
          : [
              page,
              page,
              const Color(0xFFFFF8EE),
              const Color(0xFFFFE9C8),
              const Color(0xFFFFF8EE),
              page,
              page,
            ],
      stops: const [0.0, 0.18, 0.34, 0.5, 0.66, 0.82, 1.0],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: wash),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: HeaderFlourishPainter(
                            color: accent,
                            mirror: false,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox(
                          width: 6,
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: CustomPaint(
                          painter: HeaderFlourishPainter(
                            color: accent,
                            mirror: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: QuranFont.base.copyWith(
                  fontFamily:
                      KfgqpcFontScope.maybeFamilyOf(context) ?? QuranFont.family,
                  fontSize: (fontSize * 0.55).clamp(18.0, 28.0),
                  color: inkColor,
                  height: QuranFont.recommendedLineHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
