import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/text_scale.dart';
import '../../practice/providers/practice_provider.dart';
import '../domain/models/streak.dart';
import '../providers/stats_provider.dart';
import 'widgets/streak_calendar.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(statsOverviewProvider);
    final historyAsync = ref.watch(solveHistoryProvider);
    final practiceStats = ref.watch(practiceStatsNotifierProvider);

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.purpleLight,
        backgroundColor: AppColors.cardSurface,
        onRefresh: () async {
          ref.invalidate(statsOverviewProvider);
          ref.invalidate(solveHistoryProvider);
          await Future.wait([
            ref.read(statsOverviewProvider.future),
            ref.read(solveHistoryProvider.future),
          ]);
        },
        child: ListView(
          // Always scrollable so pull-to-refresh works on short content such
          // as the error state.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.all(AppSizes.lg),
          children: [
            Text(
              'Statistics',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: AppSizes.lg),
            // Stat cards use the always-dark card surface; pin their text to
            // the dark text theme so they stay legible in the light theme.
            Theme(
              data: Theme.of(
                context,
              ).copyWith(textTheme: AppTheme.darkTheme.textTheme),
              child: Builder(
                builder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildOverviewSection(context, ref, overviewAsync),
                    const SizedBox(height: AppSizes.sm),
                    _PracticeStatsCard(stats: practiceStats),
                    const SizedBox(height: AppSizes.lg),
                    _buildCalendarSection(
                      context,
                      overviewAsync,
                      historyAsync,
                      ref,
                    ),
                    const SizedBox(height: AppSizes.lg),
                    _buildTimeDistribution(context, historyAsync),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSizes.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<StatsOverview> overviewAsync,
  ) {
    return switch (overviewAsync) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (value.fromCache) ...[
            const _SavedStatsNote(),
            const SizedBox(height: AppSizes.sm),
          ],
          _StatsOverviewCards(overview: value),
        ],
      ),
      AsyncError() => _ErrorCard(
        onRetry: () {
          ref.invalidate(statsOverviewProvider);
          ref.invalidate(solveHistoryProvider);
        },
      ),
      _ => const _LoadingCards(),
    };
  }

  Widget _buildCalendarSection(
    BuildContext context,
    AsyncValue<StatsOverview> overviewAsync,
    AsyncValue<List<SolveHistory>> historyAsync,
    WidgetRef ref,
  ) {
    final currentStreak = switch (overviewAsync) {
      AsyncData(:final value) => value.currentStreak,
      _ => 0,
    };

    return switch (historyAsync) {
      AsyncData(:final value) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: AppColors.cellBorder.withValues(alpha: 0.3),
          ),
        ),
        padding: const EdgeInsetsDirectional.all(AppSizes.md),
        child: StreakCalendar(
          solveHistory: value,
          currentStreak: currentStreak,
        ),
      ),
      // The overview card already shows the error + retry.
      AsyncError() when overviewAsync.hasError => const SizedBox.shrink(),
      AsyncError() => _ErrorCard(
        onRetry: () => ref.invalidate(solveHistoryProvider),
      ),
      _ => Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        padding: const EdgeInsetsDirectional.all(AppSizes.md),
        child: const SizedBox(
          height: 200,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.purpleLight),
          ),
        ),
      ),
    };
  }

  Widget _buildTimeDistribution(
    BuildContext context,
    AsyncValue<List<SolveHistory>> historyAsync,
  ) {
    return switch (historyAsync) {
      AsyncData(:final value) => _SolveTimeDistribution(history: value),
      AsyncError() => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }
}

class _StatsOverviewCards extends StatelessWidget {
  const _StatsOverviewCards({required this.overview});

  final StatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final freezeStatus = _freezeStatusText(overview);

    return Column(
      children: [
        _StreakHero(
          currentStreak: overview.currentStreak,
          longestStreak: overview.longestStreak,
        ),
        const SizedBox(height: AppSizes.sm),
        _PairOf(
          stack: isLargeText(context),
          first: _StatCard(
            label: 'Puzzles Solved',
            value: '${overview.totalSolved}',
            icon: Icons.check_circle_rounded,
            gradientColors: const [AppColors.success, AppColors.successDim],
          ),
          second: _StatCard(
            label: 'Average Time',
            value: overview.averageTimeSeconds > 0
                ? AppDateUtils.formatTime(overview.averageTimeSeconds)
                : '--:--',
            icon: Icons.timer_rounded,
            gradientColors: const [
              AppColors.purpleLight,
              AppColors.purpleDeep,
            ],
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        _StatCard(
          label: 'Streak Freeze',
          value: freezeStatus,
          icon: Icons.ac_unit_rounded,
          gradientColors: const [
            AppColors.electricBlue,
            AppColors.electricBlueDim,
          ],
        ),
      ],
    );
  }

  String _freezeStatusText(StatsOverview overview) {
    if (overview.freezeCount > 0) {
      final n = overview.freezeCount;
      return '$n freeze${n == 1 ? '' : 's'} available this week';
    }
    if (overview.lastFreezeUsedAt != null) return 'Used this week';
    return 'None left this week';
  }
}

/// Two cards side by side, or one above the other when [stack] (large text
/// leaves each card too little width).
class _PairOf extends StatelessWidget {
  const _PairOf({
    required this.stack,
    required this.first,
    required this.second,
  });

  final bool stack;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: AppSizes.sm), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: second),
      ],
    );
  }
}

/// A number that shrinks to fit rather than overflowing or breaking.
class _FitNumber extends StatelessWidget {
  const _FitNumber({required this.text, required this.style, this.alignment});

  final String text;
  final TextStyle? style;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment ?? Alignment.center,
      child: Text(text, maxLines: 1, style: style),
    );
  }
}

/// Local practice statistics (never synced).
class _PracticeStatsCard extends StatelessWidget {
  const _PracticeStatsCard({required this.stats});

  final PracticeStats stats;

  @override
  Widget build(BuildContext context) {
    final best = [
      for (final size in practiceSizes)
        if (stats.bestBySize[size] != null)
          '${size}x$size ${AppDateUtils.formatTime(stats.bestBySize[size]!)}',
    ];
    return _StatCard(
      label: 'Practice',
      value: stats.count == 0
          ? 'No practice yet'
          : '${stats.count} solved'
                '${best.isEmpty ? '' : ' · best ${best.join(', ')}'}',
      icon: Icons.fitness_center_rounded,
      gradientColors: const [AppColors.pathAmber, AppColors.pathOrangeDeep],
    );
  }
}

class _StreakHero extends StatelessWidget {
  const _StreakHero({required this.currentStreak, required this.longestStreak});

  final int currentStreak;
  final int longestStreak;

  @override
  Widget build(BuildContext context) {
    final stack = isLargeText(context);
    final current = _HeroStat(
      value: currentStreak,
      label: 'Current Streak',
      icon: Icons.local_fire_department_rounded,
      color: AppColors.pathOrange,
      deepColor: AppColors.pathOrangeDeep,
    );
    final longest = _HeroStat(
      value: longestStreak,
      label: 'Longest Streak',
      icon: Icons.emoji_events_rounded,
      color: AppColors.streakGold,
      deepColor: AppColors.streakGold,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      // Side by side normally; stacked at large text so each keeps its width.
      child: stack
          ? Column(
              children: [
                current,
                const SizedBox(height: AppSizes.sm),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: AppColors.cellBorder,
                ),
                const SizedBox(height: AppSizes.sm),
                longest,
              ],
            )
          : Row(
              children: [
                Expanded(child: current),
                Container(width: 1, height: 80, color: AppColors.cellBorder),
                Expanded(child: longest),
              ],
            ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.deepColor,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color color;
  final Color deepColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.25),
                deepColor.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
          child: Icon(icon, color: color, size: 36),
        ),
        const SizedBox(height: AppSizes.sm),
        _FitNumber(
          text: '$value',
          style: theme.textTheme.displayLarge?.copyWith(
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradientColors,
  });

  final String label;
  final String value;
  final IconData icon;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradientColors.first.withValues(alpha: 0.2),
                  gradientColors.last.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(icon, color: gradientColors.first),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                if (value.length > 12)
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  )
                else
                  _FitNumber(
                    text: value,
                    alignment: AlignmentDirectional.centerStart,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFeatures: [const FontFeature.tabularFigures()],
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

class _LoadingCards extends StatelessWidget {
  const _LoadingCards();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 300,
      child: Center(
        child: CircularProgressIndicator(color: AppColors.purpleLight),
      ),
    );
  }
}

class _SavedStatsNote extends StatelessWidget {
  const _SavedStatsNote();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.statsShowingSaved,
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 16,
              color: AppColors.textSecondaryDark,
            ),
            const SizedBox(width: AppSizes.xs),
            Flexible(
              child: Text(
                AppStrings.statsShowingSaved,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  AppStrings.statsLoadFailed,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: onRetry,
              child: const Text(AppStrings.retry),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolveTimeDistribution extends StatelessWidget {
  const _SolveTimeDistribution({required this.history});

  final List<SolveHistory> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = history.where((h) => h.completed).toList();
    if (completed.isEmpty) return const SizedBox.shrink();

    final buckets = <String, int>{
      '<1m': 0,
      '1-2m': 0,
      '2-3m': 0,
      '3-5m': 0,
      '5m+': 0,
    };

    for (final solve in completed) {
      final seconds = solve.timeSeconds;
      if (seconds < 60) {
        buckets['<1m'] = buckets['<1m']! + 1;
      } else if (seconds < 120) {
        buckets['1-2m'] = buckets['1-2m']! + 1;
      } else if (seconds < 180) {
        buckets['2-3m'] = buckets['2-3m']! + 1;
      } else if (seconds < 300) {
        buckets['3-5m'] = buckets['3-5m']! + 1;
      } else {
        buckets['5m+'] = buckets['5m+']! + 1;
      }
    }

    final maxCount = buckets.values.fold(0, max);
    if (maxCount == 0) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Solve Time Distribution', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          ...buckets.entries.map((entry) {
            final ratio = entry.value / maxCount;
            return Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSizes.sm),
              child: _DistributionBar(
                label: entry.key,
                count: entry.value,
                ratio: ratio,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.label,
    required this.count,
    required this.ratio,
  });

  final String label;
  final int count;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth * ratio;
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: barWidth.clamp(4.0, constraints.maxWidth),
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.purpleGradientStart.withValues(
                          alpha: 0.3 + (ratio * 0.7),
                        ),
                        AppColors.purpleGradientEnd.withValues(
                          alpha: 0.3 + (ratio * 0.7),
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        SizedBox(
          width: 24,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
