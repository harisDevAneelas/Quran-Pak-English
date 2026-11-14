import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/mushaf_script.dart';
import '../../core/quran_font.dart';
import '../reader_settings.dart';
import '../widgets/orange_app_bar.dart';
import '../widgets/reader_page_scaffold.dart';

/// Full-screen IndoPak vs Uthmani comparison using Ayat-e-Noor (24:35).
///
/// Short Bismillah previews look nearly identical; this ayah shows different
/// orthography and faces side by side.
class MushafScriptPickerScreen extends StatefulWidget {
  const MushafScriptPickerScreen({
    super.key,
    required this.settings,
    this.apply,
  });

  final ReaderSettings settings;

  final Future<void> Function(MushafScript script)? apply;

  @override
  State<MushafScriptPickerScreen> createState() =>
      _MushafScriptPickerScreenState();
}

class _MushafScriptPickerScreenState extends State<MushafScriptPickerScreen> {
  late MushafScript _selected;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.settings.mushafScript;
  }

  void _select(MushafScript script) {
    if (_applying) return;
    setState(() => _selected = script);
  }

  Future<void> _applySelection() async {
    final apply = widget.apply;
    if (apply != null) {
      await apply(_selected);
    } else {
      widget.settings.setMushafScript(_selected);
    }
  }

  Future<void> _saveAndPop() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      await _applySelection();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _doneToMushaf() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      await _applySelection();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _saveAndPop();
      },
      child: ReaderPageScaffold(
        title: 'Mushaf script',
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  for (final script in MushafScript.pickerOrder) ...[
                    _ScriptChoiceCard(
                      script: script,
                      selected: _selected == script,
                      onTap: () => _select(script),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: GoldDoneButton(
                      onPressed: _applying ? () {} : _doneToMushaf,
                      wide: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              if (_applying)
                ColoredBox(
                  color: theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptChoiceCard extends StatelessWidget {
  const _ScriptChoiceCard({
    required this.script,
    required this.selected,
    required this.onTap,
  });

  final MushafScript script;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        selected ? AppTheme.orange : theme.colorScheme.outlineVariant;

    return Material(
      color: selected
          ? AppTheme.orange.withValues(alpha: 0.08)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: AppTheme.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      script.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                script.comparisonSample,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: QuranFont.baseFor(script).copyWith(
                  fontSize: 30,
                  height: QuranFont.recommendedLineHeight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
