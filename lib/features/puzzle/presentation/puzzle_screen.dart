import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/audio_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/haptics.dart';
import '../../../shared/widgets/animated_background.dart';
import '../../../shared/widgets/particle_field.dart';
import '../../practice/providers/practice_provider.dart';
import '../data/puzzle_source.dart';
import '../data/submission_result.dart';
import '../domain/models/game_state.dart';
import '../domain/models/puzzle.dart';
import '../providers/colorblind_mode_provider.dart';
import '../providers/daily_puzzle_provider.dart';
import '../providers/game_provider.dart';
import '../providers/puzzle_result_provider.dart';
import '../providers/score_submission_provider.dart';
import 'widgets/celebration_overlay.dart';
import 'widgets/game_controls.dart';
import 'widgets/grid_palette.dart';
import 'widgets/notification_prompt.dart';
import 'widgets/puzzle_grid.dart';

/// Solve count at which the store rating prompt is requested (once).
const int reviewPromptSolveCount = 5;

class PuzzleScreen extends ConsumerStatefulWidget {
  const PuzzleScreen({required this.source, super.key});

  /// Convenience for `/puzzle/:date` (daily when today, archive otherwise).
  PuzzleScreen.forDate(String date, {Key? key})
    : this(source: PuzzleSource.forDate(date), key: key);

  final PuzzleSource source;

  /// ISO date for daily / archive sources; `null` for practice.
  String? get date => source.date;

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends ConsumerState<PuzzleScreen> {
  bool _scoreSubmitted = false;
  bool _showCelebration = false;
  bool _startScheduled = false;
  bool _postSolvePromptsShown = false;

  PuzzleSource get source => widget.source;

  AutoDisposeFutureProvider<Puzzle> get _puzzleProvider => switch (source) {
    PracticePuzzleSource(:final seed, :final size, :final difficulty) =>
      practicePuzzleProvider(
        PracticePuzzleSource(seed: seed, size: size, difficulty: difficulty),
      ),
    DailyPuzzleSource(:final date) => puzzleForDateProvider(date),
    ArchivePuzzleSource(:final date) => puzzleForDateProvider(date),
  };

  @override
  void dispose() {
    // Timer stops while the screen is away; startGame resumes it.
    if (ref.exists(gameNotifierProvider(source))) {
      ref.read(gameNotifierProvider(source).notifier).pauseTimer();
    }
    super.dispose();
  }

  /// Starts the game as soon as the puzzle is known. A locally stored result
  /// (instant) opens the solved view directly; a server-side result that
  /// arrives later is adopted by [_adoptResult]. Runs after the frame to
  /// avoid mutating providers during build.
  void _scheduleStart(Puzzle puzzle, SubmissionResult? result) {
    if (_startScheduled) return;
    _startScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(gameNotifierProvider(source).notifier);
      final current = ref.read(gameNotifierProvider(source));
      if (result != null &&
          !result.isRejected &&
          current?.status != GameStatus.completed) {
        _adoptResult(puzzle, result);
        return;
      }
      if (current?.status == GameStatus.completed) {
        // Re-attached to an already finished game (e.g. screen rebuilt).
        _scoreSubmitted = true;
        _postSolvePromptsShown = true;
      }
      notifier.startGame(puzzle);
    });
  }

  /// Shows a completed solve read-only (first server-verified solve wins,
  /// even if this device was mid-game).
  void _adoptResult(Puzzle puzzle, SubmissionResult result) {
    ref
        .read(gameNotifierProvider(source).notifier)
        .loadCompleted(puzzle, result);
    _scoreSubmitted = true;
    _postSolvePromptsShown = true;
    if (mounted) setState(() => _showCelebration = false);
  }

  void _onCompleted(GameState gameState) {
    if (_scoreSubmitted) return;
    _scoreSubmitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AudioService.instance.play(SoundEffect.completion);
      Haptics.heavy();
      ref.read(scoreSubmitterProvider.notifier).submitScore(gameState, source);
      Future.delayed(
        const Duration(milliseconds: AppSizes.completionRippleMs),
        () {
          if (mounted) setState(() => _showCelebration = true);
          _showPostSolvePrompts();
        },
      );
    });
  }

  /// Notification pre-permission after the first solve; store review after
  /// the fifth. Each shown at most once.
  Future<void> _showPostSolvePrompts() async {
    if (_postSolvePromptsShown) return;
    _postSolvePromptsShown = true;
    // Let the celebration card settle first.
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    if (!StorageService.hasSeenNotificationPrompt &&
        StorageService.solveCount >= 1) {
      final accepted = await NotificationPromptDialog.show(context);
      if (accepted) {
        final granted = await NotificationService.requestPermission();
        if (granted) {
          await NotificationService.scheduleDailyReminder(
            NotificationService.defaultReminderTime,
          );
        }
        unawaited(
          AnalyticsService.logEvent(
            granted
                ? AnalyticsEvents.notificationOptIn
                : AnalyticsEvents.notificationOptOut,
          ),
        );
      } else {
        unawaited(
          AnalyticsService.logEvent(AnalyticsEvents.notificationOptOut),
        );
      }
      return;
    }

    if (StorageService.solveCount >= reviewPromptSolveCount &&
        !StorageService.hasRequestedReview) {
      await StorageService.setHasRequestedReview(true);
      try {
        final review = InAppReview.instance;
        if (await review.isAvailable()) await review.requestReview();
      } catch (e) {
        AppLogger.debug('in-app review unavailable', error: e);
      }
    }
  }

  void _onNewPracticePuzzle() {
    final current = source as PracticePuzzleSource;
    ref.read(gameNotifierProvider(source).notifier).discard();
    context.pushReplacement(
      '/practice/play?size=${current.size}&difficulty=${current.difficulty}'
      '&seed=${newPracticeSeed()}',
    );
  }

  void _showWrongCellSnack() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Backtrack to the highlighted cell'),
          duration: Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final puzzleAsync = ref.watch(_puzzleProvider);
    final gameState = ref.watch(gameNotifierProvider(source));
    final hintUi = ref.watch(hintUiProvider(source));
    final palette = GridPalette.forMode(
      ref.watch(colorblindModeNotifierProvider),
    );
    final date = source.date;
    final resultAsync = date == null
        ? const AsyncValue<SubmissionResult?>.data(null)
        : ref.watch(puzzleResultProvider(date));

    if (date != null) {
      ref.listen(puzzleResultProvider(date), (prev, next) {
        final result = next.valueOrNull;
        final current = ref.read(gameNotifierProvider(source));
        final puzzle = ref.read(_puzzleProvider).valueOrNull;
        if (result == null ||
            result.isRejected ||
            puzzle == null ||
            current == null ||
            current.status == GameStatus.completed) {
          return;
        }
        _adoptResult(puzzle, result);
      });
    }

    ref.listen(hintUiProvider(source), (prev, next) {
      if (next.wrongCell != null && prev?.wrongCell != next.wrongCell) {
        _showWrongCellSnack();
      } else if (next.noHint && !(prev?.noHint ?? false)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('No hint available right now')),
          );
      }
    });

    if (gameState != null && gameState.status == GameStatus.completed) {
      _onCompleted(gameState);
    }

    return Scaffold(
      backgroundColor: AppColors.deepBlack,
      body: puzzleAsync.when(
        data: (puzzle) {
          final result = resultAsync.valueOrNull;
          if (gameState == null || gameState.puzzle != puzzle) {
            _scheduleStart(puzzle, result);
            return const Center(
              child: CircularProgressIndicator(color: AppColors.purpleLight),
            );
          }

          final notifier = ref.read(gameNotifierProvider(source).notifier);
          final isReplay = notifier.isReplay;
          final completed = gameState.status == GameStatus.completed;

          return Stack(
            children: [
              const Positioned.fill(child: AnimatedBackground()),
              const Positioned.fill(child: ParticleField()),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: AppSizes.sm),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSizes.md,
                      ),
                      child: Row(
                        children: [
                          _GlassCircleButton(
                            icon: Icons.home_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          if (source.isArchive)
                            const _ModeTag(label: 'Archive')
                          else if (source.isPractice)
                            const _ModeTag(label: 'Practice'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSizes.md,
                      ),
                      child: _GlassInfoBar(
                        timer: AppDateUtils.formatTime(
                          gameState.elapsedSeconds,
                        ),
                        gridSize: puzzle.gridSize,
                        difficulty: puzzle.difficulty,
                        parTimeSeconds: puzzle.parTimeSeconds,
                      ),
                    ),
                    if (isReplay)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: AppSizes.sm,
                        ),
                        child: Text(
                          result?.isRejected ?? false
                              ? 'Solved — not counted'
                              : 'Solved in ${AppDateUtils.formatTime(gameState.elapsedSeconds)}',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSizes.md),
                    Expanded(
                      child: Center(
                        child: PuzzleGrid(
                          gameState: gameState,
                          palette: palette,
                          wrongCell: hintUi.wrongCell,
                          readOnly: isReplay || completed,
                          onCellTap: (row, col) {
                            Haptics.pathStep();
                            AudioService.instance.play(SoundEffect.pathStep);
                            notifier.handleCellTap(row, col);
                          },
                          onCellDrag: (row, col) {
                            Haptics.pathStep();
                            AudioService.instance.play(SoundEffect.pathStep);
                            notifier.handleCellDrag(row, col);
                          },
                        ),
                      ),
                    ),
                    GameControls(
                      gameState: gameState,
                      hintThinking: hintUi.thinking,
                      readOnly: isReplay,
                      onUndo: () {
                        Haptics.undo();
                        AudioService.instance.play(SoundEffect.undo);
                        notifier.undo();
                      },
                      onReset: () {
                        Haptics.heavy();
                        notifier.reset();
                      },
                      onHint: () {
                        if (hintUi.thinking) return;
                        Haptics.hintReveal();
                        AudioService.instance.play(SoundEffect.hintReveal);
                        notifier.useHint();
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
                  dateLabel: source.isPractice ? 'Practice' : date,
                  streak: result?.streak?.currentStreak,
                  status: result?.status,
                  isArchive: source.isArchive,
                  isPractice: source.isPractice,
                  path: [
                    for (final p in gameState.path) [p.row, p.col],
                  ],
                  walls: [
                    for (final w in puzzle.walls) [w.row, w.col],
                  ],
                  onNewPuzzle: source.isPractice ? _onNewPracticePuzzle : null,
                  onDone: () {
                    if (source.isPractice) notifier.discard();
                    Navigator.of(context).pop();
                  },
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
                  onPressed: () => ref.invalidate(_puzzleProvider),
                  child: const Text('Retry'),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill showing Archive / Practice mode.
class _ModeTag extends StatelessWidget {
  const _ModeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.sm + 4,
        vertical: AppSizes.xs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(color: AppColors.cellBorder.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondaryDark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Frosted glass info bar showing timer, level, and par.
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
            border: Border.all(color: AppColors.glassBorder, width: 0.5),
          ),
          child: Row(
            children: [
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
              Text(
                '${gridSize}x$gridSize · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                style: const TextStyle(
                  color: AppColors.glassText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
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
  const _GlassCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Go back',
      button: true,
      child: GestureDetector(
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
          child: Icon(icon, color: AppColors.textSecondaryDark, size: 22),
        ),
      ),
    );
  }
}
