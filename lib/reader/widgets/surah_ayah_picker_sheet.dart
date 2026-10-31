import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../data/quran_metadata.dart';

const _pickerBar = Color(0xFF3A3A3A);
const _pickerItemExtent = 36.0;
const _pickerWheelHeight = 200.0;

const _hubItemExtent = 48.0;
const _hubWheelHeight = 220.0;

/// Wheel-style Surah + Ayah picker (same look as daily-plan setup).
///
/// Slides down from the top; the bottom Done / dismiss slides it back up.
/// Returns `(surah, ayah)` when the user confirms, or `null` if dismissed.
Future<({int surah, int ayah})?> showSurahAyahPickerSheet({
  required BuildContext context,
  required int initialSurah,
  required int initialAyah,
}) {
  return _showTopSlidePicker<({int surah, int ayah})>(
    context: context,
    child: SurahAyahPickerSheet(
      initialSurah: initialSurah,
      initialAyah: initialAyah,
    ),
  );
}

/// Full-page blurred surah wheel for the hub Surah list tile.
///
/// Stays on the hub route; the hub grid blurs behind the picker.
Future<int?> showSurahListPickerSheet({
  required BuildContext context,
  required int initialSurah,
}) {
  return _showHubBlurPicker<int>(
    context: context,
    child: SurahListPickerSheet(initialSurah: initialSurah),
  );
}

/// Full-page blurred para wheel for the hub Para list tile.
///
/// Returns the selected para's first ayah (`startSurah` / `startAyah`).
Future<({int surah, int ayah})?> showParaListPickerSheet({
  required BuildContext context,
  required int initialSurah,
  required int initialAyah,
}) {
  return _showHubBlurPicker<({int surah, int ayah})>(
    context: context,
    child: ParaListPickerSheet(
      initialSurah: initialSurah,
      initialAyah: initialAyah,
    ),
  );
}

/// Full-screen overlay: hub stays visible but blurred.
///
/// Blur is applied immediately (not faded) — animating [BackdropFilter]
/// opacity is expensive and looks like a delayed transparent flash.
/// Tap outside the compact wheel panel dismisses back to the hub menu.
Future<T?> _showHubBlurPicker<T>({
  required BuildContext context,
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final panelFade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          // Instant dim + blur — do not wrap in FadeTransition.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const ColoredBox(
                color: Color(0x59000000),
              ),
            ),
          ),
          FadeTransition(
            opacity: panelFade,
            child: Center(child: child),
          ),
        ],
      );
    },
  );
}

Future<T?> _showTopSlidePicker<T>({
  required BuildContext context,
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class SurahAyahPickerSheet extends StatefulWidget {
  const SurahAyahPickerSheet({
    super.key,
    required this.initialSurah,
    required this.initialAyah,
  });

  final int initialSurah;
  final int initialAyah;

  @override
  State<SurahAyahPickerSheet> createState() => _SurahAyahPickerSheetState();
}

class _SurahAyahPickerSheetState extends State<SurahAyahPickerSheet> {
  QuranMetadata? _meta;
  bool _ready = false;
  bool _controllersReady = false;

  late FixedExtentScrollController _surahCtrl;
  late FixedExtentScrollController _ayahCtrl;

  int _surah = 1;
  int _ayah = 1;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final meta = await QuranMetadata.load();
    final surah = widget.initialSurah.clamp(1, meta.surahs.length);
    final maxAyah = meta.surahs[surah - 1].ayahCount;
    final ayah = widget.initialAyah.clamp(1, maxAyah);

    _surahCtrl = FixedExtentScrollController(initialItem: surah - 1);
    _ayahCtrl = FixedExtentScrollController(initialItem: ayah - 1);
    _controllersReady = true;

    if (!mounted) {
      _disposeControllers();
      return;
    }

    setState(() {
      _meta = meta;
      _surah = surah;
      _ayah = ayah;
      _ready = true;
    });
  }

  void _disposeControllers() {
    if (!_controllersReady) return;
    _surahCtrl.dispose();
    _ayahCtrl.dispose();
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

  void _confirm() {
    Navigator.of(context).pop((surah: _surah, ayah: _ayah));
  }

  @override
  Widget build(BuildContext context) {
    return _PickerShell(
      title: 'Choose surah and ayah',
      ready: _ready,
      onConfirm: _ready ? _confirm : null,
      wheel: !_ready
          ? null
          : Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  flex: 3,
                  child: _PickerWheel(
                    controller: _surahCtrl,
                    childCount: _meta!.surahs.length,
                    selectedIndex: _surah - 1,
                    alignStart: true,
                    onSelected: _onSurahChanged,
                    labelBuilder: (index) {
                      final item = _meta!.surahs[index];
                      return '${item.listTitle} · ${item.surah}';
                    },
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _PickerWheel(
                    controller: _ayahCtrl,
                    childCount: _ayahCount(_surah),
                    selectedIndex: _ayah - 1,
                    onSelected: (index) {
                      final ayah = index + 1;
                      if (ayah == _ayah) return;
                      setState(() => _ayah = ayah);
                    },
                    labelBuilder: (index) {
                      final n = index + 1;
                      return n == _ayah ? '$n Ayah' : '$n';
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class SurahListPickerSheet extends StatefulWidget {
  const SurahListPickerSheet({
    super.key,
    required this.initialSurah,
  });

  final int initialSurah;

  @override
  State<SurahListPickerSheet> createState() => _SurahListPickerSheetState();
}

class _SurahListPickerSheetState extends State<SurahListPickerSheet> {
  QuranMetadata? _meta;
  bool _ready = false;
  bool _controllerReady = false;

  late FixedExtentScrollController _surahCtrl;
  int _surah = 1;

  @override
  void initState() {
    super.initState();
    final cached = QuranMetadata.cached;
    if (cached != null) {
      _applyMeta(cached);
    } else {
      _bootstrap();
    }
  }

  void _applyMeta(QuranMetadata meta) {
    final surah = widget.initialSurah.clamp(1, meta.surahs.length);
    _surahCtrl = FixedExtentScrollController(initialItem: surah - 1);
    _controllerReady = true;
    _meta = meta;
    _surah = surah;
    _ready = true;
  }

  Future<void> _bootstrap() async {
    final meta = await QuranMetadata.load();
    if (!mounted) return;
    setState(() => _applyMeta(meta));
  }

  void _disposeController() {
    if (!_controllerReady) return;
    _surahCtrl.dispose();
    _controllerReady = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(_surah);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _HubPickerShell(
      title: 'Choose a surah',
      ready: _ready,
      onConfirm: _ready ? _confirm : null,
      wheel: !_ready
          ? null
          : _PickerWheel(
              controller: _surahCtrl,
              childCount: _meta!.surahs.length,
              selectedIndex: _surah - 1,
              itemExtent: _hubItemExtent,
              selectedFontSize: 20,
              unselectedFontSize: 16,
              selectedColor:
                  isDark ? Colors.white : const Color(0xFF1C140C),
              unselectedColor: isDark
                  ? const Color(0xB3FFFFFF)
                  : const Color(0x8A1C140C),
              onSelected: (index) {
                final surah = index + 1;
                if (surah == _surah) return;
                setState(() => _surah = surah);
              },
              labelBuilder: (index) {
                final item = _meta!.surahs[index];
                return '${item.listTitle} · ${item.surah}';
              },
            ),
    );
  }
}

class ParaListPickerSheet extends StatefulWidget {
  const ParaListPickerSheet({
    super.key,
    required this.initialSurah,
    required this.initialAyah,
  });

  final int initialSurah;
  final int initialAyah;

  @override
  State<ParaListPickerSheet> createState() => _ParaListPickerSheetState();
}

class _ParaListPickerSheetState extends State<ParaListPickerSheet> {
  QuranMetadata? _meta;
  bool _ready = false;
  bool _controllerReady = false;

  late FixedExtentScrollController _juzCtrl;
  int _juzIndex = 0;

  @override
  void initState() {
    super.initState();
    final cached = QuranMetadata.cached;
    if (cached != null) {
      _applyMeta(cached);
    } else {
      _bootstrap();
    }
  }

  void _applyMeta(QuranMetadata meta) {
    final juzIndex = _juzIndexFor(
      meta,
      widget.initialSurah,
      widget.initialAyah,
    );
    _juzCtrl = FixedExtentScrollController(initialItem: juzIndex);
    _controllerReady = true;
    _meta = meta;
    _juzIndex = juzIndex;
    _ready = true;
  }

  Future<void> _bootstrap() async {
    final meta = await QuranMetadata.load();
    if (!mounted) return;
    setState(() => _applyMeta(meta));
  }

  /// Index of the juz that contains [surah]:[ayah], or 0 if none match.
  static int _juzIndexFor(QuranMetadata meta, int surah, int ayah) {
    for (var i = 0; i < meta.juz.length; i++) {
      final j = meta.juz[i];
      final afterStart = surah > j.startSurah ||
          (surah == j.startSurah && ayah >= j.startAyah);
      final beforeEnd =
          surah < j.endSurah || (surah == j.endSurah && ayah <= j.endAyah);
      if (afterStart && beforeEnd) return i;
    }
    return 0;
  }

  void _disposeController() {
    if (!_controllerReady) return;
    _juzCtrl.dispose();
    _controllerReady = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _confirm() {
    final j = _meta!.juz[_juzIndex];
    Navigator.of(context).pop((surah: j.startSurah, ayah: j.startAyah));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _HubPickerShell(
      title: 'Choose a para',
      ready: _ready,
      onConfirm: _ready ? _confirm : null,
      wheel: !_ready
          ? null
          : _PickerWheel(
              controller: _juzCtrl,
              childCount: _meta!.juz.length,
              selectedIndex: _juzIndex,
              itemExtent: _hubItemExtent,
              selectedFontSize: 20,
              unselectedFontSize: 16,
              selectedColor:
                  isDark ? Colors.white : const Color(0xFF1C140C),
              unselectedColor: isDark
                  ? const Color(0xB3FFFFFF)
                  : const Color(0x8A1C140C),
              onSelected: (index) {
                if (index == _juzIndex) return;
                setState(() => _juzIndex = index);
              },
              labelBuilder: (index) {
                final j = _meta!.juz[index];
                return '${j.displayName} · ${j.juz}';
              },
            ),
    );
  }
}

class _PickerShell extends StatelessWidget {
  const _PickerShell({
    required this.title,
    required this.ready,
    required this.onConfirm,
    required this.wheel,
  });

  final String title;
  final bool ready;
  final VoidCallback? onConfirm;
  final Widget? wheel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;

    // Status bar is transparent app-wide; paint the header under it so the
    // system icons sit on the same grey as the title bar.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _pickerBar,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Material(
        color: theme.scaffoldBackgroundColor,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxBody = MediaQuery.sizeOf(context).height * 0.72;
            final wheelH = _pickerWheelHeight
                .clamp(120.0, maxBody - 120)
                .toDouble();

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBody),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: _pickerBar,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, top + 10, 16, 12),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    _WheelBand(
                      ready: ready,
                      wheel: wheel,
                      height: wheelH,
                      itemExtent: _pickerItemExtent,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(160, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onConfirm,
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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

/// Compact hub wheel panel, centered on the blurred hub.
class _HubPickerShell extends StatelessWidget {
  const _HubPickerShell({
    required this.title,
    required this.ready,
    required this.onConfirm,
    required this.wheel,
  });

  final String title;
  final bool ready;
  final VoidCallback? onConfirm;
  final Widget? wheel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panel = theme.scaffoldBackgroundColor;
    final titleColor = theme.colorScheme.onSurface;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);
    // No second BackdropFilter here — the full-screen blur already frosts
    // the hub; another filter on open is what made the modal feel delayed.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.orange.withValues(
                alpha: isDark ? 0.55 : 0.35,
              ),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.orange.withValues(
                  alpha: isDark ? 0.18 : 0.12,
                ),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 140,
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
                            panel.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _WheelBand(
                          ready: ready,
                          wheel: wheel,
                          height: _hubWheelHeight
                              .clamp(
                                120.0,
                                MediaQuery.sizeOf(context).height * 0.45,
                              )
                              .toDouble(),
                          itemExtent: _hubItemExtent,
                          selectionHighlight: highlight,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.orange,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: onConfirm,
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _WheelBand extends StatelessWidget {
  const _WheelBand({
    required this.ready,
    required this.wheel,
    required this.height,
    required this.itemExtent,
    this.selectionHighlight,
  });

  final bool ready;
  final Widget? wheel;
  final double height;
  final double itemExtent;
  final Color? selectionHighlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.brightness == Brightness.dark
        ? const Color(0x66FFFFFF)
        : const Color(0x66000000);

    if (!ready || wheel == null) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          wheel!,
          IgnorePointer(
            child: SizedBox(
              height: itemExtent,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selectionHighlight,
                  border: Border(
                    top: BorderSide(color: line),
                    bottom: BorderSide(color: line),
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

class _PickerWheel extends StatelessWidget {
  const _PickerWheel({
    required this.controller,
    required this.childCount,
    required this.onSelected,
    required this.labelBuilder,
    required this.selectedIndex,
    this.alignStart = false,
    this.itemExtent = _pickerItemExtent,
    this.selectedFontSize = 16,
    this.unselectedFontSize = 15,
    this.selectedColor,
    this.unselectedColor,
  });

  final FixedExtentScrollController controller;
  final int childCount;
  final ValueChanged<int> onSelected;
  final String Function(int index) labelBuilder;
  final int selectedIndex;
  final bool alignStart;
  final double itemExtent;
  final double selectedFontSize;
  final double unselectedFontSize;
  final Color? selectedColor;
  final Color? unselectedColor;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final selectedFg = selectedColor ?? onSurface;
    final unselectedFg = unselectedColor ?? const Color(0xFFB0B0B0);

    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: itemExtent,
      diameterRatio: 2.2,
      perspective: 0.002,
      overAndUnderCenterOpacity: 0.55,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: childCount,
        builder: (context, index) {
          final selected = index == selectedIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  fontSize: selected ? selectedFontSize : unselectedFontSize,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? selectedFg : unselectedFg,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
