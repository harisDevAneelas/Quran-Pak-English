import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reader_nav_scope.dart';
import 'orange_app_bar.dart';
import 'playing_ayah_bar.dart';
import 'reader_sidebar.dart';

class ReaderPageScaffold extends StatefulWidget {
  const ReaderPageScaffold({
    super.key,
    required this.title,
    this.titleWidget,
    required this.body,
    this.leading,
    this.leadingWidth,
    this.actions,
    this.backgroundColor,
    this.showDrawer = true,
    this.showPlayingAyahBar = true,
    this.playingBarChromeHeight,
  });

  final String title;
  final Widget? titleWidget;
  final Widget body;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool showDrawer;
  final bool showPlayingAyahBar;
  final ValueListenable<double>? playingBarChromeHeight;

  @override
  State<ReaderPageScaffold> createState() => _ReaderPageScaffoldState();
}

class _ReaderPageScaffoldState extends State<ReaderPageScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final nav = ReaderNavScope.maybeOf(context);
    final showDrawer = widget.showDrawer && nav != null;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor:
          widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      drawer: !showDrawer
          ? null
          : ReaderMenuDrawer(
              settings: nav.settings,
              activeProfileName: nav.profileName,
              onSurahSelected: nav.nav.jumpToSurah,
              onAyahSelected: nav.nav.jumpToAyah,
              onDestination: (destination) {
                _scaffoldKey.currentState?.closeDrawer();
                nav.nav.openDestination(destination);
              },
            ),
      appBar: OrangeAppBar(
        title: widget.title,
        titleWidget: widget.titleWidget,
        leading: widget.leading,
        leadingWidth: widget.leadingWidth,
        onOpenDrawer: !showDrawer
            ? null
            : () => _scaffoldKey.currentState?.openDrawer(),
        actions: widget.actions,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.body,
          if (widget.showPlayingAyahBar)
            Positioned.fill(
              child: PlayingAyahBarHost(
                chromeHeight: widget.playingBarChromeHeight,
              ),
            ),
        ],
      ),
    );
  }
}
