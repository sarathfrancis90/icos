import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../sharing/domain/share_card_generator.dart';

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    required this.timeSeconds,
    required this.hintsUsed,
    required this.parTimeSeconds,
    required this.gridSize,
    required this.difficulty,
    super.key,
  });

  final int timeSeconds;
  final int hintsUsed;
  final int parTimeSeconds;
  final int gridSize;
  final String difficulty;

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

    // Card entrance (bounce in from bottom)
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

    // Confetti
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _cardController.forward();
        _confettiController.play();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _cardController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final underPar = widget.timeSeconds <= widget.parTimeSeconds;

    return Stack(
      children: [
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

        // Confetti
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 40,
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
  });

  final bool underPar;
  final int timeSeconds;
  final int hintsUsed;
  final int parTimeSeconds;
  final int gridSize;
  final String difficulty;

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Text(
              underPar ? 'Crushed It!' : 'Puzzle Complete!',
              style: TextStyle(
                color: underPar ? AppColors.streakGold : AppColors.textPrimaryDark,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: AppSizes.xs),

            // Trophy icon
            Icon(
              underPar ? Icons.emoji_events_rounded : Icons.check_circle_rounded,
              size: 40,
              color: underPar ? AppColors.streakGold : AppColors.success,
            ),
            const SizedBox(height: AppSizes.md),

            // Stats row
            Row(
              children: [
                Expanded(
                  child: _StatPill(
                    label: '${gridSize}x$gridSize · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: _StatPill(
                    label: AppDateUtils.formatTime(timeSeconds),
                    icon: Icons.timer_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.sm),

            // Par comparison
            if (underPar)
              Container(
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

            if (hintsUsed > 0) ...[
              const SizedBox(height: AppSizes.sm),
              Text(
                '$hintsUsed hint${hintsUsed == 1 ? '' : 's'} used',
                style: TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 13,
                ),
              ),
            ],

            const SizedBox(height: AppSizes.lg),

            // Share button — purple gradient
            _GradientButton(
              label: 'Share Result',
              icon: Icons.share_rounded,
              onPressed: () {
                final text = ShareCardGenerator.buildShareText(
                  timeSeconds: timeSeconds,
                  hintsUsed: hintsUsed,
                  gridSize: gridSize,
                  difficulty: difficulty,
                  underPar: underPar,
                );
                Share.share(text);
              },
            ),
            const SizedBox(height: AppSizes.sm),

            // Done button — outlined
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        height: AppSizes.minTouchTarget + 8,
        decoration: BoxDecoration(
          gradient: AppColors.purpleButtonGradient,
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          boxShadow: [
            BoxShadow(
              color: AppColors.purpleGlow,
              blurRadius: 12,
              offset: const Offset(0, 4),
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
