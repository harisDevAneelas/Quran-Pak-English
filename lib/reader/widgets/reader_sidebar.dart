import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../reader_settings.dart';

/// Dark-contrast palette for the navigation sidebar.
abstract final class _SidebarColors {
  static const Color background = Color(0xFF3C3C3C);
  static const Color tile = Color(0xFF3C3C3C);
  static const Color text = Color(0xFFF5F5F5);
  static const Color textMuted = Color(0xFFB0B0B0);
}

/// Where a sidebar row should take the reader.
enum SidebarDestination {
  dailyRecitation,
  dailyArrangement,
  surahList,
  paraList,
  manzil,
  search,
  bookmarks,
  profiles,
  reciter,
  audioLanguage,
  translator,
  shareApp,
  mushafScript,
  textSize,
}

/// Top-right reader menu: lists, reading tools, and display toggles.
class ReaderMenuDrawer extends StatefulWidget {
  const ReaderMenuDrawer({
    super.key,
    required this.settings,
    required this.activeProfileName,
    required this.onDestination,
  });

  final ReaderSettings settings;
  final String activeProfileName;
  final ValueChanged<SidebarDestination> onDestination;

  @override
  State<ReaderMenuDrawer> createState() => _ReaderMenuDrawerState();
}

class _ReaderMenuDrawerState extends State<ReaderMenuDrawer> {
  Future<void> _confirmResetPreferences(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: AlertDialog(
            title: const Text('Reset to defaults?'),
            content: const Text(
              'Reciter, translation, Tajweed, light or dark, text size, and other '
              "preferences return to defaults. Bookmarks and today's recitation stay.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Reset'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    widget.settings.resetToDefaults();
    if (context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final drawerWidth = size.width * 0.58;

    return Drawer(
      width: drawerWidth,
      backgroundColor: _SidebarColors.background,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) {
              final isDark =
                  Theme.of(context).brightness == Brightness.dark;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      end: 4,
                      top: 8,
                      bottom: 8,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Menu',
                            textAlign: TextAlign.left,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              color: _SidebarColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _trailingSlot(
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () =>
                                Scaffold.maybeOf(context)?.closeDrawer(),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 40,
                            ),
                            icon: const Directionality(
                              textDirection: TextDirection.ltr,
                              child: Icon(
                                Icons.first_page_outlined,
                                color: _SidebarColors.text,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _Separator(),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _TodaysTilawatRow(
                          onOpenTodays: () => widget.onDestination(
                            SidebarDestination.dailyRecitation,
                          ),
                          onOpenSettings: () => widget.onDestination(
                            SidebarDestination.dailyArrangement,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Surah list',
                          icon: _sidebarIcon(Icons.menu_book_outlined),
                          onTap: () => widget.onDestination(
                            SidebarDestination.surahList,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Juz list',
                          icon: _sidebarIcon(Icons.library_books_outlined),
                          onTap: () => widget.onDestination(
                            SidebarDestination.paraList,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Manzil',
                          icon: _sidebarIcon(Icons.mosque_outlined),
                          onTap: () => widget.onDestination(
                            SidebarDestination.manzil,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Search',
                          icon: _sidebarIcon(Icons.search),
                          onTap: () => widget.onDestination(
                            SidebarDestination.search,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Bookmarks',
                          icon: _sidebarIcon(Icons.format_list_bulleted),
                          onTap: () => widget.onDestination(
                            SidebarDestination.bookmarks,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Profile',
                          icon: _sidebarIcon(Icons.person_outline),
                          trailing: Text(
                            widget.activeProfileName,
                            style: const TextStyle(
                              color: _SidebarColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: () => widget.onDestination(
                            SidebarDestination.profiles,
                          ),
                        ),
                        const _ThickSeparator(),
                        _MenuButton(
                          title: 'Choose a reciter',
                          subtitle: widget.settings.reciterLabel,
                          icon: _sidebarIcon(Icons.groups_outlined),
                          onTap: () => widget.onDestination(
                            SidebarDestination.reciter,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Spoken translation',
                          subtitle: widget.settings.audioLanguageLabel,
                          icon: _sidebarIcon(Icons.translate_outlined),
                          trailing: _trailingSlot(
                            _SidebarSwitch(
                              value: widget.settings.audioTranslationEnabled,
                              onChanged:
                                  widget.settings.setAudioTranslationEnabled,
                            ),
                          ),
                          onTap: () => widget.onDestination(
                            SidebarDestination.audioLanguage,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Show translation',
                          subtitle: widget.settings.translatorLabel,
                          icon: _sidebarIcon(Icons.public),
                          trailing: _trailingSlot(
                            _SidebarSwitch(
                              value: !widget.settings.hideTranslation,
                              onChanged: (value) {
                                widget.settings.setHideTranslation(!value);
                              },
                            ),
                          ),
                          onTap: () => widget.onDestination(
                            SidebarDestination.translator,
                          ),
                        ),
                        const _Separator(),
                        _ToggleTile(
                          title: 'Read in the dark',
                          icon: _sidebarIcon(Icons.nightlight_outlined),
                          value: isDark,
                          onChanged: (value) {
                            widget.settings.setThemeMode(
                              value ? ThemeMode.dark : ThemeMode.light,
                            );
                          },
                        ),
                        const _Separator(),
                        _ToggleTile(
                          title: 'Tajweed colors',
                          icon: _sidebarIcon(Icons.palette_outlined),
                          value: widget.settings.tajweedEnabled,
                          onChanged: widget.settings.setTajweedEnabled,
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Share with others',
                          icon: _sidebarIcon(Icons.favorite_border),
                          onTap: () => widget.onDestination(
                            SidebarDestination.shareApp,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Mushaf script',
                          subtitle: widget.settings.mushafScriptLabel,
                          icon: _sidebarIcon(Icons.history_edu_outlined),
                          onTap: () => widget.onDestination(
                            SidebarDestination.mushafScript,
                          ),
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Text size',
                          icon: _sidebarIcon(Icons.format_size),
                          onTap: () => widget.onDestination(
                            SidebarDestination.textSize,
                          ),
                        ),
                        const _Separator(),
                        _ToggleTile(
                          title: 'Background recitation',
                          icon: _sidebarIcon(Icons.headphones_outlined),
                          value: widget.settings.backgroundRecitation,
                          onChanged: widget.settings.setBackgroundRecitation,
                        ),
                        const _Separator(),
                        _MenuButton(
                          title: 'Reset to defaults',
                          subtitle: 'Reset every preference',
                          icon: _sidebarIcon(Icons.settings_backup_restore),
                          onTap: () => _confirmResetPreferences(context),
                        ),
                        const _Separator(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.orange.withValues(alpha: 0.14),
    );
  }
}

/// Thick section break after bookmarks.
class _ThickSeparator extends StatelessWidget {
  const _ThickSeparator();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF000000),
      child: SizedBox(height: 3, width: double.infinity),
    );
  }
}

/// Top row: Today's recitation + settings gear for daily arrangement.
class _TodaysTilawatRow extends StatelessWidget {
  const _TodaysTilawatRow({
    required this.onOpenTodays,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenTodays;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.orange.withValues(alpha: 0.16),
      child: InkWell(
        onTap: onOpenTodays,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              _sidebarIcon(Icons.auto_stories_outlined),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  "Today's recitation",
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: _SidebarColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _trailingSlot(
                IconButton(
                  tooltip: 'Daily recitation plan',
                  onPressed: onOpenSettings,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 40,
                  ),
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: AppTheme.orange,
                    size: 22,
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

Widget _sidebarIcon(IconData icon) {
  return SizedBox(
    width: 22,
    child: Icon(icon, color: _SidebarColors.text, size: 20),
  );
}

/// Trailing control column (close, gear, switch) shares this width.
Widget _trailingSlot(Widget child) {
  return SizedBox(
    width: 48,
    child: Center(child: child),
  );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return Material(
      color: _SidebarColors.tile,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: hasSubtitle ? 72 : 52,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  child: icon == null ? null : Center(child: icon),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              textAlign: TextAlign.left,
                              maxLines: 1,
                              softWrap: false,
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                color: _SidebarColors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ),
                        if (hasSubtitle) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            textAlign: TextAlign.left,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              color: _SidebarColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _SidebarColors.tile,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                child: icon == null ? null : Center(child: icon),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: _SidebarColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
              _trailingSlot(
                _SidebarSwitch(value: value, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSwitch extends StatelessWidget {
  const _SidebarSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 28,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTheme.orange,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF8E8E8E),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the reader text-size slider.
///
/// Drag updates a local preview only; the mushaf size commits on finger-up
/// so HarfBuzz reshape / prefs write do not lag the thumb.
class TextSizeBottomSheet extends StatefulWidget {
  const TextSizeBottomSheet({super.key, required this.settings});

  final ReaderSettings settings;

  @override
  State<TextSizeBottomSheet> createState() => _TextSizeBottomSheetState();
}

class _TextSizeBottomSheetState extends State<TextSizeBottomSheet> {
  late double _previewSize;

  @override
  void initState() {
    super.initState();
    _previewSize = widget.settings.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Text size  ${_previewSize.round()}',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
              Slider(
                value: _previewSize,
                min: 18,
                max: 56,
                divisions: 38,
                onChanged: (value) {
                  setState(() => _previewSize = value);
                },
                onChangeEnd: widget.settings.setFontSize,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
