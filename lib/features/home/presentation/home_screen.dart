import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/date_utils.dart';
import '../../puzzle/providers/daily_puzzle_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzleAsync = ref.watch(dailyPuzzleProvider);
    final today = AppDateUtils.todayUtc();

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
            Text(
              AppStrings.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: AppSizes.xl),
            Expanded(
              child: puzzleAsync.when(
                data: (puzzle) => _PuzzleCard(
                  date: today,
                  gridSize: puzzle.gridSize,
                  difficulty: puzzle.difficulty,
                  parTime: puzzle.parTimeSeconds,
                  onPlay: () => context.push('/puzzle/$today'),
                ),
                loading: () => const _PuzzleCardSkeleton(),
                error: (error, _) => _PuzzleCard(
                  date: today,
                  gridSize: 5,
                  difficulty: 'easy',
                  parTime: 60,
                  onPlay: () => context.push('/puzzle/$today'),
                ),
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
    required this.onPlay,
  });

  final String date;
  final int gridSize;
  final String difficulty;
  final int parTime;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Center(
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
              color: AppColors.cellBorder.withValues(alpha: 0.4),
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
                    gradient: const RadialGradient(
                      colors: [
                        AppColors.pathAmber,
                        AppColors.pathOrangeDeep,
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.pathGlowOrange,
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.grid_4x4_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSizes.md + 4),

                Text(
                  AppStrings.puzzleTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
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
                      label: difficulty[0].toUpperCase() +
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

                // Play button with gradient
                GestureDetector(
                  onTap: onPlay,
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.purpleButtonGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purpleGlow,
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Play',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
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
        border: Border.all(
          color: AppColors.cellBorder.withValues(alpha: 0.3),
        ),
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
            border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
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
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.cellBackground,
                    borderRadius: BorderRadius.circular(28),
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
