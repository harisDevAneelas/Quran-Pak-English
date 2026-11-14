import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../../core/app_theme.dart';
import '../prayer_time_service.dart';
import 'location_consent_dialog.dart';
import 'namaz_times_popup.dart';

/// Hub strip: current prayer, Hijri date, and end time; tap opens day times.
class NamazTimeBar extends StatefulWidget {
  const NamazTimeBar({super.key, this.onLocationUpdated});

  /// Called after a successful location fix from this bar (grant or refresh).
  final Future<void> Function()? onLocationUpdated;

  @override
  State<NamazTimeBar> createState() => _NamazTimeBarState();
}

class _NamazTimeBarState extends State<NamazTimeBar> {
  bool _loading = true;
  String? _error;
  NamazName? _name;
  DateTime? _end;
  DateTime? _nextStart;
  bool _isCurrent = false;
  DateTime? _now;
  DayPrayerTimes? _day;

  static const _weekdaysUr = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    PrayerTimeService.instance.addListener(_onServiceChanged);
    _load();
  }

  @override
  void dispose() {
    PrayerTimeService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted || _loading) return;
    _applyDay(PrayerTimeService.instance);
  }

  Future<void> _load({bool promptSettings = false}) async {
    final service = PrayerTimeService.instance;
    final hadCoords = service.hasCoords;
    await service.beginForegroundLocation(promptSettings: promptSettings);
    if (!mounted) return;
    _applyDay(service);
    if (service.hasCoords && (!hadCoords || promptSettings)) {
      await widget.onLocationUpdated?.call();
    }
  }

  void _applyDay(PrayerTimeService service) {
    final now = DateTime.now();
    final day = service.today(now);
    final current = day?.currentAt(now);
    final next = day?.nextAt(now);
    setState(() {
      _loading = false;
      _day = day;
      _now = now;
      if (day == null) {
        _error = service.errorUr ??
            'Tap here and allow location for prayer times';
        _name = null;
        _end = null;
        _nextStart = null;
        _isCurrent = false;
        return;
      }
      if (current != null) {
        _error = null;
        _name = current.name;
        _end = current.end;
        _nextStart = null;
        _isCurrent = true;
        return;
      }
      if (next != null) {
        _error = null;
        _name = next.name;
        _end = null;
        _nextStart = next.start;
        _isCurrent = false;
        return;
      }
      _error = service.errorUr ??
          'Tap here and allow location for prayer times';
      _name = null;
      _end = null;
      _nextStart = null;
      _isCurrent = false;
    });
  }

  Future<void> _onTap() async {
    if (_loading) return;
    if (_day == null) {
      final needs = await PrayerTimeService.instance.needsLocationPermission();
      if (!mounted) return;
      if (needs) {
        final allowed = await showLocationConsentDialog(context);
        if (!mounted || !allowed) return;
        await PrayerTimeService.instance.beginForegroundLocation(
          afterUserConsent: true,
        );
      } else {
        await PrayerTimeService.instance.beginForegroundLocation(
          promptSettings: true,
        );
      }
      if (!mounted) return;
      _applyDay(PrayerTimeService.instance);
      if (PrayerTimeService.instance.hasCoords) {
        await widget.onLocationUpdated?.call();
      }
      if (!mounted || _day == null) return;
    }
    final day = _day!;
    if (!mounted) return;
    await showNamazTimesPopup(
      context: context,
      times: day,
      current: _name,
    );
  }

  static String _clock(DateTime t, DayPrayerTimes day) {
    var h12 = t.hour % 12;
    if (h12 == 0) h12 = 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${day.dayPartAt(t)}';
  }

  static String _hijriDateLabel(DateTime t) {
    final h = HijriCalendar.fromDate(t);
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
    final weekday = _weekdaysUr[t.weekday - 1];
    final month = months[h.hMonth - 1];
    return '$weekday ${h.hDay} $month ${h.hYear} AH';
  }

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.92);
    final soft = Colors.white.withValues(alpha: 0.78);

    Widget body;
    if (_loading) {
      body = const Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    } else if (_error != null) {
      body = Text(
        _error!,
        textAlign: TextAlign.start,
        style: TextStyle(
          color: muted,
          fontSize: 14,
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mosque_outlined, size: 19, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isCurrent
                      ? 'Prayer ${_name!.labelUr}'
                      : 'Next prayer ${_name!.labelUr}',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _isCurrent
                    ? 'Ends ${_clock(_end!, _day!)}'
                    : 'Starts ${_clock(_nextStart!, _day!)}',
                style: TextStyle(
                  color: muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hijriDateLabel(_now!),
            style: TextStyle(
              color: soft,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.topBarGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
