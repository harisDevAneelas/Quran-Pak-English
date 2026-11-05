import 'package:flutter/material.dart';

import '../../core/app_dimens.dart';
import '../../core/app_theme.dart';

/// Horizontal chips of bookmarked index items under the grid search field.
class IndexBookmarkStrip extends StatelessWidget {
  const IndexBookmarkStrip({
    super.key,
    required this.labels,
    required this.onTap,
    required this.onUnstar,
    required this.ink,
    required this.muted,
  });

  /// Display label per item, keyed by id (surah or para number).
  final Map<int, String> labels;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onUnstar;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    // Preserve insertion order from [labels] (mark order, not number).
    final ids = labels.keys.toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.indexPadH,
        0,
        AppDimens.indexPadH,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bookmarks',
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.orangeDeep,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ids.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final id = ids[index];
                final label = labels[id] ?? '$id';
                return Material(
                  color: AppTheme.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onTap(id),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 12,
                        end: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: AppTheme.orange,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove bookmark',
                            onPressed: () => onUnstar(id),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
