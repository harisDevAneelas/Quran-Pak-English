import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_dimens.dart';
import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../data/quran_metadata.dart';
import '../playing_ayah_follow.dart';
import '../reader_nav_scope.dart';

class PlayingAyahBarHost extends StatelessWidget {
  const PlayingAyahBarHost({
    super.key,
    this.followDetached,
    this.transportVisible,
    this.transportHeight = 0,
    this.chromeHeight,
  });

  final ValueListenable<bool>? followDetached;
  final ValueListenable<bool>? transportVisible;
  final double transportHeight;
  final ValueListenable<double>? chromeHeight;

  @override
  Widget build(BuildContext context) {
    final nav = ReaderNavScope.maybeOf(context)?.nav;
    if (nav == null) {
      return const IgnorePointer(child: SizedBox.expand());
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        nav.playingBar,
        nav.pageAboveHome,
        ?followDetached,
        ?transportVisible,
        ?chromeHeight,
      ]),
      builder: (context, _) {
        final session = nav.playingBar.value;
        final show = shouldShowPlayingAyahBar(
          audioActive: session != null,
          pageAboveHome: nav.pageAboveHome.value,
          playingAyahOnScreen: followDetached == null
              ? false
              : !followDetached!.value,
        );
        if (!show || session == null) {
          return const IgnorePointer(child: SizedBox.expand());
        }

        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final gap = AppDimens.scaled(context, AppDimens.playingAyahBarGap);
        final transportShown =
            transportVisible == null || transportVisible!.value;
        final chrome = chromeHeight?.value ??
            ((transportShown && transportHeight > 0) ? transportHeight : 0.0);
        final lift = playingAyahBarLift(
          safeBottom: safeBottom,
          gap: gap,
          chromeHeight: chrome,
        );
        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedPadding(
            duration: chrome > 0
                ? AppDimens.bottomBarShow
                : AppDimens.bottomBarHide,
            curve: chrome > 0
                ? AppDimens.bottomBarShowCurve
                : AppDimens.bottomBarHideCurve,
            padding: EdgeInsets.only(bottom: lift),
            child: PlayingAyahBar(
              surah: session.surah,
              ayah: session.ayah,
              playing: session.playing,
              loading: session.loading,
              onTap: () => nav.onPlayingBarTap?.call(),
              onPlayPressed: () => nav.onPlayingBarPlay?.call(),
              onClosePressed: () => nav.onPlayingBarClose?.call(),
            ),
          ),
        );
      },
    );
  }
}

class PlayingAyahBar extends StatelessWidget {
  const PlayingAyahBar({
    super.key,
    required this.surah,
    required this.ayah,
    required this.playing,
    required this.loading,
    required this.onTap,
    required this.onPlayPressed,
    required this.onClosePressed,
  });

  final int surah;
  final int ayah;
  final bool playing;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback onPlayPressed;
  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    final scale = AppDimens.scaleOf(context);
    final height = AppDimens.playingAyahBarHeight * scale;
    final radius = AppDimens.playingAyahBarRadius * scale;
    final inset = AppDimens.playingAyahBarInset * scale;
    final playSize = AppDimens.playingAyahPlaySize * scale;
    final rawName = QuranMetadata.nameArOrEmpty(surah);
    final surahLabel = playingSurahCaption(rawName);
    final ayahLabel = playingAyahCaption(ayah);
    final theme = Theme.of(context);
    final surahStyle = QuranFont.base.copyWith(
      fontSize: AppDimens.fontPlayingAyahSurah,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.1,
    );
    final ayahStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: AppDimens.fontPlayingAyahNumber * scale,
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.bottomBarGradient,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset * 0.6),
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  _CircleAction(
                    size: playSize,
                    tooltip: 'Close',
                    onPressed: onClosePressed,
                    child: Icon(
                      Icons.close_rounded,
                      color: AppTheme.orangeDeep,
                      size: playSize * 0.58,
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(radius),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: ScreenFitText(
                                surahLabel,
                                textDirection: TextDirection.rtl,
                                maxLines: 1,
                                minFontSize: AppDimens.fontPlayingAyahSurahMin,
                                textAlign: TextAlign.center,
                                style: surahStyle,
                              ),
                            ),
                            Text(
                              '  .  ',
                              style: ayahStyle,
                            ),
                            Text(
                              ayahLabel,
                              textDirection: TextDirection.ltr,
                              style: ayahStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _CircleAction(
                    size: playSize,
                    tooltip: playing ? 'Pause' : 'Play',
                    onPressed: loading ? null : onPlayPressed,
                    child: loading
                        ? SizedBox(
                            width: playSize * 0.45,
                            height: playSize * 0.45,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppTheme.orangeDeep,
                            ),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: AppTheme.orangeDeep,
                            size: playSize * 0.62,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.size,
    required this.tooltip,
    required this.child,
    required this.onPressed,
  });

  final double size;
  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
