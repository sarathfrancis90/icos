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
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              AppStrings.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                  ),
            ),
            const SizedBox(height: AppSizes.xl),
            Expanded(
              child: puzzleAsync.when(
                data: (puzzle) => _PuzzleCard(
                  date: today,
                  gridSize: puzzle.gridSize,
                  difficulty: puzzle.difficulty,
                  onPlay: () => context.push('/puzzle/$today'),
                ),
                loading: () => const _PuzzleCardSkeleton(),
                error: (error, _) => _PuzzleCard(
                  date: today,
                  gridSize: 5,
                  difficulty: 'easy',
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
    required this.onPlay,
  });

  final String date;
  final int gridSize;
  final String difficulty;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Card(
          child: Padding(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.grid_4x4_rounded,
                  size: 64,
                  color: AppColors.electricBlue,
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  AppStrings.puzzleTitle,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  '${gridSize}x$gridSize · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPlay,
                    child: const Text('Play'),
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

class _PuzzleCardSkeleton extends StatelessWidget {
  const _PuzzleCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Card(
          child: Padding(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Container(
                  width: 160,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                Container(
                  width: double.infinity,
                  height: AppSizes.minTouchTarget,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
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
