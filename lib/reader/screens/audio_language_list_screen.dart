import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/audio_language_catalog.dart';
import '../widgets/option_preview_player.dart';
import '../widgets/orange_app_bar.dart';
import '../widgets/reader_page_scaffold.dart';

class AudioLanguageListScreen extends StatefulWidget {
  const AudioLanguageListScreen({
    super.key,
    required this.selectedLabel,
  });

  final String selectedLabel;

  @override
  State<AudioLanguageListScreen> createState() =>
      _AudioLanguageListScreenState();
}

class _AudioLanguageListScreenState extends State<AudioLanguageListScreen> {
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

  void _done() {
    Navigator.of(context).pop(_selectedLabel);
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
        title: 'Spoken translation',
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
            itemCount: AudioLanguageCatalog.all.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final language = AudioLanguageCatalog.all[index];
              final isSelected = language.name == _selectedLabel;
              final playing = _preview.isPlaying(language.id);
              return Material(
                color: isSelected
                    ? AppTheme.orange.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _select(language.name),
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
                              onChanged: (_) => _select(language.name),
                              activeColor: AppTheme.orange,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _FlagAvatar(assetPath: language.imageAsset),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              language.name,
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
                              language.id,
                              AudioLanguageCatalog.previewUrl(language.id),
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

class _FlagAvatar extends StatelessWidget {
  const _FlagAvatar({required this.assetPath});

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
            AudioLanguageCatalog.dummyImageAsset,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
