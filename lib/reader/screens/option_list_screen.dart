import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/translation_catalog.dart';
import '../widgets/reader_page_scaffold.dart';

class TranslationMultiSelectScreen extends StatefulWidget {
  const TranslationMultiSelectScreen({
    super.key,
    required this.selectedIds,
  });

  final List<String> selectedIds;

  @override
  State<TranslationMultiSelectScreen> createState() =>
      _TranslationMultiSelectScreenState();
}

class _TranslationMultiSelectScreenState
    extends State<TranslationMultiSelectScreen> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = TranslationCatalog.resolveIds(widget.selectedIds).toSet();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  List<String> _orderedSelection() => [
        for (final option in TranslationCatalog.all)
          if (_selected.contains(option.id)) option.id,
      ];

  void _done() {
    Navigator.of(context).pop(_orderedSelection());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _done();
      },
      child: ReaderPageScaffold(
        title: 'Choose translations',
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  _selected.isEmpty
                      ? 'No translation selected. You can pick one or more.'
                      : '${_selected.length} translations selected',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: TranslationCatalog.all.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final option = TranslationCatalog.all[index];
                    final isSelected = _selected.contains(option.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (_) => _toggle(option.id),
                      activeColor: AppTheme.orange,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        option.label,
                        textAlign: TextAlign.left,
                        style: const TextStyle(fontSize: 16),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
