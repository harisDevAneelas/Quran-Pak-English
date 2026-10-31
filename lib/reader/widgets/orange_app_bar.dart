import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/app_dimens.dart';

/// Orange gradient bar used by reader menus and the daily-plan flow.
class OrangeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OrangeAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.leading,
    this.leadingWidth,
    this.actions,
    this.onOpenDrawer,
  });

  final String title;
  final Widget? titleWidget;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget>? actions;
  final VoidCallback? onOpenDrawer;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final menu = onOpenDrawer == null
        ? null
        : IconButton(
            tooltip: 'Menu',
            onPressed: onOpenDrawer,
            icon: const Icon(Icons.menu, size: 30),
          );
    final back = IconButton(
      tooltip: 'Back',
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_forward_ios, size: 20),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      forceMaterialTransparency: true,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      centerTitle: true,
      automaticallyImplyLeading: false,
      leadingWidth: leadingWidth,
      flexibleSpace: const SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: AppTheme.topBarGradient),
        ),
      ),
      leading: leading ?? menu,
      title: titleWidget ??
          ScreenFitText(
            title,
            maxLines: 1,
            minFontSize: AppDimens.fontAppBarMin,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppDimens.fontAppBar,
              fontWeight: FontWeight.w600,
            ),
          ),
      actions: [
        ...?actions,
        back,
      ],
    ),
    );
  }
}

/// Gold action chip used on the daily-plan header/footer and similar bars.
class GoldDoneButton extends StatelessWidget {
  const GoldDoneButton({
    super.key,
    required this.onPressed,
    this.label = 'Done',
    this.wide = false,
  });

  final VoidCallback onPressed;
  final String label;
  final bool wide;

  static const Color gold = Color(0xFFF6A21A);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: Colors.white,
        minimumSize: wide
            ? const Size(AppDimens.doneWideW, AppDimens.doneWideH)
            : const Size(AppDimens.doneW, AppDimens.doneH),
        padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: ScreenFitText(
        label,
        maxLines: 1,
        minFontSize: AppDimens.fontDoneMin,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: AppDimens.fontDone,
        ),
      ),
    );
  }
}
