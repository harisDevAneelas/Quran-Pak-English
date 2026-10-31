import 'package:flutter/material.dart';

import 'reader_settings.dart';
import 'widgets/reader_sidebar.dart';

/// Live ayah shown on the floating playing chip.
class PlayingAyahBarSession {
  const PlayingAyahBarSession({
    required this.surah,
    required this.ayah,
    required this.playing,
    required this.loading,
  });

  final int surah;
  final int ayah;
  final bool playing;
  final bool loading;

  @override
  bool operator ==(Object other) {
    return other is PlayingAyahBarSession &&
        other.surah == surah &&
        other.ayah == ayah &&
        other.playing == playing &&
        other.loading == loading;
  }

  @override
  int get hashCode => Object.hash(surah, ayah, playing, loading);
}

/// Callbacks the reader registers so any route can open the shared drawer.
class ReaderNavController {
  void Function(int surah)? _jumpToSurah;
  void Function(int surah, int ayah)? _jumpToAyah;
  void Function(SidebarDestination destination)? _openDestination;
  VoidCallback? onPlayingBarTap;
  VoidCallback? onPlayingBarPlay;
  VoidCallback? onPlayingBarClose;

  /// True while a [PageRoute] sits above the mushaf home route.
  final ValueNotifier<bool> pageAboveHome = ValueNotifier(false);

  /// Current ayah audio for chips painted inside each scaffold body.
  final ValueNotifier<PlayingAyahBarSession?> playingBar = ValueNotifier(null);

  void publishRouteCover({
    required bool pageAboveHome,
  }) {
    if (this.pageAboveHome.value != pageAboveHome) {
      this.pageAboveHome.value = pageAboveHome;
    }
  }

  void publishPlayingBar(PlayingAyahBarSession? session) {
    if (playingBar.value != session) playingBar.value = session;
  }

  void dispose() {
    pageAboveHome.dispose();
    playingBar.dispose();
  }

  void attach({
    required void Function(int surah) jumpToSurah,
    required void Function(int surah, int ayah) jumpToAyah,
    required void Function(SidebarDestination destination) openDestination,
    VoidCallback? onPlayingBarTap,
    VoidCallback? onPlayingBarPlay,
    VoidCallback? onPlayingBarClose,
  }) {
    _jumpToSurah = jumpToSurah;
    _jumpToAyah = jumpToAyah;
    _openDestination = openDestination;
    this.onPlayingBarTap = onPlayingBarTap;
    this.onPlayingBarPlay = onPlayingBarPlay;
    this.onPlayingBarClose = onPlayingBarClose;
  }

  void detach() {
    _jumpToSurah = null;
    _jumpToAyah = null;
    _openDestination = null;
    onPlayingBarTap = null;
    onPlayingBarPlay = null;
    onPlayingBarClose = null;
    playingBar.value = null;
  }

  void jumpToSurah(int surah) => _jumpToSurah?.call(surah);

  void jumpToAyah(int surah, int ayah) => _jumpToAyah?.call(surah, ayah);

  void openDestination(SidebarDestination destination) =>
      _openDestination?.call(destination);
}

/// Lives above the root navigator so every pushed screen can reuse the drawer.
class ReaderNavScope extends InheritedWidget {
  const ReaderNavScope({
    super.key,
    required this.settings,
    required this.profileName,
    required this.nav,
    required super.child,
  });

  final ReaderSettings settings;
  final String profileName;
  final ReaderNavController nav;

  static ReaderNavScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ReaderNavScope>();
  }

  static ReaderNavScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'ReaderNavScope is missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(ReaderNavScope oldWidget) {
    return settings != oldWidget.settings ||
        profileName != oldWidget.profileName ||
        nav != oldWidget.nav;
  }
}
