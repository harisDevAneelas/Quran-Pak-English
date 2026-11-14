import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../data/quran_metadata.dart';

const _pickerBar = Color(0xFF3A3A3A);
const _pickerItemExtent = 36.0;
const _pickerWheelHeight = 200.0;


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
