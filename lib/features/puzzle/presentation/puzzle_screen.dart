import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/haptics.dart';
import '../domain/models/game_state.dart';
import '../providers/daily_puzzle_provider.dart';
import '../providers/game_provider.dart';
import '../providers/score_submission_provider.dart';
import 'widgets/celebration_overlay.dart';
import 'widgets/game_controls.dart';
import 'widgets/puzzle_grid.dart';

class PuzzleScreen extends ConsumerStatefulWidget {
  const PuzzleScreen({required this.date, super.key});

  final String date;

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends ConsumerState<PuzzleScreen> {
  bool _scoreSubmitted = false;

  @override
  void initState() {
    super.initState();
    _loadPuzzle();
  }

  Future<void> _loadPuzzle() async {
    final puzzleAsync = ref.read(dailyPuzzleProvider);
    puzzleAsync.whenData((puzzle) {
      ref.read(gameNotifierProvider.notifier).startGame(puzzle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final puzzleAsync = ref.watch(dailyPuzzleProvider);
    final gameState = ref.watch(gameNotifierProvider);

    // Auto-submit score when completed
    if (gameState != null &&
        gameState.status == GameStatus.completed &&
        !_scoreSubmitted) {
      _scoreSubmitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(scoreSubmitterProvider.notifier).submitScore(gameState);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Puzzle',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          if (gameState != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSizes.md),
              child: Center(
                child: Text(
                  AppDateUtils.formatTime(gameState.elapsedSeconds),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ),
        ],
      ),
      body: puzzleAsync.when(
        data: (puzzle) {
          if (gameState == null) {
            // Initialize game if not yet started
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(gameNotifierProvider.notifier).startGame(puzzle);
            });
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    // Puzzle info
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSizes.lg,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _InfoChip(
                            icon: Icons.grid_4x4_rounded,
                            label:
                                '${puzzle.gridSize}x${puzzle.gridSize}',
                          ),
                          _InfoChip(
                            icon: Icons.speed_rounded,
                            label: puzzle.difficulty[0].toUpperCase() +
                                puzzle.difficulty.substring(1),
                          ),
                          _InfoChip(
                            icon: Icons.timer_outlined,
                            label:
                                'Par ${AppDateUtils.formatTimeHuman(puzzle.parTimeSeconds)}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // Puzzle grid
                    Expanded(
                      child: Center(
                        child: PuzzleGrid(
                          gameState: gameState,
                          onCellTap: (row, col) {
                            Haptics.light();
                            ref
                                .read(gameNotifierProvider.notifier)
                                .handleCellTap(row, col);
                          },
                          onCellDrag: (row, col) {
                            Haptics.selection();
                            ref
                                .read(gameNotifierProvider.notifier)
                                .handleCellDrag(row, col);
                          },
                        ),
                      ),
                    ),

                    // Controls
                    GameControls(
                      gameState: gameState,
                      onUndo: () {
                        Haptics.medium();
                        ref.read(gameNotifierProvider.notifier).undo();
                      },
                      onReset: () {
                        Haptics.heavy();
                        ref.read(gameNotifierProvider.notifier).reset();
                      },
                      onHint: () {
                        Haptics.medium();
                        ref.read(gameNotifierProvider.notifier).useHint();
                      },
                    ),
                    const SizedBox(height: AppSizes.lg),
                  ],
                ),
              ),
              if (gameState.status == GameStatus.completed)
                CelebrationOverlay(
                  timeSeconds: gameState.elapsedSeconds,
                  hintsUsed: gameState.hintsUsed,
                  parTimeSeconds: puzzle.parTimeSeconds,
                  gridSize: puzzle.gridSize,
                  difficulty: puzzle.difficulty,
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: AppSizes.md),
              Text(
                'Could not load puzzle',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSizes.md),
              ElevatedButton(
                onPressed: () => ref.invalidate(dailyPuzzleProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.electricBlue),
          const SizedBox(width: AppSizes.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
