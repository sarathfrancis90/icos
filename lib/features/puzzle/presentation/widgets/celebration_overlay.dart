import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/app_logger.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/motion.dart';
import '../../../../shared/widgets/spring_button.dart';
import '../../../sharing/domain/share_card_generator.dart';
import '../../../sharing/presentation/share_card_widget.dart';
import '../../data/submission_result.dart';

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    required this.timeSeconds,
    required this.hintsUsed,
    required this.parTimeSeconds,
    required this.gridSize,
    required this.difficulty,
    this.dateLabel,
    this.streak,
    this.status,
    this.isArchive = false,
    this.isPractice = false,
    this.path = const [],
    this.walls = const [],
    this.onDone,
    this.onNewPuzzle,
    super.key,
  });

  final int timeSeconds;
  final int hintsUsed;
  final int parTimeSeconds;
  final int gridSize;
  final String difficulty;

  /// Date shown on the share card (`YYYY-MM-DD`) or `Practice`.
  final String? dateLabel;

  /// Current streak after this solve (daily only).
  final int? streak;

  /// Server acknowledgement state; drives the "verified / not counted" note.
  final SubmissionStatus? status;
  final bool isArchive;
  final bool isPractice;

  /// Solved path `[[row, col], ...]` and walls for the spoiler-free card.
  final List<List<int>> path;
  final List<List<int>> walls;

  /// Called by "Done"; defaults to popping the route.
  final VoidCallback? onDone;

  /// Practice only: starts another puzzle.
  final VoidCallback? onNewPuzzle;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _cardController;
  late final Animation<double> _fadeIn;
  late final Animation<double> _cardScale;
  late final Animation<double> _cardSlide;
  late final ConfettiController _confettiController;
  late final ConfettiController _confettiBottomController;

  // Phase 8: Trophy bounce
  late final AnimationController _trophyController;
  late final Animation<double> _trophyScale;

  // Phase 8: Staggered stat reveals
  late final AnimationController _statsController;

  // Phase 8: Score count-up
  late final AnimationController _countUpController;

  final GlobalKey _shareCardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final underPar = widget.timeSeconds <= widget.parTimeSeconds;
    final text = ShareCardGenerator.buildShareText(
      timeSeconds: widget.timeSeconds,
      hintsUsed: widget.hintsUsed,
      gridSize: widget.gridSize,
      difficulty: widget.difficulty,
      underPar: underPar,
      dateLabel: widget.dateLabel,
      streak: widget.streak,
    );
    try {
      final bytes = await ShareCardGenerator.captureFromWidget(_shareCardKey);
      if (bytes != null) {
        final name = 'icos-${widget.dateLabel ?? 'result'}.png';
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png', name: name)],
          text: text,
          fileNameOverrides: [name],
        );
      } else {
        await Share.share(text);
      }
      unawaited(
        AnalyticsService.logEvent(AnalyticsEvents.shareResult, {
          'image': bytes != null,
          'practice': widget.isPractice,
        }),
      );
    } catch (e, st) {
      AppLogger.warn('share failed', error: e, st: st);
      try {
        await Share.share(text);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void initState() {
    super.initState();

    // Background fade
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    // Card entrance with spring feel
    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _cardScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.elasticOut),
    );
    _cardSlide = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Confetti — top burst
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    // Confetti — bottom upward burst (Phase 8)
    _confettiBottomController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    // Phase 8: Trophy bounce
    _trophyController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _trophyScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _trophyController, curve: Curves.elasticOut),
    );

    // Phase 8: Stats stagger
    _statsController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Phase 8: Score count-up
    _countUpController = AnimationController(
      duration: const Duration(milliseconds: AppSizes.scoreCountUpMs),
      vsync: this,
    );

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _cardController.forward();
        _confettiController.play();
        _confettiBottomController.play();
      }
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _statsController.forward();
        _countUpController.forward();
      }
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _trophyController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _cardController.dispose();
    _confettiController.dispose();
    _confettiBottomController.dispose();
    _trophyController.dispose();
    _statsController.dispose();
    _countUpController.dispose();
    super.dispose();
  }

  /// Stagger helper: returns 0-1 for an element that appears at [delayMs]
  /// within the stats controller timeline.
  double _staggeredValue(int delayMs) {
    const totalMs = 1200.0;
    final start = delayMs / totalMs;
    final end = (delayMs + AppSizes.statRevealStaggerMs) / totalMs;
    if (_statsController.value < start) return 0.0;
    if (_statsController.value > end) return 1.0;
    return ((_statsController.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final underPar = widget.timeSeconds <= widget.parTimeSeconds;
    final reduceMotion = MotionUtils.shouldReduceMotion(context);

    return Stack(
      children: [
        // Off-screen share card (must be painted for RepaintBoundary.toImage).
        Positioned(
          left: -2000,
          top: 0,
          child: ShareCardWidget(
            repaintKey: _shareCardKey,
            gridSize: widget.gridSize,
            difficulty: widget.difficulty,
            timeSeconds: widget.timeSeconds,
            hintsUsed: widget.hintsUsed,
            parTimeSeconds: widget.parTimeSeconds,
            dateLabel: widget.dateLabel,
            streak: widget.streak,
            pathVisualization: PathBlocksVisualization(
              gridSize: widget.gridSize,
              path: widget.path,
              walls: widget.walls,
            ),
          ),
        ),

        // Dark overlay with radial burst
        AnimatedBuilder(
          animation: _fadeController,
          builder: (context, child) => Opacity(
            opacity: _fadeIn.value,
            child: child,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.5,
                colors: [
                  AppColors.pathOrange.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
        ),

        // Confetti — top
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 30,
            maxBlastForce: 30,
            minBlastForce: 10,
            emissionFrequency: 0.06,
            gravity: 0.2,
            colors: const [
              AppColors.pathYellowBright,
              AppColors.pathOrange,
              AppColors.purpleLight,
              AppColors.success,
              AppColors.streakGold,
              Colors.white,
              AppColors.pathAmber,
            ],
          ),
        ),

        // Phase 8: Confetti — bottom upward burst
        Align(
          alignment: Alignment.bottomCenter,
          child: ConfettiWidget(
            confettiController: _confettiBottomController,
            blastDirection: -3.14159 / 2, // upward
            shouldLoop: false,
            numberOfParticles: 30,
            maxBlastForce: 25,
            minBlastForce: 8,
            emissionFrequency: 0.05,
            gravity: 0.3,
            colors: const [
              AppColors.pathYellowBright,
              AppColors.pathOrange,
              AppColors.purpleLight,
              AppColors.streakGold,
              AppColors.pathAmber,
            ],
          ),
        ),

        // Card content
        AnimatedBuilder(
          animation: _cardController,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _cardSlide.value),
            child: Transform.scale(
              scale: _cardScale.value,
              child: Opacity(
                opacity: _cardController.value.clamp(0.0, 1.0),
                child: child,
              ),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSizes.lg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: _CelebrationCard(
                  underPar: underPar,
                  timeSeconds: widget.timeSeconds,
                  hintsUsed: widget.hintsUsed,
                  parTimeSeconds: widget.parTimeSeconds,
                  gridSize: widget.gridSize,
                  difficulty: widget.difficulty,
                  streak: widget.streak,
                  status: widget.status,
                  isArchive: widget.isArchive,
                  isPractice: widget.isPractice,
                  onShare: _sharing ? null : _share,
                  onDone: widget.onDone ?? () => Navigator.of(context).pop(),
                  onNewPuzzle: widget.onNewPuzzle,
                  trophyScale: reduceMotion ? 1.0 : _trophyScale.value,
                  countUpValue: reduceMotion ? 1.0 : _countUpController.value,
                  staggeredValue: reduceMotion ? (_) => 1.0 : _staggeredValue,
                  statsAnimation: _statsController,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({
    required this.underPar,
    required this.timeSeconds,
    required this.hintsUsed,
    required this.parTimeSeconds,
    required this.gridSize,
    required this.difficulty,
    required this.trophyScale,
    required this.countUpValue,
    required this.staggeredValue,
    required this.statsAnimation,
    required this.onShare,
    required this.onDone,
    this.onNewPuzzle,
    this.streak,
    this.status,
    this.isArchive = false,
    this.isPractice = false,
  });

  final bool underPar;
  final int timeSeconds;
  final int hintsUsed;
  final int parTimeSeconds;
  final int gridSize;
  final String difficulty;
  final VoidCallback? onShare;
  final VoidCallback onDone;
  final VoidCallback? onNewPuzzle;
  final int? streak;
  final SubmissionStatus? status;
  final bool isArchive;
  final bool isPractice;
  final double trophyScale;
  final double countUpValue;
  final double Function(int delayMs) staggeredValue;
  final Animation<double> statsAnimation;

  String? get _note {
    if (isPractice) return 'Practice solves stay on this device.';
    if (status == SubmissionStatus.rejected) {
      return 'This solve could not be verified and was not counted.';
    }
    if (isArchive) return "Archive solves don't affect your streak.";
    if (status == SubmissionStatus.localOnly) {
      return 'Saved on this device only.';
    }
    if (status == SubmissionStatus.pending) return 'Saving your result…';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Phase 8: Count-up display time
    final displayTime = (timeSeconds * countUpValue).round();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: AppColors.cellBorder.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
        child: AnimatedBuilder(
          animation: statsAnimation,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                underPar ? 'Crushed It!' : 'Puzzle Complete!',
                style: TextStyle(
                  color:
                      underPar ? AppColors.streakGold : AppColors.textPrimaryDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSizes.xs),

              // Phase 8: Trophy icon with bounce-in
              Transform.scale(
                scale: trophyScale,
                child: Icon(
                  underPar
                      ? Icons.emoji_events_rounded
                      : Icons.check_circle_rounded,
                  size: 40,
                  color: underPar ? AppColors.streakGold : AppColors.success,
                ),
              ),
              const SizedBox(height: AppSizes.md),

              // Phase 8: Staggered stat reveals — grid pill at 0ms
              _StaggeredReveal(
                progress: staggeredValue(0),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatPill(
                        label:
                            '${gridSize}x$gridSize · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    // Time at 200ms stagger
                    Expanded(
                      child: _StaggeredReveal(
                        progress: staggeredValue(200),
                        child: _StatPill(
                          label: AppDateUtils.formatTime(displayTime),
                          icon: Icons.timer_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.sm),

              // Par comparison at 400ms stagger
              if (underPar)
                _StaggeredReveal(
                  progress: staggeredValue(400),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: AppSizes.sm,
                      horizontal: AppSizes.md,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      border: Border.all(
                        color: AppColors.purpleLight.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Under par by ${AppDateUtils.formatTime(parTimeSeconds - timeSeconds)}!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.purpleLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

              if (hintsUsed > 0) ...[
                const SizedBox(height: AppSizes.sm),
                _StaggeredReveal(
                  progress: staggeredValue(600),
                  child: Text(
                    '$hintsUsed hint${hintsUsed == 1 ? '' : 's'} used',
                    style: const TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],

              if (streak != null && streak! > 0 && !isArchive && !isPractice) ...[
                const SizedBox(height: AppSizes.sm),
                _StaggeredReveal(
                  progress: staggeredValue(600),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: AppColors.streakGold,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$streak day streak',
                        style: const TextStyle(
                          color: AppColors.streakGold,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_note != null) ...[
                const SizedBox(height: AppSizes.sm),
                _StaggeredReveal(
                  progress: staggeredValue(700),
                  child: Text(
                    _note!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: status == SubmissionStatus.rejected
                          ? AppColors.warning
                          : AppColors.textSecondaryDark,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSizes.lg),

              // Buttons at 800ms stagger
              _StaggeredReveal(
                progress: staggeredValue(800),
                child: Column(
                  children: [
                    // Share button — purple gradient with spring
                    _GradientButton(
                      label: onShare == null ? 'Sharing…' : 'Share Result',
                      icon: Icons.share_rounded,
                      onPressed: onShare ?? () {},
                    ),
                    const SizedBox(height: AppSizes.sm),

                    if (onNewPuzzle != null) ...[
                      _GradientButton(
                        label: 'New Puzzle',
                        icon: Icons.refresh_rounded,
                        onPressed: onNewPuzzle!,
                      ),
                      const SizedBox(height: AppSizes.sm),
                    ],

                    // Done button — outlined
                    SizedBox(
                      width: double.infinity,
                      child: SpringButton(
                        onPressed: onDone,
                        child: Container(
                          height: AppSizes.minTouchTarget,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusXl),
                            border: Border.all(
                              color: AppColors.textSecondaryDark
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Done',
                              style: TextStyle(
                                color: AppColors.textPrimaryDark,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
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

/// Phase 8: Slide-up + fade-in reveal for staggered stats.
class _StaggeredReveal extends StatelessWidget {
  const _StaggeredReveal({
    required this.progress,
    required this.child,
  });

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 20 * (1.0 - progress)),
        child: child,
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: AppSizes.sm + 2,
        horizontal: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.textSecondaryDark),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimaryDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SpringButton(
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        height: AppSizes.minTouchTarget + 8,
        decoration: BoxDecoration(
          gradient: AppColors.purpleButtonGradient,
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          boxShadow: const [
            BoxShadow(
              color: AppColors.purpleGlow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
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
