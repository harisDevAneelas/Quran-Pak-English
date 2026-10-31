import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/azaan_catalog.dart';
import '../widgets/option_preview_player.dart';
import '../widgets/orange_app_bar.dart';
import '../widgets/reader_page_scaffold.dart';

/// Azaan voice picker with per-row preview. Pops with the chosen id.
class AzaanListScreen extends StatefulWidget {
  const AzaanListScreen({
    super.key,
    required this.selectedId,
  });

  final String selectedId;

  @override
  State<AzaanListScreen> createState() => _AzaanListScreenState();
}

class _AzaanListScreenState extends State<AzaanListScreen> {
  late final OptionPreviewPlayer _preview;
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = AzaanCatalog.resolveId(widget.selectedId);
    _preview = OptionPreviewPlayer()..addListener(_onPreview);
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _preview.removeListener(_onPreview);
    _preview.dispose();
    super.dispose();
  }

  void _select(String id) {
    setState(() => _selectedId = id);
  }

  void _done() {
    Navigator.of(context).pop(_selectedId);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_selectedId);
      },
      child: ReaderPageScaffold(
        title: 'Choose azaan',
        showDrawer: false,
        leadingWidth: 88,
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: Center(
            child: GoldDoneButton(
              onPressed: _done,
              label: 'Save',
            ),
          ),
        ),
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: ListView.separated(
            itemCount: AzaanCatalog.all.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = AzaanCatalog.all[index];
              final isSelected = option.id == _selectedId;
              final playing = _preview.isPlaying(option.id);
              return Material(
                color: isSelected
                    ? AppTheme.orange.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _select(option.id),
                  child: SizedBox(
                    height: 72,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _select(option.id),
                              activeColor: AppTheme.orange,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              option.name,
                              textAlign: TextAlign.left,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          IconButton(
                            tooltip: playing ? 'Stop preview' : 'Preview',
                            iconSize: 40,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: () => _preview.toggleAsset(
                              option.id,
                              option.assetPath,
                            ),
                            icon: Icon(
                              playing
                                  ? Icons.stop_circle_rounded
                                  : Icons.play_circle_filled_rounded,
                              color: AppTheme.orange,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ),
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
