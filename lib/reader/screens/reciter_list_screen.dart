import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/reciter_catalog.dart';
import '../widgets/option_preview_player.dart';
import '../widgets/reader_page_scaffold.dart';

/// Reciter picker with portrait thumbnails. Pops with the chosen English name.
class ReciterListScreen extends StatefulWidget {
  const ReciterListScreen({
    super.key,
    required this.selectedLabel,
  });

  final String selectedLabel;

  @override
  State<ReciterListScreen> createState() => _ReciterListScreenState();
}

class _ReciterListScreenState extends State<ReciterListScreen> {
  late final OptionPreviewPlayer _preview;
  late String _selectedLabel;

  @override
  void initState() {
    super.initState();
    _selectedLabel = widget.selectedLabel;
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

  void _select(String name) {
    setState(() => _selectedLabel = name);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_selectedLabel);
      },
      child: ReaderPageScaffold(
        title: 'Choose a reciter',
        body: Directionality(
          textDirection: TextDirection.ltr,
          child: ListView.separated(
            itemCount: ReciterCatalog.all.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final reciter = ReciterCatalog.all[index];
              final isSelected = reciter.name == _selectedLabel;
              final playing = _preview.isPlaying(reciter.id);
              return Material(
                color: isSelected
                    ? AppTheme.orange.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _select(reciter.name),
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
                              onChanged: (_) => _select(reciter.name),
                              activeColor: AppTheme.orange,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _ReciterAvatar(assetPath: reciter.imageAsset),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              reciter.name,
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
                            onPressed: () => _preview.toggleUrl(
                              reciter.id,
                              ReciterCatalog.previewUrl(reciter.id),
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

class _ReciterAvatar extends StatelessWidget {
  const _ReciterAvatar({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Image.asset(
            ReciterCatalog.dummyImageAsset,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
