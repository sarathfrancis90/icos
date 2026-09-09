import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/spring_button.dart';
import '../../puzzle/data/submission_result.dart';
import '../../puzzle/providers/daily_puzzle_provider.dart';
import '../../puzzle/providers/puzzle_result_provider.dart';
import '../../stats/providers/stats_provider.dart';
import 'widgets/home_share.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzleAsync = ref.watch(dailyPuzzleProvider);
    final resultAsync = ref.watch(todayResultProvider);
    final streakAsync = ref.watch(streakProvider);
    final today = AppDateUtils.todayUtc();

    // Unsolved on load → remind before midnight UTC (cancelled on solve).
    ref.listen(todayResultProvider, (prev, next) {
      if (next is AsyncData<SubmissionResult?> && next.value == null) {
        final streak = ref.read(streakProvider).valueOrNull?.currentStreak ?? 0;
        unawaited(
          NotificationService.scheduleStreakReminder(
            currentStreak: streak,
          ).catchError((Object _) {}),
        );
      }
    });

    final result = resultAsync.valueOrNull;
    final streak =
        result?.streak?.currentStreak ?? streakAsync.valueOrNull?.currentStreak;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App title with gradient accent
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.purpleLight, AppColors.pathYellowBright],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                AppStrings.appName,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Colors.white, // masked by shader
                ),
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Row(
              children: [
                Text(
                  AppStrings.appTagline,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
                ),
                const Spacer(),
                if (streak != null && streak > 0) _StreakBadge(streak: streak),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  puzzleAsync.when(
                    data: (puzzle) => _PuzzleCard(
                      date: today,
                      gridSize: puzzle.gridSize,
                      difficulty: puzzle.difficulty,
                      parTime: puzzle.parTimeSeconds,
                      result: result,
                      resultLoading: resultAsync.isLoading,
                      onPlay: () => context.push('/puzzle/$today'),
                      onView: () => context.push('/puzzle/$today'),
                      onShare: result == null
                          ? null
                          : () => shareResultFromHome(
                              context,
                              result: result,
                              gridSize: puzzle.gridSize,
                              difficulty: puzzle.difficulty,
                              parTimeSeconds: puzzle.parTimeSeconds,
                              walls: [
                                for (final w in puzzle.walls) [w.row, w.col],
                              ],
                              streak: streak,
                            ),
                    ),
                    loading: () => const _PuzzleCardSkeleton(),
                    error: (error, _) => _PuzzleCard(
                      date: today,
                      gridSize: 5,
                      difficulty: 'easy',
                      parTime: 60,
                      result: result,
                      resultLoading: false,
                      onPlay: () => context.push('/puzzle/$today'),
                      onView: () => context.push('/puzzle/$today'),
                      onShare: result == null
                          ? null
                          : () => shareResultFromHome(
                              context,
                              result: result,
                              gridSize: 5,
                              difficulty: 'easy',
                              parTimeSeconds: 60,
                              walls: const [],
                              streak: streak,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.contentMaxWidth,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _EntryCard(
                              key: const Key('home-practice'),
                              icon: Icons.fitness_center_rounded,
                              title: 'Practice',
                              subtitle: 'Unlimited puzzles',
                              onTap: () => context.push('/practice'),
                            ),
                          ),
                          const SizedBox(width: AppSizes.sm),
                          Expanded(
                            child: _EntryCard(
                              key: const Key('home-archive'),
                              icon: Icons.history_rounded,
                              title: 'Archive',
                              subtitle: 'Last 30 days',
                              onTap: () => context.push('/archive'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$streak day streak',
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSizes.sm + 4,
          vertical: AppSizes.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.streakGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          border: Border.all(
            color: AppColors.streakGold.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              size: 16,
              color: AppColors.streakGold,
            ),
            const SizedBox(width: 4),
            Text(
              '$streak',
              style: const TextStyle(
                color: AppColors.streakGold,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({
    required this.date,
    required this.gridSize,
    required this.difficulty,
    required this.parTime,
    required this.result,
    required this.resultLoading,
    required this.onPlay,
    required this.onView,
    required this.onShare,
  });

  final String date;
  final int gridSize;
  final String difficulty;
  final int parTime;
  final SubmissionResult? result;
  final bool resultLoading;
  final VoidCallback onPlay;
  final VoidCallback onView;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final solved = result != null;

    // The card surface is always dark, so pin its text to the dark text theme
    // regardless of the ambient (possibly light) theme.
    return Theme(
      data: Theme.of(context).copyWith(textTheme: AppTheme.darkTheme.textTheme),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.cardSurface,
                  AppColors.elevatedSurface.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              border: Border.all(
                color: solved
                    ? AppColors.success.withValues(alpha: 0.5)
                    : AppColors.cellBorder.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purpleGlow.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSizes.lg + 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Grid icon with glow
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: solved
                            ? const [AppColors.success, AppColors.successDim]
                            : const [
                                AppColors.pathAmber,
                                AppColors.pathOrangeDeep,
                              ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: solved
                              ? AppColors.success.withValues(alpha: 0.4)
                              : AppColors.pathGlowOrange,
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      solved ? Icons.check_rounded : Icons.grid_4x4_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md + 4),

                  Text(
                    AppStrings.puzzleTitle,
                    // Card surface is always dark; use the dark text style.
                    style: AppTheme.darkTheme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSizes.sm),

                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _InfoTag(
                        icon: Icons.grid_view_rounded,
                        label: '${gridSize}x$gridSize',
                      ),
                      const SizedBox(width: AppSizes.sm),
                      _InfoTag(
                        icon: Icons.speed_rounded,
                        label:
                            difficulty[0].toUpperCase() +
                            difficulty.substring(1),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      _InfoTag(
                        icon: Icons.timer_outlined,
                        label: AppDateUtils.formatTimeHuman(parTime),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.lg + 4),

                  if (solved)
                    _SolvedSummary(result: result!)
                  else if (resultLoading)
                    const _PuzzleActionSkeleton(),

                  if (solved) ...[
                    const SizedBox(height: AppSizes.md),
                    Row(
                      children: [
                        Expanded(
                          child: _OutlinedAction(
                            key: const Key('home-view'),
                            label: 'View',
                            icon: Icons.visibility_rounded,
                            onPressed: onView,
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: _GradientAction(
                            key: const Key('home-share'),
                            label: 'Share',
                            icon: Icons.share_rounded,
                            onPressed: onShare ?? () {},
                          ),
                        ),
                      ],
                    ),
                  ] else if (!resultLoading)
                    _GradientAction(
                      key: const Key('home-play'),
                      label: 'Play',
                      onPressed: onPlay,
                      height: 56,
                      fontSize: 18,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Solved in mm:ss · N hints · #rank today" line.
class _SolvedSummary extends StatelessWidget {
  const _SolvedSummary({required this.result});

  final SubmissionResult result;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      'Solved in ${AppDateUtils.formatTime(result.timeSeconds)}',
      '${result.hintsUsed} hint${result.hintsUsed == 1 ? '' : 's'}',
      if (result.rankHint != null) '#${result.rankHint} today',
    ];
    final note = switch (result.status) {
      SubmissionStatus.rejected => 'Not counted — could not be verified',
      SubmissionStatus.pending => 'Saving result…',
      SubmissionStatus.localOnly => 'Saved on this device',
      _ => null,
    };

    return Column(
      children: [
        Text(
          parts.join(' · '),
          key: const Key('home-solved-summary'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.success,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: AppSizes.xs),
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: result.isRejected
                  ? AppColors.warning
                  : AppColors.textSecondaryDark,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _GradientAction extends StatelessWidget {
  const _GradientAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.fontSize = 16,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SpringButton(
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          gradient: AppColors.purpleButtonGradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: const [
            BoxShadow(
              color: AppColors.purpleGlow,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: AppSizes.sm),
            ],
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SpringButton(
      onPressed: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: AppColors.textSecondaryDark.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textPrimaryDark, size: 20),
            const SizedBox(width: AppSizes.sm),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimaryDark,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: SpringButton(
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: AppColors.cellBorder.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.purpleLight, size: 26),
              const SizedBox(width: AppSizes.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondaryDark,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.sm + 4,
        vertical: AppSizes.xs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondaryDark),
          const SizedBox(width: AppSizes.xs),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleActionSkeleton extends StatelessWidget {
  const _PuzzleActionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.cellBackground,
        borderRadius: BorderRadius.circular(28),
      ),
    );
  }
}

class _PuzzleCardSkeleton extends StatelessWidget {
  const _PuzzleCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(
              color: AppColors.cellBorder.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.cellBackground,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Container(
                  width: 160,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.cellBackground,
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                const _PuzzleActionSkeleton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
