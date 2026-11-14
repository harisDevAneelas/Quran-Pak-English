import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/mushaf_script.dart';
import '../../data/ayah_ref.dart';
import '../../data/mushaf_divisions.dart';
import '../../data/quran_metadata.dart';
import '../app_notification_scheduler.dart';
import '../daily_plan.dart';
import '../daily_range.dart';
import '../learned_notify_store.dart';
import '../profile.dart';
import '../profile_manager.dart';
import '../reader_nav_scope.dart';
import '../reader_routes.dart';
import '../reader_settings.dart';
import '../tilawat_position_store.dart';
import '../widgets/orange_app_bar.dart';
import '../widgets/reader_page_scaffold.dart';
import '../widgets/reader_sidebar.dart';
import '../../data/tilawat_order.dart';
import '../../data/prayer_calculation_catalog.dart';
import '../prayer_time_service.dart';
import 'azaan_list_screen.dart';
import 'daily_recitation_screen.dart';

/// Switch profiles at the top and edit the active profile's reader preferences.
///
/// Creating or switching a profile stays here. Leaving (back) or deleting the
/// active profile pops a jump target so the reader can scroll safely.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profiles,
    required this.settings,
    required this.dailyPlanStore,
    required this.tilawatPositionStore,
    required this.learnedNotifyStore,
    required this.onSwitchProfile,
    required this.onDeleteProfile,
    this.applyMushafScript,
  });

  final ProfileManager profiles;
  final ReaderSettings settings;
  final DailyPlanStore dailyPlanStore;
  final TilawatPositionStore tilawatPositionStore;
  final LearnedNotifyStore learnedNotifyStore;
  final Future<({int surah, int ayah, bool openAtSurahHeader})?> Function(
    String id,
  ) onSwitchProfile;
  final Future<({int surah, int ayah, bool openAtSurahHeader})?> Function(
    String id,
  ) onDeleteProfile;
  final Future<void> Function(MushafScript script)? applyMushafScript;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final GlobalKey _tilawatBlockKey = GlobalKey();
  final GlobalKey _asrFiqahBlockKey = GlobalKey();
  bool _busy = false;
  bool _tilawatOrderOpen = false;
  bool _asrFiqahOpen = false;
  DailyPlan? _plan;
  AyahWindow? _window;

  /// Applied when leaving this screen so the reader can jump safely.
  ({int surah, int ayah, bool openAtSurahHeader})? _pendingJump;

  late final Listenable _listenable = Listenable.merge([
    widget.profiles,
    widget.settings,
  ]);

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    await QuranMetadata.load();
    final plan = await widget.dailyPlanStore.load();
    AyahWindow? window;
    if (plan != null) {
      final divisions = await MushafDivisions.load();
      window = DailyRangeResolver.resolve(plan, divisions);
    }
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _window = window;
    });
  }

  Future<void> _select(Profile profile) async {
    if (_busy) return;
    if (profile.id == widget.profiles.activeProfileId) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onSwitchProfile(profile.id);
      if (!mounted) return;
      setState(() => _pendingJump = result);
      await _loadPlan();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await _promptName(title: 'New profile', initial: '');
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final profile = await widget.profiles.create(name);
      final result = await widget.onSwitchProfile(profile.id);
      if (!mounted) return;
      setState(() => _pendingJump = result);
      await _loadPlan();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Profile profile) async {
    if (widget.profiles.profiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'At least one profile is required',
            textDirection: TextDirection.ltr,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return _ThemedDialog(
          title: 'Delete profile?',
          body: Text(
            '"${profile.name}" will lose its preferences, bookmarks, and plan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          actions: [
            _OrangeButton(
              label: 'Delete',
              destructive: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            _OrangeButton(
              label: 'Cancel',
              outlined: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await widget.onDeleteProfile(profile.id);
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptName({
    required String title,
    required String initial,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => _ProfileNameDialog(title: title, initial: initial),
    );
  }

  void _openReciterPicker() {
    if (_busy) return;
    ReaderNavScope.maybeOf(context)?.nav.openDestination(
      SidebarDestination.reciter,
    );
  }

  void _toggleAsrFiqah() {
    if (_busy) return;
    setState(() {
      _asrFiqahOpen = !_asrFiqahOpen;
      if (_asrFiqahOpen) _tilawatOrderOpen = false;
    });
  }

  Future<void> _pickAsrFiqah(String id) async {
    if (_busy) return;
    widget.settings.setPrayerFiqah(id);
    setState(() => _asrFiqahOpen = false);
    await _syncPrayerCalculation();
  }

  Future<void> _openAzaanPicker() async {
    if (_busy) return;
    final nav = Navigator.of(context);
    nav.popUntil((route) {
      if (route.settings.name == ReaderRoutes.profile) return true;
      return route.isFirst;
    });
    final choice = await nav.push<String>(
      MaterialPageRoute<String>(
        settings: const RouteSettings(name: ReaderRoutes.azaan),
        builder: (_) => AzaanListScreen(
          selectedId: widget.settings.azaanId,
        ),
      ),
    );
    if (choice == null || !mounted) return;
    widget.settings.setAzaan(choice);
    await _rescheduleNotifications();
  }

  Future<void> _setAzaanEnabled(bool value) async {
    if (_busy) return;
    widget.settings.setAzaanEnabled(value);
    await _rescheduleNotifications();
  }

  Future<void> _syncPrayerCalculation() async {
    PrayerTimeService.instance.applyCalculation(
      methodId: widget.settings.prayerMethodId,
      fiqahId: widget.settings.prayerFiqahId,
    );
    await _rescheduleNotifications();
  }

  Future<void> _rescheduleNotifications() async {
    final plan = await widget.dailyPlanStore.load();
    await AppNotificationScheduler.instance.rescheduleAll(
      plan: plan,
      learnedNotifyStore: widget.learnedNotifyStore,
    );
  }

  void _openAudioLanguagePicker() {
    if (_busy) return;
    ReaderNavScope.maybeOf(context)?.nav.openDestination(
      SidebarDestination.audioLanguage,
    );
  }

  void _openTranslatorPicker() {
    if (_busy) return;
    ReaderNavScope.maybeOf(context)?.nav.openDestination(
      SidebarDestination.translator,
    );
  }

  Future<void> _openTextSize() async {
    if (_busy) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => TextSizeBottomSheet(settings: widget.settings),
    );
  }

  void _openMushafScript() {
    if (_busy) return;
    ReaderNavScope.maybeOf(context)?.nav.openDestination(
      SidebarDestination.mushafScript,
    );
  }

  Future<void> _confirmResetPreferences() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return _ThemedDialog(
          title: 'Reset to defaults?',
          body: Text(
            'Reciter, translation, Tajweed, light or dark, text size, and other '
            "preferences return to defaults. Bookmarks and today's recitation stay.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Theme.of(ctx).colorScheme.onSurface,
            ),
          ),
          actions: [
            _OrangeButton(
              label: 'Reset',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            _OrangeButton(
              label: 'Cancel',
              outlined: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    widget.settings.resetToDefaults();
    await _syncPrayerCalculation();
  }

  void _toggleTilawatOrder() {
    if (_busy) return;
    setState(() {
      _tilawatOrderOpen = !_tilawatOrderOpen;
      if (_tilawatOrderOpen) _asrFiqahOpen = false;
    });
  }

  void _pickTilawatOrder(TilawatOrder order) {
    if (_busy) return;
    widget.settings.setTilawatOrder(order);
  }

  void _collapseExpandablePrefs({
    required GlobalKey key,
    required bool open,
    required VoidCallback collapse,
    required Offset position,
  }) {
    if (!open) return;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.attached) {
      final local = box.globalToLocal(position);
      if ((Offset.zero & box.size).contains(local)) return;
    }
    collapse();
  }

  void _onPagePointerDown(PointerDownEvent event) {
    _collapseExpandablePrefs(
      key: _tilawatBlockKey,
      open: _tilawatOrderOpen,
      collapse: () => setState(() => _tilawatOrderOpen = false),
      position: event.position,
    );
    _collapseExpandablePrefs(
      key: _asrFiqahBlockKey,
      open: _asrFiqahOpen,
      collapse: () => setState(() => _asrFiqahOpen = false),
      position: event.position,
    );
  }

  Future<void> _openDailyArrangement() async {
    if (_busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DailyRecitationScreen(
          dailyPlanStore: widget.dailyPlanStore,
          profiles: widget.profiles,
          learnedNotifyStore: widget.learnedNotifyStore,
        ),
      ),
    );
    if (mounted) await _loadPlan();
  }

  void _openTodaysRecitation() {
    if (_busy) return;
    ReaderNavScope.maybeOf(context)?.nav.openDestination(
      SidebarDestination.dailyRecitation,
    );
  }

  Future<void> _setReminderEnabled(bool value) async {
    if (_busy) return;
    final plan = _plan;
    if (plan == null) {
      await _openDailyArrangement();
      return;
    }
    final updated = DailyPlan(
      kind: plan.kind,
      amount: plan.amount,
      startSurah: plan.startSurah,
      startAyah: plan.startAyah,
      reminderEnabled: value,
      hour: plan.hour,
      minute: plan.minute,
      isPm: plan.isPm,
    );
    await widget.dailyPlanStore.save(updated);
    await AppNotificationScheduler.instance.rescheduleAll(
      plan: updated,
      learnedNotifyStore: widget.learnedNotifyStore,
      confirm: value,
    );
    if (!mounted) return;
    setState(() => _plan = updated);
  }

  Future<void> _openReminderClock() async {
    if (_busy) return;
    final plan = _plan;
    if (plan == null) {
      await _openDailyArrangement();
      return;
    }
    final draft = _ReminderTime(
      hour: plan.hour,
      minute: plan.minute,
      isPm: plan.isPm,
    );
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => _ReminderClockDialog(draft: draft),
    );
    if (!mounted) return;
    final updated = DailyPlan(
      kind: plan.kind,
      amount: plan.amount,
      startSurah: plan.startSurah,
      startAyah: plan.startAyah,
      reminderEnabled: true,
      hour: draft.hour,
      minute: draft.minute,
      isPm: draft.isPm,
    );
    await widget.dailyPlanStore.save(updated);
    await AppNotificationScheduler.instance.rescheduleAll(
      plan: updated,
      learnedNotifyStore: widget.learnedNotifyStore,
      confirm: true,
    );
    if (!mounted) return;
    setState(() => _plan = updated);
  }

  static String _planAmountLabel(DailyPlan plan) {
    if (plan.kind == DailyPlanKind.para) {
      return DailyPlanKindX.paraAmountLabel(plan.amount);
    }
    final unit = switch (plan.kind) {
      DailyPlanKind.ruku => 'Ruku',
      DailyPlanKind.ayah => 'Ayahs',
      DailyPlanKind.para => 'Paras',
      DailyPlanKind.page => 'Pages',
    };
    final amount = plan.amount == plan.amount.roundToDouble()
        ? plan.amount.round().toString()
        : plan.amount.toString();
    return '$amount $unit';
  }

  static String _planTimeLabel(DailyPlan plan) {
    final minute = plan.minute.toString().padLeft(2, '0');
    final period = plan.isPm ? 'PM' : 'AM';
    return '${plan.hour}:$minute $period';
  }

  String? _todaysRangeLabel() {
    final window = _window;
    if (window != null) {
      return _TodaysInfoCard.rangeLabel(window);
    }
    final plan = _plan;
    if (plan == null) return null;
    return '${_TodaysInfoCard.surahTitle(plan.startSurah)} · Ayah ${plan.startAyah}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        Navigator.of(context).pop(_pendingJump);
      },
      child: ReaderPageScaffold(
        title: 'Profile',
        body: ListenableBuilder(
          listenable: _listenable,
          builder: (context, _) {
            final items = widget.profiles.profiles;
            final active = widget.profiles.activeProfile;
            final settings = widget.settings;
            final plan = _plan;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final enabled = !_busy;

            return Directionality(
              textDirection: TextDirection.ltr,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPagePointerDown,
                child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _IdentityCard(
                        name: active?.name ?? 'Profile',
                        enabled: enabled,
                        onCommitName: active == null
                            ? null
                            : (name) => widget.profiles.rename(
                                  active.id,
                                  name,
                                ),
                        onCreateProfile: null,
                      ),
                      const SizedBox(height: 18),
                      const _SectionLabel('Switch profile'),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _AddProfileChip(
                                enabled: enabled,
                                onTap: () {
                                  setState(() {
                                    _tilawatOrderOpen = false;
                                    _asrFiqahOpen = false;
                                  });
                                  _create();
                                },
                              );
                            }
                            final profile = items[index - 1];
                            return _ProfileChip(
                              name: profile.name,
                              isActive: profile.id == active?.id,
                              enabled: enabled,
                              onTap: () => _select(profile),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      _TodaysInfoCard(
                        range: _todaysRangeLabel(),
                        enabled: enabled,
                        onTap: _openTodaysRecitation,
                      ),
                      const SizedBox(height: 14),
                      _PrefCard(
                        children: [
                          _PrefNavRow(
                            icon: Icons.event_note_outlined,
                            title: 'Daily recitation plan',
                            value: plan == null
                                ? 'No plan'
                                : _planAmountLabel(plan),
                            enabled: enabled,
                            onTap: _openDailyArrangement,
                          ),
                          _PrefSwitchNavRow(
                            icon: Icons.notifications_outlined,
                            title: 'Recitation reminder',
                            value: plan == null
                                ? 'Set a plan first'
                                : plan.reminderEnabled
                                ? _planTimeLabel(plan)
                                : 'Off',
                            valueLtr: plan != null && plan.reminderEnabled,
                            switchValue: plan?.reminderEnabled ?? false,
                            enabled: enabled,
                            onSwitch: _setReminderEnabled,
                            onTap: _openReminderClock,
                          ),
                          KeyedSubtree(
                            key: _tilawatBlockKey,
                            child: _TilawatOrderBlock(
                              selected: settings.tilawatOrder,
                              expanded: _tilawatOrderOpen,
                              enabled: enabled,
                              onToggle: _toggleTilawatOrder,
                              onPick: _pickTilawatOrder,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _SectionLabel('Recitation'),
                      const SizedBox(height: 8),
                      _PrefCard(
                        children: [
                          _PrefNavRow(
                            icon: Icons.groups_outlined,
                            title: 'Choose a reciter',
                            value: settings.reciterLabel,
                            enabled: enabled,
                            onTap: _openReciterPicker,
                          ),
                          _PrefSwitchNavRow(
                            icon: Icons.translate_outlined,
                            title: 'Spoken translation',
                            value: settings.audioLanguageLabel,
                            switchValue: settings.audioTranslationEnabled,
                            enabled: enabled,
                            onSwitch: settings.setAudioTranslationEnabled,
                            onTap: _openAudioLanguagePicker,
                          ),
                          _PrefSwitchRow(
                            icon: Icons.headphones_outlined,
                            title: 'Background recitation',
                            value: settings.backgroundRecitation,
                            enabled: enabled,
                            onChanged: settings.setBackgroundRecitation,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _SectionLabel('Translation'),
                      const SizedBox(height: 8),
                      _PrefCard(
                        children: [
                          _PrefSwitchNavRow(
                            icon: Icons.public,
                            title: 'Show translation',
                            value: settings.translatorLabel,
                            switchValue: !settings.hideTranslation,
                            enabled: enabled,
                            onSwitch: (value) {
                              settings.setHideTranslation(!value);
                            },
                            onTap: _openTranslatorPicker,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _SectionLabel('Prayer'),
                      const SizedBox(height: 8),
                      _PrefCard(
                        children: [
                          KeyedSubtree(
                            key: _asrFiqahBlockKey,
                            child: _AsrFiqahBlock(
                              selectedId: settings.prayerFiqahId,
                              selectedLabel: settings.prayerFiqahLabel,
                              expanded: _asrFiqahOpen,
                              enabled: enabled,
                              onToggle: _toggleAsrFiqah,
                              onPick: _pickAsrFiqah,
                            ),
                          ),
                          _PrefSwitchNavRow(
                            icon: Icons.surround_sound_outlined,
                            title: 'Azaan',
                            value: settings.azaanLabel,
                            switchValue: settings.azaanEnabled,
                            enabled: enabled,
                            onSwitch: _setAzaanEnabled,
                            onTap: _openAzaanPicker,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _SectionLabel('Appearance'),
                      const SizedBox(height: 8),
                      _PrefCard(
                        children: [
                          _PrefSwitchRow(
                            icon: Icons.nightlight_outlined,
                            title: 'Read in the dark',
                            value: isDark,
                            enabled: enabled,
                            onChanged: (value) {
                              settings.setThemeMode(
                                value ? ThemeMode.dark : ThemeMode.light,
                              );
                            },
                          ),
                          _PrefSwitchRow(
                            icon: Icons.palette_outlined,
                            title: 'Tajweed colors',
                            value: settings.tajweedEnabled,
                            enabled: enabled,
                            onChanged: settings.setTajweedEnabled,
                          ),
                          _PrefNavRow(
                            icon: Icons.history_edu_outlined,
                            title: 'Mushaf script',
                            value: settings.mushafScriptLabel,
                            enabled: enabled,
                            onTap: _openMushafScript,
                          ),
                          _PrefNavRow(
                            icon: Icons.format_size,
                            title: 'Text size',
                            value: settings.fontSize.round().toString(),
                            enabled: enabled,
                            onTap: _openTextSize,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _FooterAction(
                        icon: Icons.settings_backup_restore,
                        label: 'Reset to defaults',
                        enabled: enabled,
                        onTap: _confirmResetPreferences,
                      ),
                      const SizedBox(height: 10),
                      _FooterAction(
                        icon: Icons.delete_outline,
                        label: 'Delete profile',
                        enabled: enabled && active != null,
                        destructive: true,
                        onTap: active == null
                            ? null
                            : () => _delete(active),
                      ),
                    ],
                  ),
                  if (_busy)
                    const ColoredBox(
                      color: Color(0x33000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _OrangeButton(
      icon: icon,
      label: label,
      enabled: enabled,
      destructive: destructive,
      onPressed: onTap,
    );
  }
}

class _OrangeButton extends StatelessWidget {
  const _OrangeButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.outlined = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;
  final bool outlined;
  final bool destructive;

  static const _radius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    final fill = destructive ? AppTheme.danger : AppTheme.orange;
    final onFill = Colors.white;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: outlined ? fill : onFill),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: outlined ? fill : onFill,
            ),
          ),
        ),
      ],
    );
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: fill,
            side: BorderSide(color: fill),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: const RoundedRectangleBorder(borderRadius: _radius),
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 48,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            foregroundColor: onFill,
            disabledBackgroundColor: fill.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: const RoundedRectangleBorder(borderRadius: _radius),
          ),
          child: child,
        ),
    );
  }
}

class _ThemedDialog extends StatelessWidget {
  const _ThemedDialog({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.orange.withValues(alpha: isDark ? 0.55 : 0.35),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.orange.withValues(alpha: isDark ? 0.16 : 0.1),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 12),
                body,
                const SizedBox(height: 16),
                if (actions.length <= 1)
                  ...actions
                else
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppSwitch extends StatelessWidget {
  const _AppSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: AppTheme.orange,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: const Color(0xFF8E8E8E),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

BoxDecoration _profileCardDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: isDark ? const Color(0xFF1C2220) : Colors.white,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _IdentityCard extends StatefulWidget {
  const _IdentityCard({
    required this.name,
    required this.enabled,
    required this.onCommitName,
    this.onCreateProfile,
  });

  final String name;
  final bool enabled;
  final Future<void> Function(String name)? onCommitName;
  final VoidCallback? onCreateProfile;

  @override
  State<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends State<_IdentityCard> {
  bool _editing = false;
  late final TextEditingController _controller =
      TextEditingController(text: widget.name);
  late final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _IdentityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.name != widget.name) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _beginEdit() {
    if (!widget.enabled || widget.onCommitName == null || _editing) return;
    _controller.text = widget.name;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _commit() async {
    if (!_editing) return;
    final next = _controller.text.trim();
    setState(() => _editing = false);
    _focus.unfocus();
    if (next.isEmpty || next == widget.name) {
      _controller.text = widget.name;
      return;
    }
    await widget.onCommitName?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return DecoratedBox(
      decoration: _profileCardDecoration(context),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: 16,
          end: 4,
          top: 12,
          bottom: 12,
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: AppTheme.orange,
              child: Icon(
                Icons.person,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _editing
                  ? TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      onSubmitted: (_) => _commit(),
                      onTapOutside: (_) => _commit(),
                    )
                  : GestureDetector(
                      onTap: _beginEdit,
                      child: Text(
                        widget.name,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
            ),
            IconButton(
              tooltip: 'Rename',
              onPressed: widget.enabled ? _beginEdit : null,
              icon: const Icon(Icons.edit_outlined, color: AppTheme.orange),
            ),
            if (widget.onCreateProfile != null)
              IconButton(
                tooltip: 'New profile',
                onPressed: widget.enabled ? widget.onCreateProfile : null,
                icon: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: AppTheme.orange,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddProfileChip extends StatelessWidget {
  const _AddProfileChip({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.orange, width: 1.1),
          ),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.add, color: AppTheme.orange, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.name,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: isActive ? AppTheme.orange : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.orange,
              width: 1.1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive) ...[
                  const Icon(Icons.check, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Colors.white : ink,
                    ),
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

class _TodaysInfoCard extends StatelessWidget {
  const _TodaysInfoCard({
    required this.range,
    required this.enabled,
    required this.onTap,
  });

  final String? range;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(10));
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: AppTheme.barGradient,
            borderRadius: radius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.auto_stories_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Today's recitation",
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        range ?? 'No plan',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
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
    );
  }

  static String rangeLabel(AyahWindow window) {
    final startSurah = surahTitle(window.start.surah);
    final endSurah = surahTitle(window.end.surah);
    if (window.start.surah == window.end.surah) {
      return '$startSurah · Ayah ${window.start.ayah} to ayah ${window.end.ayah}';
    }
    return '$startSurah Ayah ${window.start.ayah} to $endSurah Ayah ${window.end.ayah}';
  }

  static String surahTitle(int surah) {
    final meta = QuranMetadata.surahOrNull(surah);
    final name = meta?.listTitle ?? QuranMetadata.nameArOrEmpty(surah);
    if (name.isEmpty) return 'Surah $surah';
    if (name.startsWith('Surah') || name.startsWith('سورة')) return name;
    return 'Surah $name';
  }
}

class _PrefCard extends StatelessWidget {
  const _PrefCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 0.6,
            indent: 14,
            endIndent: 14,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE8E8E8),
          ),
        );
      }
      rows.add(children[i]);
    }
    return DecoratedBox(
      decoration: _profileCardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: rows),
      ),
    );
  }
}

class _AsrFiqahBlock extends StatelessWidget {
  const _AsrFiqahBlock({
    required this.selectedId,
    required this.selectedLabel,
    required this.expanded,
    required this.enabled,
    required this.onToggle,
    required this.onPick,
  });

  final String selectedId;
  final String selectedLabel;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isDark = theme.brightness == Brightness.dark;
    final nest = isDark
        ? Colors.black.withValues(alpha: 0.22)
        : const Color(0xFFF2F2F2);
    return Column(
      children: [
        _PrefInk(
          enabled: enabled,
          onTap: onToggle,
          child: Row(
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: 22,
                color: AppTheme.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Asr time',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedLabel,
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more, color: muted),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: ColoredBox(
            color: nest,
            child: Column(
              children: [
                for (final option in PrayerCalculationCatalog.fiqahs)
                  _TilawatOrderChoice(
                    label: option.labelUr,
                    selected: option.id == selectedId,
                    enabled: enabled,
                    onTap: () => onPick(option.id),
                  ),
              ],
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}

class _TilawatOrderBlock extends StatelessWidget {
  const _TilawatOrderBlock({
    required this.selected,
    required this.expanded,
    required this.enabled,
    required this.onToggle,
    required this.onPick,
  });

  final TilawatOrder selected;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<TilawatOrder> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isDark = theme.brightness == Brightness.dark;
    final nest = isDark
        ? Colors.black.withValues(alpha: 0.22)
        : const Color(0xFFF2F2F2);
    return Column(
      children: [
        _PrefInk(
          enabled: enabled,
          onTap: onToggle,
          child: Row(
            children: [
              const Icon(
                Icons.queue_music_outlined,
                size: 22,
                color: AppTheme.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Recitation order',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected.label,
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more, color: muted),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: ColoredBox(
            color: nest,
            child: Column(
              children: [
                for (final order in TilawatOrder.values)
                  _TilawatOrderChoice(
                    label: order.label,
                    selected: order == selected,
                    enabled: enabled,
                    onTap: () => onPick(order),
                  ),
              ],
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}

class _TilawatOrderChoice extends StatelessWidget {
  const _TilawatOrderChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return _PrefInk(
      enabled: enabled,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: selected ? AppTheme.orange : ink.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.orange : ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrefNavRow extends StatelessWidget {
  const _PrefNavRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PrefInk(
      enabled: enabled,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrefSwitchRow extends StatelessWidget {
  const _PrefSwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _AppSwitch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _PrefSwitchNavRow extends StatelessWidget {
  const _PrefSwitchNavRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.switchValue,
    required this.enabled,
    required this.onSwitch,
    required this.onTap,
    this.valueLtr = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool switchValue;
  final bool enabled;
  final ValueChanged<bool> onSwitch;
  final VoidCallback onTap;
  final bool valueLtr;

  @override
  Widget build(BuildContext context) {
    return _PrefInk(
      enabled: enabled,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  textAlign: TextAlign.left,
                  textDirection:
                      valueLtr ? TextDirection.ltr : TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AppSwitch(
            value: switchValue,
            onChanged: enabled ? onSwitch : null,
          ),
        ],
      ),
    );
  }
}

class _PrefInk extends StatelessWidget {
  const _PrefInk({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: child,
        ),
      ),
    );
  }
}

/// Owns its [TextEditingController] so it is disposed with the dialog route,
/// not while the exit animation is still rebuilding the field.
class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
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
    return _ThemedDialog(
      title: widget.title,
      body: TextField(
        controller: _controller,
        autofocus: true,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: 16, color: ink),
        cursorColor: AppTheme.orange,
        decoration: InputDecoration(
          hintText: 'Enter a name',
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: AppTheme.orange.withValues(alpha: 0.45),
            ),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.orange, width: 1.6),
          ),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        _OrangeButton(
          label: 'Save',
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
        _OrangeButton(
          label: 'Cancel',
          outlined: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ReminderTime {
  _ReminderTime({
    required this.hour,
    required this.minute,
    required this.isPm,
  });

  int hour;
  int minute;
  bool isPm;
}

class _ReminderClockDialog extends StatefulWidget {
  const _ReminderClockDialog({required this.draft});

  final _ReminderTime draft;

  @override
  State<_ReminderClockDialog> createState() => _ReminderClockDialogState();
}

class _ReminderClockDialogState extends State<_ReminderClockDialog> {
  static const _minutes = <int>[
    0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55,
  ];
  static const _itemExtent = 40.0;

  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;
  late final FixedExtentScrollController _periodCtrl;

  @override
  void initState() {
    super.initState();
    var minuteIndex = _minutes.indexOf(widget.draft.minute);
    if (minuteIndex < 0) {
      minuteIndex = 0;
      var dist = 60;
      for (var i = 0; i < _minutes.length; i++) {
        final d = (widget.draft.minute - _minutes[i]).abs();
        if (d < dist) {
          dist = d;
          minuteIndex = i;
        }
      }
      widget.draft.minute = _minutes[minuteIndex];
    }
    _hourCtrl = FixedExtentScrollController(
      initialItem: (widget.draft.hour - 1).clamp(0, 11),
    );
    _minuteCtrl = FixedExtentScrollController(initialItem: minuteIndex);
    _periodCtrl = FixedExtentScrollController(
      initialItem: widget.draft.isPm ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _periodCtrl.dispose();
    super.dispose();
  }

  void _setHour(int index) {
    setState(() => widget.draft.hour = index + 1);
  }

  void _setMinute(int index) {
    setState(() => widget.draft.minute = _minutes[index]);
  }

  void _setPeriod(int index) {
    setState(() => widget.draft.isPm = index == 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = theme.scaffoldBackgroundColor;
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final draft = widget.draft;
    final time =
        '${draft.hour}:${draft.minute.toString().padLeft(2, '0')} '
        '${draft.isPm ? 'PM' : 'AM'}';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.orange.withValues(alpha: isDark ? 0.55 : 0.35),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.orange.withValues(alpha: isDark ? 0.16 : 0.1),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reminder time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  time,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w300,
                    color: AppTheme.orange,
                    height: 1.1,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 148,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.orange.withValues(
                            alpha: isDark ? 0.14 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const SizedBox(
                          height: _itemExtent,
                          width: double.infinity,
                        ),
                      ),
                      Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          Expanded(
                            child: _ClockWheel(
                              controller: _hourCtrl,
                              childCount: 12,
                              selectedIndex: draft.hour - 1,
                              onSelected: _setHour,
                              labelBuilder: (index) => '${index + 1}',
                            ),
                          ),
                          Text(
                            ':',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w300,
                              color: muted,
                            ),
                          ),
                          Expanded(
                            child: _ClockWheel(
                              controller: _minuteCtrl,
                              childCount: _minutes.length,
                              selectedIndex: _minutes.indexOf(draft.minute)
                                  .clamp(0, _minutes.length - 1),
                              onSelected: _setMinute,
                              labelBuilder: (index) => _minutes[index]
                                  .toString()
                                  .padLeft(2, '0'),
                            ),
                          ),
                          Expanded(
                            child: _ClockWheel(
                              controller: _periodCtrl,
                              childCount: 2,
                              selectedIndex: draft.isPm ? 1 : 0,
                              onSelected: _setPeriod,
                              labelBuilder: (index) =>
                                  index == 0 ? 'AM' : 'PM',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GoldDoneButton(
                  label: 'Save',
                  wide: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockWheel extends StatelessWidget {
  const _ClockWheel({
    required this.controller,
    required this.childCount,
    required this.selectedIndex,
    required this.onSelected,
    required this.labelBuilder,
  });

  final FixedExtentScrollController controller;
  final int childCount;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String Function(int index) labelBuilder;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _ReminderClockDialogState._itemExtent,
      diameterRatio: 1.6,
      perspective: 0.003,
      overAndUnderCenterOpacity: 0.35,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: childCount,
        builder: (context, index) {
          final selected = index == selectedIndex;
          return Center(
            child: Text(
              labelBuilder(index),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: selected ? 22 : 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? ink : muted,
              ),
            ),
          );
        },
      ),
    );
  }
}
