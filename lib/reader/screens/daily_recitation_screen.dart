import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/app_dimens.dart';
import '../daily_plan.dart';
import '../profile_manager.dart';
import '../widgets/reader_page_scaffold.dart';
import 'daily_plan_setup_screen.dart';

/// Plan-type picker for daily Quran reading / listening.
class DailyRecitationScreen extends StatelessWidget {
  const DailyRecitationScreen({
    super.key,
    required this.dailyPlanStore,
    required this.profiles,
    this.initialEditProfileId,
  });

  final DailyPlanStore dailyPlanStore;
  final ProfileManager profiles;
  final String? initialEditProfileId;

  static const _options = <_DailyOption>[
    _DailyOption(
      kind: DailyPlanKind.ruku,
      title: 'Ruku',
      subtitle: 'One, two, three, ...',
    ),
    _DailyOption(
      kind: DailyPlanKind.ayah,
      title: 'Ayahs',
      subtitle: 'Five, ten, fifteen, ...',
    ),
    _DailyOption(
      kind: DailyPlanKind.para,
      title: 'Paras',
      subtitle: 'A quarter, half a para, three quarters, one para...',
    ),
    _DailyOption(
      kind: DailyPlanKind.page,
      title: 'Pages',
      subtitle: 'One, two, three, ...',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = AppDimens.scaleOf(context);
    final editProfileId = initialEditProfileId ??
        profiles.activeProfileId ??
        dailyPlanStore.profileId;

    return ReaderPageScaffold(
      title: 'Daily recitation plan',
      showPlayingAyahBar: false,
      body: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppDimens.dailyGap;
              const pad = EdgeInsets.fromLTRB(
                AppDimens.dailyPadH,
                AppDimens.dailyPadTop,
                AppDimens.dailyPadH,
                AppDimens.dailyPadBottom,
              );
              const cellMin = AppDimens.dailyCellMin;
              const chrome = AppDimens.dailyChrome;
              final fits =
                  constraints.maxHeight >= chrome + cellMin * 2 + gap + 80;
              final cellW = AppDimens.dailyCellWidthOf(constraints.maxWidth);

              final header = Column(
                children: [
                  Text(
                    'How do you want to read or listen each day?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: AppDimens.fontDailyQuestion * scale,
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pick one',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: AppDimens.fontDailyHint * scale,
                      height: 1.5,
                    ),
                  ),
                ],
              );

              final footer = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'You can change the plan at any time',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                        fontSize: AppDimens.fontDailyFooter * scale,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: Colors.amber.shade700,
                  ),
                ],
              );

              Widget grid(double cellH) {
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final option in _options)
                      SizedBox(
                        width: cellW,
                        height: cellH,
                        child: _OptionCard(
                          option: option,
                          dailyPlanStore: dailyPlanStore,
                          profiles: profiles,
                          editProfileId: editProfileId,
                        ),
                      ),
                  ],
                );
              }

              if (fits) {
                return Padding(
                  padding: pad,
                  child: Column(
                    children: [
                      header,
                      const SizedBox(height: 28),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, inner) {
                            final cellH = ((inner.maxHeight - gap) / 2)
                                .clamp(cellMin, 200.0);
                            return Align(
                              alignment: Alignment.topCenter,
                              child: grid(cellH),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      footer,
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: pad,
                child: Column(
                  children: [
                    header,
                    const SizedBox(height: 28),
                    grid(cellMin),
                    const SizedBox(height: 12),
                    footer,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DailyOption {
  const _DailyOption({
    required this.kind,
    required this.title,
    required this.subtitle,
  });

  final DailyPlanKind kind;
  final String title;
  final String subtitle;
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.dailyPlanStore,
    required this.profiles,
    required this.editProfileId,
  });

  final _DailyOption option;
  final DailyPlanStore dailyPlanStore;
  final ProfileManager profiles;
  final String editProfileId;

  static const _cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppTheme.orangeLight, AppTheme.orange, AppTheme.orangeDeep],
  );

  @override
  Widget build(BuildContext context) {
    final titleSize = AppDimens.scaled(context, AppDimens.fontDailyCardTitle);
    final subtitleSize =
        AppDimens.scaled(context, AppDimens.fontDailyCardSubtitle);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DailyPlanSetupScreen(
                kind: option.kind,
                dailyPlanStore: dailyPlanStore,
                profiles: profiles,
                editProfileId: editProfileId,
              ),
            ),
          );
        },
        child: Ink(
          decoration: const BoxDecoration(gradient: _cardGradient),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ScreenFitText(
                    option.title,
                    maxLines: 1,
                    minFontSize: AppDimens.fontDailyCardTitleMin,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ScreenFitText(
                    option.subtitle,
                    maxLines: 2,
                    minFontSize: AppDimens.fontDailyCardSubtitleMin,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: subtitleSize,
                      height: 1.4,
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
