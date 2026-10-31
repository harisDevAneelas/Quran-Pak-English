import 'package:flutter/widgets.dart';

/// Named UI sizes at the iPhone-14 reference width, plus scale/fit math.
///
/// Screens read tokens from here and call [scaled] / [fontSizeFor] instead of
/// inventing local numbers.
abstract final class AppDimens {
  /// Shortest side this file is designed at (~iPhone 14 portrait width).
  static const double referenceShortest = 390;

  /// Narrowest scale factor (iPhone SE / mini).
  static const double scaleFloor = 0.75;

  // --- Fonts (reference px) ---
  static const double fontAppBar = 18;
  static const double fontAppBarMin = 12;
  static const double fontHubTitle = 20;
  static const double fontHubTitleMin = 12;
  static const double fontHubTile = 20;
  static const double fontHubTileMin = 11;
  static const double fontAction = 13;
  static const double fontActionMin = 9;
  static const double fontDailyQuestion = 16;
  static const double fontDailyHint = 14;
  static const double fontDailyFooter = 13;
  static const double fontDailyCardTitle = 28;
  static const double fontDailyCardTitleMin = 16;
  static const double fontDailyCardSubtitle = 13;
  static const double fontDailyCardSubtitleMin = 10;
  static const double fontPlanBar = 15;
  static const double fontPlanReminder = 14;
  static const double fontPlanBarMin = 11;
  static const double fontTilawatTitle = 20;
  static const double fontTilawatSubtitle = 13;
  static const double fontTilawatButton = 15;
  static const double fontTilawatButtonMin = 11;
  static const double fontDone = 16;
  static const double fontDoneMin = 11;
  static const double fontConfirm = 14;
  static const double fontConfirmMin = 11;
  static const double fontSurahJump = 17;
  static const double fontSurahJumpMin = 12;
  static const double fontPlayingAyahSurah = 18;
  static const double fontPlayingAyahSurahMin = 12;
  static const double fontPlayingAyahNumber = 13;

  // --- Hub grid ---
  static const double hubGap = 12;
  static const double hubPadH = 14;
  static const double hubPadV = 16;
  static const double hubTileHeight = 76;
  static const double hubTileHeightFloor = 0.92;
  static const double hubTilePadH = 10;
  static const double hubTilePadV = 8;

  // --- Ayah actions ---
  static const double actionCircle = 76;
  static const double actionCircleFloor = 0.88;
  static const double actionLabelGap = 8;

  // --- Daily-plan type picker ---
  static const double dailyGap = 14;
  static const double dailyPadH = 20;
  static const double dailyPadTop = 28;
  static const double dailyPadBottom = 20;
  static const double dailyCellMin = 120;
  static const double dailyChrome = 190;

  // --- Buttons ---
  static const double doneWideW = 168;
  static const double doneWideH = 44;
  static const double doneW = 72;
  static const double doneH = 36;
  static const double tilawatButtonH = 46;
  static const double playingAyahBarHeight = 52;
  static const double playingAyahBarGap = 10;
  static const double playingAyahBarInset = 12;
  static const double playingAyahBarRadius = 16;
  static const double playingAyahPlaySize = 36;

  /// Transport overlay: hide stays short; return after scroll is a slow ease.
  static const Duration bottomBarHide = Duration(milliseconds: 220);
  static const Duration bottomBarShow = Duration(milliseconds: 650);
  static const Curve bottomBarHideCurve = Curves.easeInCubic;
  static const Curve bottomBarShowCurve = Curves.easeOutCubic;

  /// `0.75 … 1.0` from [MediaQuery] shortest side.
  static double scaleOf(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    if (shortest >= referenceShortest) return 1.0;
    return (shortest / referenceShortest).clamp(scaleFloor, 1.0);
  }

  /// [base] token multiplied by [scaleOf].
  static double scaled(BuildContext context, double base) =>
      base * scaleOf(context);

  /// Fixed hub tile height (same for every tile), scaled only by screen size.
  static double hubTileHeightOf(BuildContext context) {
    return hubTileHeight * scaleOf(context).clamp(hubTileHeightFloor, 1.0);
  }
  
  static double hubTileWidthOf(double maxWidth) =>
      (maxWidth - hubPadH * 2 - hubGap) / 2;

  static double actionCircleOf(BuildContext context) =>
      actionCircle * scaleOf(context).clamp(actionCircleFloor, 1.0);

  static double dailyCellWidthOf(double maxWidth) =>
      (maxWidth - dailyPadH * 2 - dailyGap) / 2;

  /// Largest font size at or below [style.fontSize] that paints [text] inside
  /// [maxWidth] × [maxHeight] with [maxLines].
  static double fontSizeFor({
    required String text,
    required TextStyle style,
    required double maxWidth,
    double maxHeight = double.infinity,
    int maxLines = 2,
    double minFontSize = 10,
    TextAlign textAlign = TextAlign.center,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final hiStart = style.fontSize ?? 14;
    final min = minFontSize.clamp(1.0, hiStart);
    if (!maxWidth.isFinite || maxWidth <= 0) return hiStart;

    bool fits(double size) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: textDirection,
        textAlign: textAlign,
        textScaler: TextScaler.noScaling,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final ok = !painter.didExceedMaxLines &&
          (!maxHeight.isFinite || painter.height <= maxHeight + 0.5);
      painter.dispose();
      return ok;
    }

    if (fits(hiStart)) return hiStart;
    var lo = min;
    var hi = hiStart;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return fits(lo) ? lo : min;
  }
}

/// Button/tile label that shrinks from an [AppDimens] font token to the box.
class ScreenFitText extends StatelessWidget {
  const ScreenFitText(
    this.data, {
    super.key,
    required this.style,
    this.maxLines = 2,
    this.minFontSize = 10,
    this.textAlign = TextAlign.center,
    this.textDirection = TextDirection.ltr,
  });

  final String data;
  final TextStyle style;
  final int maxLines;
  final double minFontSize;
  final TextAlign textAlign;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = AppDimens.fontSizeFor(
          text: data,
          style: style,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          maxLines: maxLines,
          minFontSize: minFontSize,
          textAlign: textAlign,
          textDirection: textDirection,
        );
        return Text(
          data,
          style: style.copyWith(fontSize: size),
          maxLines: maxLines,
          textAlign: textAlign,
          textDirection: textDirection,
          textScaler: TextScaler.noScaling,
          overflow: TextOverflow.clip,
          softWrap: maxLines > 1,
        );
      },
    );
  }
}
