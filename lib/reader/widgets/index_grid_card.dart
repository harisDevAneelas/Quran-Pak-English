import 'package:flutter/material.dart';

import '../../core/app_dimens.dart';
import '../../core/app_theme.dart';

/// Soft card used by surah / para index grids (number + name + optional star).
class IndexGridCard extends StatelessWidget {
  const IndexGridCard({
    super.key,
    required this.fill,
    required this.badge,
    required this.title,
    required this.ink,
    required this.onTap,
    this.starred = false,
    this.onStarTap,
    this.titleFontFamily,
    this.titleFontFamilyFallback,
    this.titleHeight = 1.2,
  });

  final Color fill;
  final String badge;
  final String title;
  final Color ink;
  final VoidCallback onTap;
  final bool starred;
  final VoidCallback? onStarTap;

  /// When null, the title uses the theme font (surah grid).
  final String? titleFontFamily;
  final List<String>? titleFontFamilyFallback;
  final double titleHeight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimens.indexTileRadius);
    final titleSize = AppDimens.scaled(context, AppDimens.fontIndexTitle);

    return Material(
      color: fill,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: AppTheme.orange.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: AppDimens.indexBadgeSize,
                  height: AppDimens.indexBadgeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.orange.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: AppTheme.orangeDeep,
                      fontSize: AppDimens.fontIndexBadge,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // Shrink / wrap until the full title fits — never ellipsize.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const maxLines = 3;
                      final maxHeight = constraints.maxHeight.isFinite &&
                              constraints.maxHeight > 0
                          ? constraints.maxHeight
                          : titleSize * titleHeight * maxLines;
                      final style = TextStyle(
                        color: ink,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w400,
                        height: titleHeight,
                        fontFamily: titleFontFamily,
                        fontFamilyFallback: titleFontFamilyFallback,
                      );
                      final size = AppDimens.fontSizeFor(
                        text: title,
                        style: style,
                        maxWidth: constraints.maxWidth,
                        maxHeight: maxHeight,
                        maxLines: maxLines,
                        minFontSize: 8,
                        textAlign: TextAlign.left,
                        textDirection: TextDirection.ltr,
                      );
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: Text(
                            title,
                            maxLines: maxLines,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.left,
                            textDirection: TextDirection.ltr,
                            textScaler: TextScaler.noScaling,
                            style: style.copyWith(fontSize: size),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (onStarTap != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: starred ? 'Remove bookmark' : 'Bookmark',
                    onPressed: onStarTap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: AppDimens.indexStarTap,
                      minHeight: AppDimens.indexStarTap,
                    ),
                    icon: Icon(
                      starred ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: starred
                          ? AppTheme.orange
                          : ink.withValues(alpha: 0.35),
                      size: AppDimens.indexStarSize,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
