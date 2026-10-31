import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../../core/app_theme.dart';
import '../prayer_time_service.dart';

/// Day prayer times in the same card family as Ruku details.
Future<void> showNamazTimesPopup({
  required BuildContext context,
  required DayPrayerTimes times,
  NamazName? current,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _NamazTimesPopup(times: times, current: current);
    },
  );
}

class _NamazTimesPopup extends StatelessWidget {
  const _NamazTimesPopup({required this.times, this.current});

  final DayPrayerTimes times;
  final NamazName? current;

  static String clock(DateTime t, DayPrayerTimes day) {
    var h12 = t.hour % 12;
    if (h12 == 0) h12 = 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${day.dayPartAt(t)}';
  }

  static String hijriLabel(DateTime day) {
    final h = HijriCalendar.fromDate(day);
    const months = [
      'Muharram',
      'Safar',
      'Rabi al-Awwal',
      'Rabi al-Thani',
      'Jumada al-Awwal',
      'Jumada al-Thani',
      'Rajab',
      "Sha'ban",
      'Ramadan',
      'Shawwal',
      "Dhul Qa'dah",
      'Dhul Hijjah',
    ];
    final month = months[h.hMonth - 1];
    return '${h.hDay} $month ${h.hYear} AH';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final veil = isDark
        ? Colors.black.withValues(alpha: 0.62)
        : Colors.black.withValues(alpha: 0.38);
    final card = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final rowFill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : theme.colorScheme.onSurface.withValues(alpha: 0.05);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: ColoredBox(color: veil),
            ),
          ),
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 280,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.orange.withValues(
                          alpha: isDark ? 0.55 : 0.35,
                        ),
                        width: 1.1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.orange.withValues(
                            alpha: isDark ? 0.14 : 0.1,
                          ),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 110,
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    2,
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: AppTheme.barGradient,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.orange.withValues(
                                                alpha: 0.35,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.access_time_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Prayer times',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                          color: ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        hijriLabel(times.date),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    children: [
                                      for (final name in NamazName.values) ...[
                                        _Fact(
                                          label: name.labelUr,
                                          value: clock(
                                            times.startOf(name),
                                            times,
                                          ),
                                          ink: ink,
                                          muted: muted,
                                          rowFill: rowFill,
                                          highlight: name == current,
                                        ),
                                        if (name == NamazName.fajr)
                                          _Fact(
                                            label: 'Sunrise',
                                            value: clock(
                                              times.sunrise,
                                              times,
                                            ),
                                            ink: ink,
                                            muted: muted,
                                            rowFill: rowFill,
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.ink,
    required this.muted,
    required this.rowFill,
    this.highlight = false,
  });

  final String label;
  final String value;
  final Color ink;
  final Color muted;
  final Color rowFill;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final fill = highlight
        ? AppTheme.orange.withValues(alpha: 0.14)
        : rowFill;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: AppTheme.orange.withValues(alpha: highlight ? 0.35 : 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: highlight ? ink : muted,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1.25,
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
