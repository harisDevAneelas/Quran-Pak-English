import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_dimens.dart';
import '../../core/app_theme.dart';
import '../../data/quran_metadata.dart';
import '../app_notification_scheduler.dart';
import '../daily_plan.dart';
import '../learned_notify_store.dart';
import '../notification_route.dart';
import '../profile.dart';
import '../profile_manager.dart';
import '../widgets/orange_app_bar.dart';
import '../widgets/profile_edit_chips.dart';
import '../widgets/reader_page_scaffold.dart';

/// Amount, start position, and reminder for one daily-plan unit.
class DailyPlanSetupScreen extends StatefulWidget {
  const DailyPlanSetupScreen({
    super.key,
    required this.kind,
    required this.dailyPlanStore,
    required this.profiles,
    required this.editProfileId,
    required this.learnedNotifyStore,
  });

  final DailyPlanKind kind;
  final DailyPlanStore dailyPlanStore;
  final ProfileManager profiles;
  final String editProfileId;
  final LearnedNotifyStore learnedNotifyStore;

  @override
  State<DailyPlanSetupScreen> createState() => _DailyPlanSetupScreenState();
}

class _DailyPlanSetupScreenState extends State<DailyPlanSetupScreen> {
  static const _bar = Color(0xFF3A3A3A);
  static const _itemExtent = 36.0;
  static const _wheelHeight = 180.0;
  static const _minutes = <int>[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
  static const _paraAmounts = <double>[0.25, 0.5, 0.75, 1, 2, 3];

  QuranMetadata? _meta;
  bool _ready = false;
  bool _controllersReady = false;

  late FixedExtentScrollController _surahCtrl;
  late FixedExtentScrollController _ayahCtrl;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  late FixedExtentScrollController _periodCtrl;

  late String _editProfileId;
  late DailyPlanStore _store;

  int _surah = 1;
  int _ayah = 1;
  double _amount = 3;
  bool _reminder = true;
  int _hour = 5;
  int _minute = 0;
  bool _isPm = true;

  @override
  void initState() {
    super.initState();
    _amount = widget.kind.defaultAmount;
    _editProfileId = widget.editProfileId;
    _store = DailyPlanStore(profileId: _editProfileId);
    _bootstrap();
  }

  Future<void> _onProfileSelected(Profile profile) async {
    if (profile.id == _editProfileId) return;
    _editProfileId = profile.id;
    _store = DailyPlanStore(profileId: profile.id);
    setState(() => _ready = false);
    _disposeControllers();
    await _bootstrap();
  }

  Future<void> _createProfileForEdit() async {
    final name = await _promptNewProfileName('');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final profile = await widget.profiles.create(name.trim());
    if (!mounted) return;
    await _onProfileSelected(profile);
  }

  Future<String?> _promptNewProfileName(String suggested) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => _NewProfileDialog(initial: suggested),
    );
  }

  Future<void> _bootstrap() async {
    final meta = await QuranMetadata.load();
    final saved = await _store.load();

    var surah = 1;
    var ayah = 1;
    var reminder = true;
    var hour = 5;
    var minute = 0;
    var isPm = true;
    var amount = widget.kind.defaultAmount;

    if (saved != null) {
      surah = saved.startSurah.clamp(1, meta.surahs.length);
      final maxAyah = meta.surahs[surah - 1].ayahCount;
      ayah = saved.startAyah.clamp(1, maxAyah);
      reminder = saved.reminderEnabled;
      hour = saved.hour.clamp(1, 12);
      minute = _minutes.contains(saved.minute) ? saved.minute : 0;
      isPm = saved.isPm;
    }

    _surahCtrl = FixedExtentScrollController(initialItem: surah - 1);
    _ayahCtrl = FixedExtentScrollController(initialItem: ayah - 1);
    _hourCtrl = FixedExtentScrollController(initialItem: hour - 1);
    _minuteCtrl = FixedExtentScrollController(
      initialItem: _minutes.indexOf(minute),
    );
    _periodCtrl = FixedExtentScrollController(initialItem: isPm ? 1 : 0);
    _controllersReady = true;

    if (!mounted) {
      _disposeControllers();
      return;
    }

    setState(() {
      _meta = meta;
      _surah = surah;
      _ayah = ayah;
      _amount = amount;
      _reminder = reminder;
      _hour = hour;
      _minute = minute;
      _isPm = isPm;
      _ready = true;
    });
  }

  void _disposeControllers() {
    if (!_controllersReady) return;
    _surahCtrl.dispose();
    _ayahCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _periodCtrl.dispose();
    _controllersReady = false;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  int _ayahCount(int surah) => _meta!.surahs[surah - 1].ayahCount;

  void _onSurahChanged(int index) {
    final surah = index + 1;
    if (surah == _surah) return;
    final maxAyah = _ayahCount(surah);
    if (_ayah > maxAyah && _ayahCtrl.hasClients) {
      _ayahCtrl.jumpToItem(maxAyah - 1);
    }
    setState(() {
      _surah = surah;
      if (_ayah > maxAyah) _ayah = maxAyah;
    });
  }

  Future<void> _save() async {
    final plan = DailyPlan(
      kind: widget.kind,
      amount: widget.kind.usesFractionChips ? _amount : _amount.roundToDouble(),
      startSurah: _surah,
      startAyah: _ayah,
      reminderEnabled: _reminder,
      hour: _hour,
      minute: _minute,
      isPm: _isPm,
    );
    await _store.save(plan);
    final allowed = await AppNotificationScheduler.instance.rescheduleAll(
      plan: plan,
      learnedNotifyStore: widget.learnedNotifyStore,
      confirm: _reminder,
    );
    if (!mounted) return;
    if (_reminder && !allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission is required',
            textDirection: TextDirection.ltr,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    NotificationRoute.requestTodaysRecitation();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderPageScaffold(
      title: 'Daily recitation plan',
      showPlayingAyahBar: false,
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _QuestionBar(text: 'Choose a profile'),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: ListenableBuilder(
                                listenable: widget.profiles,
                                builder: (context, _) {
                                  return ProfileEditChips(
                                    profiles: widget.profiles.profiles,
                                    selectedId: _editProfileId,
                                    onSelected: _onProfileSelected,
                                    onCreateNew: _createProfileForEdit,
                                  );
                                },
                              ),
                            ),
                            _QuestionBar(text: widget.kind.question),
                            widget.kind.usesFractionChips
                                ? _ParaChips(
                                    amount: _amount,
                                    onChanged: (value) =>
                                        setState(() => _amount = value),
                                  )
                                : _AmountStepper(
                                    value: _amount.round(),
                                    min: widget.kind.minAmount,
                                    max: widget.kind.maxAmount,
                                    onChanged: (value) => setState(
                                      () => _amount = value.toDouble(),
                                    ),
                                  ),
                            const _QuestionBar(
                              text: 'Where do you want to start?',
                            ),
                            _StartWheels(
                              meta: _meta!,
                              surah: _surah,
                              ayah: _ayah,
                              ayahCount: _ayahCount(_surah),
                              surahCtrl: _surahCtrl,
                              ayahCtrl: _ayahCtrl,
                              onSurahChanged: _onSurahChanged,
                              onAyahChanged: (index) {
                                final ayah = index + 1;
                                if (ayah == _ayah) return;
                                setState(() => _ayah = ayah);
                              },
                            ),
                            _ReminderBar(
                              enabled: _reminder,
                              onChanged: (value) =>
                                  setState(() => _reminder = value),
                            ),
                            if (_reminder)
                              _TimeWheels(
                                hour: _hour,
                                minute: _minute,
                                isPm: _isPm,
                                hourCtrl: _hourCtrl,
                                minuteCtrl: _minuteCtrl,
                                periodCtrl: _periodCtrl,
                                onHour: (index) =>
                                    setState(() => _hour = index + 1),
                                onMinute: (index) =>
                                    setState(() => _minute = _minutes[index]),
                                onPeriod: (index) =>
                                    setState(() => _isPm = index == 1),
                              ),
                            const SizedBox(height: 24),
                            Center(
                              child: GoldDoneButton(
                                onPressed: _save,
                                wide: true,
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _QuestionBar extends StatelessWidget {
  const _QuestionBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _DailyPlanSetupScreenState._bar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ScreenFitText(
          text,
          maxLines: 2,
          minFontSize: AppDimens.fontPlanBarMin,
          textAlign: TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: AppDimens.fontPlanBar,
          ),
        ),
      ),
    );
  }
}

class _ReminderBar extends StatelessWidget {
  const _ReminderBar({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _DailyPlanSetupScreenState._bar,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8, end: 12),
        child: Row(
          children: [
            const Expanded(
              child: ScreenFitText(
                'Notification (reminder) time',
                maxLines: 2,
                minFontSize: AppDimens.fontPlanBarMin,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppDimens.fontPlanReminder,
                ),
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFFF6A21A),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF8A8A8A),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountStepper extends StatefulWidget {
  const _AmountStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_AmountStepper> createState() => _AmountStepperState();
}

class _AmountStepperState extends State<_AmountStepper> {
  late final _controller = TextEditingController(text: '${widget.value}');

  int get _typed =>
      (int.tryParse(_controller.text) ?? widget.value).clamp(widget.min, widget.max);

  @override
  void didUpdateWidget(_AmountStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF9E9E9E)),
            ),
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onSubmitted: (_) => widget.onChanged(_typed),
              onTapOutside: (_) => widget.onChanged(_typed),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: onSurface,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 36),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBDBDBD)),
            ),
            child: IntrinsicHeight(
              child: Row(
                textDirection: TextDirection.ltr,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stepButton(
                    icon: Icons.remove,
                    enabled: widget.value > widget.min,
                    onTap: () => widget.onChanged(
                      (_typed - 1).clamp(widget.min, widget.max),
                    ),
                    color: onSurface,
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xFFBDBDBD),
                  ),
                  _stepButton(
                    icon: Icons.add,
                    enabled: widget.value < widget.max,
                    onTap: () => widget.onChanged(
                      (_typed + 1).clamp(widget.min, widget.max),
                    ),
                    color: onSurface,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 48,
        height: 44,
        child: Icon(
          icon,
          color: enabled ? color : const Color(0xFFBDBDBD),
        ),
      ),
    );
  }
}

class _ParaChips extends StatelessWidget {
  const _ParaChips({required this.amount, required this.onChanged});

  final double amount;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            for (final option in _DailyPlanSetupScreenState._paraAmounts) ...[
              _ParaChip(
                label: DailyPlanKindX.paraAmountLabel(option),
                selected: (option - amount).abs() < 0.001,
                onTap: () => onChanged(option),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParaChip extends StatelessWidget {
  const _ParaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = selected
        ? AppTheme.orange
        : isDark
            ? const Color(0xFF2A2A2A)
            : Colors.white;
    final border = selected
        ? AppTheme.orangeDeep
        : isDark
            ? const Color(0xFF6B6B6B)
            : const Color(0xFFE0E0E0);
    final labelColor = selected
        ? Colors.white
        : isDark
            ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
            : const Color(0xFF9E9E9E);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(4),
      elevation: selected ? 1 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: labelColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartWheels extends StatelessWidget {
  const _StartWheels({
    required this.meta,
    required this.surah,
    required this.ayah,
    required this.ayahCount,
    required this.surahCtrl,
    required this.ayahCtrl,
    required this.onSurahChanged,
    required this.onAyahChanged,
  });

  final QuranMetadata meta;
  final int surah;
  final int ayah;
  final int ayahCount;
  final FixedExtentScrollController surahCtrl;
  final FixedExtentScrollController ayahCtrl;
  final ValueChanged<int> onSurahChanged;
  final ValueChanged<int> onAyahChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _DailyPlanSetupScreenState._wheelHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                flex: 3,
                child: _Wheel(
                  controller: surahCtrl,
                  childCount: meta.surahs.length,
                  onSelected: onSurahChanged,
                  labelBuilder: (index) {
                    final item = meta.surahs[index];
                    return '${item.listTitle} · ${item.surah}';
                  },
                  selectedIndex: surah - 1,
                  alignStart: true,
                ),
              ),
              Expanded(
                flex: 2,
                child: _Wheel(
                  controller: ayahCtrl,
                  childCount: ayahCount,
                  onSelected: onAyahChanged,
                  labelBuilder: (index) {
                    final n = index + 1;
                    return n == ayah ? '$n Ayah' : '$n';
                  },
                  selectedIndex: ayah - 1,
                ),
              ),
            ],
          ),
          const _SelectionBand(),
        ],
      ),
    );
  }
}

class _TimeWheels extends StatelessWidget {
  const _TimeWheels({
    required this.hour,
    required this.minute,
    required this.isPm,
    required this.hourCtrl,
    required this.minuteCtrl,
    required this.periodCtrl,
    required this.onHour,
    required this.onMinute,
    required this.onPeriod,
  });

  final int hour;
  final int minute;
  final bool isPm;
  final FixedExtentScrollController hourCtrl;
  final FixedExtentScrollController minuteCtrl;
  final FixedExtentScrollController periodCtrl;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final ValueChanged<int> onPeriod;

  @override
  Widget build(BuildContext context) {
    final minuteIndex = _DailyPlanSetupScreenState._minutes.indexOf(minute);
    return SizedBox(
      height: _DailyPlanSetupScreenState._wheelHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 64,
                child: _Wheel(
                  controller: hourCtrl,
                  childCount: 12,
                  onSelected: onHour,
                  selectedIndex: hour - 1,
                  labelBuilder: (index) => '${index + 1}',
                ),
              ),
              SizedBox(
                width: 72,
                child: _Wheel(
                  controller: minuteCtrl,
                  childCount: _DailyPlanSetupScreenState._minutes.length,
                  onSelected: onMinute,
                  selectedIndex: minuteIndex < 0 ? 0 : minuteIndex,
                  labelBuilder: (index) => _DailyPlanSetupScreenState
                      ._minutes[index]
                      .toString()
                      .padLeft(2, '0'),
                ),
              ),
              SizedBox(
                width: 72,
                child: _Wheel(
                  controller: periodCtrl,
                  childCount: 2,
                  onSelected: onPeriod,
                  selectedIndex: isPm ? 1 : 0,
                  labelBuilder: (index) => index == 0 ? 'AM' : 'PM',
                ),
              ),
            ],
          ),
          const _SelectionBand(),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.childCount,
    required this.onSelected,
    required this.labelBuilder,
    required this.selectedIndex,
    this.alignStart = false,
  });

  final FixedExtentScrollController controller;
  final int childCount;
  final ValueChanged<int> onSelected;
  final String Function(int index) labelBuilder;
  final int selectedIndex;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _DailyPlanSetupScreenState._itemExtent,
      diameterRatio: 2.6,
      perspective: 0.002,
      overAndUnderCenterOpacity: 0.85,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: childCount,
        builder: (context, index) {
          final selected = index == selectedIndex;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: alignStart ? 16 : 8),
            child: Align(
              alignment:
                  alignStart ? Alignment.centerLeft : Alignment.center,
              child: Text(
                labelBuilder(index),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignStart ? TextAlign.left : TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: selected ? 16 : 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : const Color(0xFFB0B0B0),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SelectionBand extends StatelessWidget {
  const _SelectionBand();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Container(
        height: _DailyPlanSetupScreenState._itemExtent,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF555555) : const Color(0xFFE4E4E4),
            ),
            bottom: BorderSide(
              color: isDark ? const Color(0xFF555555) : const Color(0xFFE4E4E4),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewProfileDialog extends StatefulWidget {
  const _NewProfileDialog({required this.initial});

  final String initial;

  @override
  State<_NewProfileDialog> createState() => _NewProfileDialogState();
}

class _NewProfileDialogState extends State<_NewProfileDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AlertDialog(
        title: const Text('New profile'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.left,
          decoration: const InputDecoration(
            hintText: 'Name',
          ),
          style: TextStyle(color: ink),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
