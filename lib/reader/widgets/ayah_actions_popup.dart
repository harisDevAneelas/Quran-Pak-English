import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/app_dimens.dart';

/// Action chosen from the verse overlay.
enum AyahAction { tilawat, bookmark, tafsir, share, aboutSurah, wordByWord }

/// Instant blurred overlay with the six verse actions.
Future<AyahAction?> showAyahActionsPopup({required BuildContext context}) {
  return showGeneralDialog<AyahAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const AyahActionsPopup();
    },
  );
}

class AyahActionsPopup extends StatelessWidget {
  const AyahActionsPopup({super.key});

  void _select(BuildContext context, AyahAction action) {
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final veil = isDark
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.38);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(color: veil),
            ),
          ),
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              label: 'Translation and tafsir',
                              icon: const Icon(
                                Icons.menu_book_rounded,
                                color: Color(0xFF7CB342),
                                size: 32,
                              ),
                              onTap: () => _select(context, AyahAction.tafsir),
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              label: 'Bookmarks',
                              icon: const _HeartPlusIcon(),
                              onTap: () =>
                                  _select(context, AyahAction.bookmark),
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              label: 'Recitation',
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: Color(0xFF00BFA5),
                                size: 40,
                              ),
                              onTap: () =>
                                  _select(context, AyahAction.tilawat),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              label: 'Word by word',
                              icon: const Icon(
                                Icons.sync_alt_rounded,
                                color: Color(0xFF1E88E5),
                                size: 30,
                              ),
                              onTap: () =>
                                  _select(context, AyahAction.wordByWord),
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              label: 'About this surah',
                              icon: const Icon(
                                Icons.wb_sunny_rounded,
                                color: Color(0xFFFFA000),
                                size: 32,
                              ),
                              onTap: () =>
                                  _select(context, AyahAction.aboutSurah),
                            ),
                          ),
                          Expanded(
                            child: _ActionButton(
                              label: 'Share',
                              icon: const _ShareMark(),
                              onTap: () => _select(context, AyahAction.share),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final circle = AppDimens.actionCircleOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: SizedBox(
              width: circle,
              height: circle,
              child: Center(child: icon),
            ),
          ),
          const SizedBox(height: AppDimens.actionLabelGap),
          SizedBox(
            width: double.infinity,
            child: ScreenFitText(
              label,
              maxLines: 2,
              minFontSize: AppDimens.fontActionMin,
              style: TextStyle(
                color: Colors.white,
                fontSize: AppDimens.scaled(context, AppDimens.fontAction),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartPlusIcon extends StatelessWidget {
  const _HeartPlusIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.favorite_rounded, color: Color(0xFF8E24AA), size: 34),
          Icon(Icons.add, color: Colors.white, size: 16),
        ],
      ),
    );
  }
}

class _ShareMark extends StatelessWidget {
  const _ShareMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.loop_rounded, color: Color(0xFF4527A0), size: 34),
          Icon(Icons.favorite, color: Color(0xFF5E35B1), size: 11),
        ],
      ),
    );
  }
}
