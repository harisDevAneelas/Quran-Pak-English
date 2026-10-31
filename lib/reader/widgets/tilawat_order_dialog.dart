import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/app_dimens.dart';
import '../../data/tilawat_order.dart';

/// Modal matching the reference "Recitation order" picker.
Future<TilawatOrder?> showTilawatOrderDialog({
  required BuildContext context,
  required TilawatOrder selected,
}) {
  return showDialog<TilawatOrder>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => TilawatOrderDialog(selected: selected),
  );
}

class TilawatOrderDialog extends StatelessWidget {
  const TilawatOrderDialog({super.key, required this.selected});

  final TilawatOrder selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = theme.scaffoldBackgroundColor;
    final title = theme.colorScheme.onSurface;
    final subtitle = theme.colorScheme.onSurfaceVariant;
    final ring = card;

    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    final titleSize = AppDimens.scaled(context, AppDimens.fontTilawatTitle);
    final subtitleSize =
        AppDimens.scaled(context, AppDimens.fontTilawatSubtitle);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320, maxHeight: maxH),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 28),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppTheme.orange.withValues(
                      alpha: isDark ? 0.55 : 0.35,
                    ),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.orange.withValues(
                        alpha: isDark ? 0.18 : 0.12,
                      ),
                      blurRadius: 32,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 140,
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
                      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Recitation order',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: title,
                              fontSize: titleSize,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Please choose one',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: subtitle,
                              fontSize: subtitleSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          for (final order in TilawatOrder.values) ...[
                            _OrderButton(
                              label: order.label,
                              highlighted: order == selected,
                              onTap: () => Navigator.of(context).pop(order),
                            ),
                            if (order != TilawatOrder.values.last)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppTheme.barGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.orange.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.touch_app_rounded,
                    color: Colors.white,
                    size: 28,
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

class _OrderButton extends StatelessWidget {
  const _OrderButton({
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppDimens.tilawatButtonH,
      child: Material(
        color: highlighted ? AppTheme.orangeDeep : AppTheme.orange,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ScreenFitText(
                label,
                maxLines: 1,
                minFontSize: AppDimens.fontTilawatButtonMin,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppDimens.scaled(context, AppDimens.fontTilawatButton),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
