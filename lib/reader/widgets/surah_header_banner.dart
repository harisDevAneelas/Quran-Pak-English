import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/quran_font.dart';
import '../../data/quran_models.dart';

/// Surah name between ornate brackets with side flourishes; bismillah beneath.
class SurahHeaderBanner extends StatelessWidget {
  const SurahHeaderBanner({
    super.key,
    required this.surah,
    required this.nameAr,
    this.bismillah,
    this.fontSize = 40,
    this.inkColor,
    this.nameFamily = QuranFont.family,
    this.nameLineHeight = QuranFont.recommendedLineHeight,
  });

  final int surah;
  final String nameAr;
  final QuranAyahChunk? bismillah;
  final double fontSize;
  final Color? inkColor;
  final String nameFamily;
  final double nameLineHeight;

  @override
  Widget build(BuildContext context) {
    final showBismillah = surah != 9 && bismillah != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final page = theme.scaffoldBackgroundColor;
    final ink = inkColor ?? theme.colorScheme.onSurface;
    const accent = AppTheme.orangeDeep;

    // Sides match the page so no card edge; a light wash only in the center.
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

    final bismillahText = showBismillah
        ? bismillah!.words.map((w) => w.text).join(' ')
        : '';

    // Nastaleeq ink sits low in the line box; drop ornaments to that midline.
    const ornamentDrop = Offset(0, 6);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: wash),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Transform.translate(
                      offset: ornamentDrop,
                      child: CustomPaint(
                        painter: HeaderFlourishPainter(
                          color: accent,
                          mirror: true,
                        ),
                        child: const SizedBox(height: 32, width: double.infinity),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: ornamentDrop,
                    child: CustomPaint(
                      size: const Size(18, 30),
                      painter: _OrnateBracketPainter(
                        color: accent,
                        opening: false,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      nameAr,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      maxLines: 1,
                      softWrap: false,
                      style: QuranFont.base.copyWith(
                        fontFamily: nameFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 22,
                        color: ink,
                        // KFGQPC ink sits low; short line boxes clip into bismillah.
                        height: nameLineHeight,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: ornamentDrop,
                    child: CustomPaint(
                      size: const Size(18, 30),
                      painter: _OrnateBracketPainter(
                        color: accent,
                        opening: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Transform.translate(
                      offset: ornamentDrop,
                      child: CustomPaint(
                        painter: HeaderFlourishPainter(
                          color: accent,
                          mirror: false,
                        ),
                        child: const SizedBox(height: 32, width: double.infinity),
                      ),
                    ),
                  ),
                ],
              ),
              if (showBismillah)
                Text(
                  bismillahText,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: QuranFont.base.copyWith(
                    fontSize: (fontSize * 0.42).clamp(12.0, 18.0),
                    color: ink,
                    height: 1.0,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Curved bracket with a small floral knot at the mid-curve (earlier style).
class _OrnateBracketPainter extends CustomPainter {
  const _OrnateBracketPainter({
    required this.color,
    required this.opening,
  });

  final Color color;
  final bool opening;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final midY = h * 0.5;

    final path = Path();
    if (opening) {
      path.moveTo(w * 0.85, h * 0.08);
      path.cubicTo(
        w * 0.15,
        h * 0.18,
        w * 0.15,
        h * 0.82,
        w * 0.85,
        h * 0.92,
      );
    } else {
      path.moveTo(w * 0.15, h * 0.08);
      path.cubicTo(
        w * 0.85,
        h * 0.18,
        w * 0.85,
        h * 0.82,
        w * 0.15,
        h * 0.92,
      );
    }
    canvas.drawPath(path, paint);

    final knotX = opening ? w * 0.32 : w * 0.68;
    final petal = w * 0.16;
    final knot = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 4; i++) {
      final angle = i * (math.pi / 2) + math.pi / 4;
      final dx = math.cos(angle) * petal;
      final dy = math.sin(angle) * petal;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(knotX + dx * 0.35, midY + dy * 0.35),
          width: petal * 0.95,
          height: petal * 0.55,
        ),
        knot,
      );
    }
    canvas.drawCircle(
      Offset(knotX, midY),
      petal * 0.18,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _OrnateBracketPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.opening != opening;
  }
}

/// Side line from the bracket, with the curl only at the far outer tip.
class HeaderFlourishPainter extends CustomPainter {
  const HeaderFlourishPainter({
    required this.color,
    required this.mirror,
  });

  final Color color;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 12) return;

    canvas.save();
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    final midY = size.height * 0.5;
    final nearBracket = size.width - 0.5;
    final joinX = 16.0;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final soft = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;

    // Hairline twin sits just above; main stroke becomes the fold.
    canvas.drawLine(
      Offset(nearBracket, midY - 2.0),
      Offset(joinX + 8, midY - 2.0),
      soft,
    );

    final stroke = Path()
      ..moveTo(nearBracket, midY)
      ..lineTo(joinX, midY)
      ..cubicTo(joinX - 7, midY, joinX - 11, midY - 2.5, joinX - 8, midY - 6)
      ..cubicTo(joinX - 5, midY - 9.5, joinX + 2, midY - 8.5, joinX + 3, midY - 4.5)
      ..cubicTo(joinX + 4, midY - 1.5, joinX - 1, midY - 0.5, joinX - 3, midY - 2.5);
    canvas.drawPath(stroke, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HeaderFlourishPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.mirror != mirror;
  }
}
