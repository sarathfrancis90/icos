import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/models/streak.dart';
import '../providers/stats_provider.dart';
import 'widgets/streak_calendar.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(statsOverviewProvider);
    final historyAsync = ref.watch(solveHistoryProvider);

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
          padding: const EdgeInsetsDirectional.all(AppSizes.lg),
          children: [
            Text(
              'Statistics',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: AppSizes.lg),
            _buildOverviewSection(context, overviewAsync),
            const SizedBox(height: AppSizes.lg),
            _buildCalendarSection(context, overviewAsync, historyAsync),
            const SizedBox(height: AppSizes.lg),
            _buildTimeDistribution(context, historyAsync),
            const SizedBox(height: AppSizes.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(
    BuildContext context,
    AsyncValue<StatsOverview> overviewAsync,
  ) {
    return switch (overviewAsync) {
      AsyncData(:final value) => _StatsOverviewCards(overview: value),
      AsyncError(:final error) => _ErrorCard(message: error.toString()),
      _ => const _LoadingCards(),
    };
  }

  Widget _buildCalendarSection(
    BuildContext context,
    AsyncValue<StatsOverview> overviewAsync,
    AsyncValue<List<SolveHistory>> historyAsync,
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
      AsyncError(:final error) => _ErrorCard(message: error.toString()),
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
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Puzzles Solved',
                value: '${overview.totalSolved}',
                icon: Icons.check_circle_rounded,
                gradientColors: [AppColors.success, AppColors.successDim],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: _StatCard(
                label: 'Average Time',
                value: overview.averageTimeSeconds > 0
                    ? AppDateUtils.formatTime(overview.averageTimeSeconds)
                    : '--:--',
                icon: Icons.timer_rounded,
                gradientColors: [AppColors.purpleLight, AppColors.purpleDeep],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        _StatCard(
          label: 'Streak Freeze',
          value: freezeStatus,
          icon: Icons.ac_unit_rounded,
          gradientColors: [AppColors.electricBlue, AppColors.electricBlueDim],
        ),
      ],
    );
  }

  String _freezeStatusText(StatsOverview overview) {
    if (overview.freezeCount > 0) return '${overview.freezeCount} available';
    if (overview.lastFreezeUsedAt != null) return 'Used this week';
    return '0 available';
  }
}

class _StreakHero extends StatelessWidget {
  const _StreakHero({
    required this.currentStreak,
    required this.longestStreak,
  });

  final int currentStreak;
  final int longestStreak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: AppColors.cellBorder.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        AppColors.pathOrange.withValues(alpha: 0.25),
                        AppColors.pathOrangeDeep.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    color: AppColors.pathOrange,
                    size: 36,
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  '$currentStreak',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
                Text('Current Streak', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 80,
            color: AppColors.cellBorder,
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        AppColors.streakGold.withValues(alpha: 0.25),
                        AppColors.streakGold.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: AppColors.streakGold,
                    size: 36,
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  '$longestStreak',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
                Text('Longest Streak', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
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
        border: Border.all(
          color: AppColors.cellBorder.withValues(alpha: 0.3),
        ),
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
                Text(
                  value,
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              'Failed to load stats. Pull down to retry.',
              style: Theme.of(context).textTheme.bodyMedium,
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
          Text(
            'Solve Time Distribution',
            style: theme.textTheme.titleMedium,
          ),
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
