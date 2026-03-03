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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleUp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: AppSizes.celebrationTotalMs),
      vsync: this,
    );

    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    _scaleUp = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final underPar = widget.timeSeconds <= widget.parTimeSeconds;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _fadeIn.value,
        child: Transform.scale(
          scale: _scaleUp.value,
          child: child,
        ),
      ),
      child: Container(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Card(
              child: Padding(
                padding: const EdgeInsetsDirectional.all(AppSizes.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      underPar
                          ? Icons.emoji_events_rounded
                          : Icons.check_circle_rounded,
                      size: 64,
                      color: underPar
                          ? AppColors.streakGold
                          : AppColors.success,
                    ),
                    const SizedBox(height: AppSizes.md),
                    Text(
                      underPar ? 'Under Par!' : 'Puzzle Complete!',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: underPar
                                    ? AppColors.streakGold
                                    : AppColors.success,
                              ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    _ResultRow(
                      label: 'Time',
                      value: AppDateUtils.formatTime(widget.timeSeconds),
                    ),
                    _ResultRow(
                      label: 'Par',
                      value: AppDateUtils.formatTime(widget.parTimeSeconds),
                    ),
                    _ResultRow(
                      label: 'Hints Used',
                      value: '${widget.hintsUsed}',
                    ),
                    const SizedBox(height: AppSizes.lg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final text = ShareCardGenerator.buildShareText(
                            timeSeconds: widget.timeSeconds,
                            hintsUsed: widget.hintsUsed,
                            gridSize: widget.gridSize,
                            difficulty: widget.difficulty,
                            underPar: underPar,
                          );
                          Share.share(text);
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share Result'),
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSizes.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
