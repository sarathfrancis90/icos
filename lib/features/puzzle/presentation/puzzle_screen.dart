import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/utils/haptics.dart';
import '../domain/models/game_state.dart';
import '../providers/daily_puzzle_provider.dart';
import '../providers/game_provider.dart';
import '../providers/score_submission_provider.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/particle_field.dart';
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
  bool _showCelebration = false;

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

    // Auto-submit score when completed + delay celebration for ripple
    if (gameState != null &&
        gameState.status == GameStatus.completed &&
        !_scoreSubmitted) {
      _scoreSubmitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(scoreSubmitterProvider.notifier).submitScore(gameState);
        // Delay celebration overlay to let the grid completion ripple play
        Future.delayed(
          const Duration(milliseconds: AppSizes.completionRippleMs),
          () {
            if (mounted) setState(() => _showCelebration = true);
          },
        );
      });
    }

    return Scaffold(
      backgroundColor: AppColors.deepBlack,
      body: puzzleAsync.when(
        data: (puzzle) {
          if (gameState == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(gameNotifierProvider.notifier).startGame(puzzle);
            });
            return const Center(
              child: CircularProgressIndicator(color: AppColors.purpleLight),
            );
          }

          return Stack(
            children: [
              const Positioned.fill(child: AnimatedBackground()),
              const Positioned.fill(child: ParticleField()),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: AppSizes.sm),

                    // Top bar: Back button + Info bar
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSizes.md,
                      ),
                      child: Row(
                        children: [
                          // Home button
                          _GlassCircleButton(
                            icon: Icons.home_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Glass info bar
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSizes.md,
                      ),
                      child: _GlassInfoBar(
                        timer: AppDateUtils.formatTime(gameState.elapsedSeconds),
                        gridSize: puzzle.gridSize,
                        difficulty: puzzle.difficulty,
                        parTimeSeconds: puzzle.parTimeSeconds,
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // Puzzle grid
                    Expanded(
                      child: Center(
                        child: PuzzleGrid(
                          gameState: gameState,
                          onCellTap: (row, col) {
                            Haptics.pathStep();
                            AudioService.instance.play(SoundEffect.slither);
                            ref
                                .read(gameNotifierProvider.notifier)
                                .handleCellTap(row, col);
                          },
                          onCellDrag: (row, col) {
                            Haptics.pathStep();
                            AudioService.instance.play(SoundEffect.slither);
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
                        Haptics.undo();
                        AudioService.instance.play(SoundEffect.undo);
                        ref.read(gameNotifierProvider.notifier).undo();
                      },
                      onReset: () {
                        Haptics.heavy();
                        ref.read(gameNotifierProvider.notifier).reset();
                      },
                      onHint: () {
                        Haptics.hintReveal();
                        AudioService.instance.play(SoundEffect.hintReveal);
                        ref.read(gameNotifierProvider.notifier).useHint();
                      },
                    ),
                    const SizedBox(height: AppSizes.md),
                  ],
                ),
              ),
              if (_showCelebration)
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.purpleLight),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.error.withValues(alpha: 0.7),
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                'Could not load puzzle',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSizes.md),
              SizedBox(
                width: 160,
                child: ElevatedButton(
                  onPressed: () => ref.invalidate(dailyPuzzleProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted glass info bar showing timer, level, and share.
class _GlassInfoBar extends StatelessWidget {
  const _GlassInfoBar({
    required this.timer,
    required this.gridSize,
    required this.difficulty,
    required this.parTimeSeconds,
  });

  final String timer;
  final int gridSize;
  final String difficulty;
  final int parTimeSeconds;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm + 4,
          ),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: AppColors.glassBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Timer
              Text(
                timer,
                style: const TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              // Level info
              Text(
                '${gridSize}x$gridSize · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                style: const TextStyle(
                  color: AppColors.glassText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Par time
              Text(
                'Par ${AppDateUtils.formatTimeHuman(parTimeSeconds)}',
                style: TextStyle(
                  color: AppColors.glassText.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small frosted glass circle button.
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.elevatedSurface.withValues(alpha: 0.7),
          border: Border.all(
            color: AppColors.cellBorder.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          icon,
          color: AppColors.textSecondaryDark,
          size: 22,
        ),
      ),
    );
  }
}
