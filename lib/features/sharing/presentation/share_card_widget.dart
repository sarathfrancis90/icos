import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';

/// Spoiler-free result card rendered through a [RepaintBoundary] so it can
/// be captured as a PNG (see `ShareCardGenerator.captureFromWidget`).
class ShareCardWidget extends StatelessWidget {
  const ShareCardWidget({
    required this.repaintKey,
    required this.gridSize,
    required this.difficulty,
    required this.timeSeconds,
    required this.hintsUsed,
    required this.parTimeSeconds,
    required this.pathVisualization,
    this.dateLabel,
    this.streak,
    super.key,
  });

  final GlobalKey repaintKey;
  final int gridSize;
  final String difficulty;
  final int timeSeconds;
  final int hintsUsed;
  final int parTimeSeconds;
  final Widget pathVisualization;

  /// Shown top-right; defaults to today's UTC date.
  final String? dateLabel;

  /// Current streak (daily solves only).
  final int? streak;

  @override
  Widget build(BuildContext context) {
    final underPar = timeSeconds <= parTimeSeconds;
    final label = dateLabel ?? AppDateUtils.todayUtc();

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 360,
        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: AppColors.deepNavy,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Icos',
                  style: TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondaryDark,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),

            // Puzzle grid visualization
            SizedBox(
              width: 200,
              height: 200,
              child: pathVisualization,
            ),
            const SizedBox(height: AppSizes.md),

            // Difficulty & grid info
            Text(
              '${gridSize}x$gridSize · ${difficulty[0].toUpperCase()}${difficulty.substring(1)}',
              style: const TextStyle(
                color: AppColors.textSecondaryDark,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppSizes.sm),

            // Results row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ResultPill(
                  icon: Icons.timer_outlined,
                  value: AppDateUtils.formatTime(timeSeconds),
                  highlight: underPar,
                ),
                const SizedBox(width: AppSizes.sm),
                _ResultPill(
                  icon: Icons.lightbulb_outline,
                  value: '$hintsUsed hint${hintsUsed != 1 ? 's' : ''}',
                  highlight: hintsUsed == 0,
                ),
                if (streak != null && streak! > 0) ...[
                  const SizedBox(width: AppSizes.sm),
                  _ResultPill(
                    icon: Icons.local_fire_department_rounded,
                    value: '$streak day${streak == 1 ? '' : 's'}',
                    highlight: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSizes.sm),

            if (underPar)
              const Text(
                '⭐ Under Par!',
                style: TextStyle(
                  color: AppColors.streakGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Abstract block rendering of a solved grid: walls are dark, every other
/// cell gets a colour from a coarse band of its path position. No numbers,
/// arrows or exact ordering — enough to show the shape, not the solution.
class PathBlocksVisualization extends StatelessWidget {
  const PathBlocksVisualization({
    required this.gridSize,
    required this.path,
    required this.walls,
    super.key,
  });

  final int gridSize;

  /// `[[row, col], ...]`
  final List<List<int>> path;

  /// `[[row, col], ...]`
  final List<List<int>> walls;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PathBlocksPainter(gridSize: gridSize, path: path, walls: walls),
    );
  }
}

class _PathBlocksPainter extends CustomPainter {
  _PathBlocksPainter({
    required this.gridSize,
    required this.path,
    required this.walls,
  });

  final int gridSize;
  final List<List<int>> path;
  final List<List<int>> walls;

  static const _bands = [
    AppColors.pathOrangeDeep,
    AppColors.pathOrange,
    AppColors.pathAmber,
    AppColors.pathYellow,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (gridSize <= 0) return;
    final cell = size.width / gridSize;
    final wallSet = {for (final w in walls) w[0] * gridSize + w[1]};
    final band = <int, int>{};
    for (var i = 0; i < path.length; i++) {
      final idx = path[i][0] * gridSize + path[i][1];
      band[idx] = path.length <= 1
          ? 0
          : (i * _bands.length ~/ path.length).clamp(0, _bands.length - 1);
    }

    for (var row = 0; row < gridSize; row++) {
      for (var col = 0; col < gridSize; col++) {
        final idx = row * gridSize + col;
        final rect = Rect.fromLTWH(col * cell + 2, row * cell + 2, cell - 4, cell - 4);
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.18));
        final Color color;
        if (wallSet.contains(idx)) {
          color = AppColors.wallFill;
        } else if (band.containsKey(idx)) {
          color = _bands[band[idx]!];
        } else {
          color = AppColors.cellBackground;
        }
        canvas.drawRRect(rrect, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PathBlocksPainter oldDelegate) =>
      oldDelegate.gridSize != gridSize ||
      oldDelegate.path != path ||
      oldDelegate.walls != walls;
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({
    required this.icon,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.sm + 4,
        vertical: AppSizes.xs + 2,
      ),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.electricBlue.withValues(alpha: 0.2)
            : AppColors.mediumNavy,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: highlight
            ? Border.all(color: AppColors.electricBlue.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlight
                ? AppColors.electricBlue
                : AppColors.textSecondaryDark,
          ),
          const SizedBox(width: AppSizes.xs),
          Text(
            value,
            style: TextStyle(
              color: highlight
                  ? AppColors.electricBlue
                  : AppColors.textSecondaryDark,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
