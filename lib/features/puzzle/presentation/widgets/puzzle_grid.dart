import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/puzzle.dart';

class PuzzleGrid extends StatelessWidget {
  const PuzzleGrid({
    required this.gameState,
    required this.onCellTap,
    required this.onCellDrag,
    super.key,
  });

  final GameState gameState;
  final void Function(int row, int col) onCellTap;
  final void Function(int row, int col) onCellDrag;

  @override
  Widget build(BuildContext context) {
    final size = gameState.puzzle.gridSize;
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = (screenWidth - AppSizes.gridPadding * 2)
        .clamp(0.0, AppSizes.gridMaxWidth);
    final cellSize = gridWidth / size;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.gridPadding,
      ),
      child: Center(
        child: SizedBox(
          width: gridWidth,
          height: gridWidth,
          child: GestureDetector(
            onPanUpdate: (details) {
              final localPos = details.localPosition;
              final row = (localPos.dy / cellSize).floor();
              final col = (localPos.dx / cellSize).floor();
              if (row >= 0 && row < size && col >= 0 && col < size) {
                onCellDrag(row, col);
              }
            },
            child: CustomPaint(
              painter: _GridPainter(
                gameState: gameState,
                cellSize: cellSize,
              ),
              child: _buildTapTargets(size, cellSize),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTapTargets(int size, double cellSize) {
    return Stack(
      children: [
        for (int row = 0; row < size; row++)
          for (int col = 0; col < size; col++)
            Positioned(
              left: col * cellSize,
              top: row * cellSize,
              width: cellSize,
              height: cellSize,
              child: GestureDetector(
                onTap: () => onCellTap(row, col),
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  label: _cellSemanticLabel(row, col),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
      ],
    );
  }

  String _cellSemanticLabel(int row, int col) {
    final cellState = gameState.grid[row][col];
    final stateLabel = switch (cellState) {
      CellState.empty => 'empty',
      CellState.filled => 'filled',
      CellState.waypoint => _waypointLabel(row, col),
      CellState.wall => 'wall',
    };
    return 'Row ${row + 1}, Column ${col + 1}, $stateLabel';
  }

  String _waypointLabel(int row, int col) {
    for (final wp in gameState.puzzle.waypoints) {
      if (wp.row == row && wp.col == col) {
        return 'waypoint ${wp.order}';
      }
    }
    return 'waypoint';
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.gameState,
    required this.cellSize,
  });

  final GameState gameState;
  final double cellSize;

  // Cell geometry constants
  static const double _cellInset = 2.0;
  static const double _cellRadius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final gridSize = gameState.puzzle.gridSize;

    // Draw all cells (3D embossed)
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        _drawEmbossedCell(canvas, row, col);
      }
    }

    // Draw hint cell highlight
    _drawHintCell(canvas);

    // Draw path with gradient tube effect
    _drawGradientTubePath(canvas);

    // Draw waypoints on top
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        if (gameState.grid[row][col] == CellState.waypoint) {
          _drawWaypoint(canvas, row, col);
        }
      }
    }
  }

  /// Draws a 3D embossed/inset cell matching the reference design.
  void _drawEmbossedCell(Canvas canvas, int row, int col) {
    final cellState = gameState.grid[row][col];
    final rect = Rect.fromLTWH(
      col * cellSize + _cellInset,
      row * cellSize + _cellInset,
      cellSize - _cellInset * 2,
      cellSize - _cellInset * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_cellRadius));

    final isInPath = gameState.path.any((p) => p.row == row && p.col == col);

    if (cellState == CellState.wall) {
      // Walls: darker solid fill
      final paint = Paint()..color = AppColors.wallFill;
      canvas.drawRRect(rrect, paint);
      return;
    }

    if (isInPath && cellState != CellState.waypoint) {
      // Visited cell: warm amber fill
      _drawVisitedCell(canvas, rect, rrect, row, col);
    } else {
      // Normal empty cell with 3D inset effect
      _drawInsetCell(canvas, rect, rrect);
    }
  }

  /// Draws the 3D inset empty cell (dark sunken look).
  void _drawInsetCell(Canvas canvas, Rect rect, RRect rrect) {
    // Shadow at bottom-right (gives "pushed in" effect)
    final shadowPaint = Paint()
      ..color = AppColors.cellShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawRRect(
      rrect.shift(const Offset(1.0, 1.0)),
      shadowPaint,
    );

    // Highlight at top-left
    final highlightPaint = Paint()
      ..color = AppColors.cellHighlight.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
    canvas.drawRRect(
      rrect.shift(const Offset(-0.5, -0.5)),
      highlightPaint,
    );

    // Main cell fill
    final fillPaint = Paint()..color = AppColors.cellBackground;
    canvas.drawRRect(rrect, fillPaint);

    // Subtle inner border
    final borderPaint = Paint()
      ..color = AppColors.cellBorder.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Draws a visited cell with warm amber tint.
  void _drawVisitedCell(Canvas canvas, Rect rect, RRect rrect, int row, int col) {
    // Determine how far along path this cell is (for color progression)
    final pathIndex = gameState.path.indexWhere((p) => p.row == row && p.col == col);
    final progress = gameState.path.length > 1
        ? pathIndex / (gameState.path.length - 1)
        : 0.0;

    // Interpolate from dark amber to brighter amber/yellow
    final baseColor = Color.lerp(
      AppColors.filledCellDark,
      AppColors.filledCellLight,
      progress,
    )!;

    final fillPaint = Paint()..color = baseColor;
    canvas.drawRRect(rrect, fillPaint);

    // Subtle warm border
    final borderPaint = Paint()
      ..color = AppColors.pathAmber.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Draws the thick gradient "tube" path from orange → yellow.
  void _drawGradientTubePath(Canvas canvas) {
    if (gameState.path.length < 2) return;

    final tubeWidth = cellSize * 0.45;
    final points = gameState.path
        .map((p) => Offset(
              p.col * cellSize + cellSize / 2,
              p.row * cellSize + cellSize / 2,
            ))
        .toList();

    // Draw each segment with a gradient that progresses along the path
    for (int i = 0; i < points.length - 1; i++) {
      final progress = i / (points.length - 1);
      final nextProgress = (i + 1) / (points.length - 1);

      final startColor = _pathColorAtProgress(progress);
      final endColor = _pathColorAtProgress(nextProgress);

      _drawTubeSegment(
        canvas,
        points[i],
        points[i + 1],
        tubeWidth,
        startColor,
        endColor,
      );
    }

    // Draw rounded end caps at path start and end
    _drawTubeEndCap(canvas, points.first, tubeWidth, _pathColorAtProgress(0));
    _drawTubeEndCap(canvas, points.last, tubeWidth, _pathColorAtProgress(1));

    // Draw rounded joints at turns
    for (int i = 1; i < points.length - 1; i++) {
      final progress = i / (points.length - 1);
      _drawTubeEndCap(canvas, points[i], tubeWidth, _pathColorAtProgress(progress));
    }
  }

  /// Gets the gradient color at a given progress (0.0 = start, 1.0 = end).
  Color _pathColorAtProgress(double t) {
    // Map to gradient: deep orange → orange → amber → yellow → bright yellow
    const colors = AppColors.pathGradientColors;
    if (colors.length < 2) return colors.first;

    final segmentCount = colors.length - 1;
    final segment = (t * segmentCount).floor().clamp(0, segmentCount - 1);
    final localT = (t * segmentCount - segment).clamp(0.0, 1.0);

    return Color.lerp(colors[segment], colors[segment + 1], localT)!;
  }

  /// Draws a single tube segment between two points.
  void _drawTubeSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    double width,
    Color startColor,
    Color endColor,
  ) {
    // Main tube body
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        start,
        end,
        [startColor, endColor],
      )
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, bodyPaint);

    // Offset highlight slightly to create tube illusion
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;

    // Perpendicular offset for highlight
    final nx = -dy / len * width * 0.12;
    final ny = dx / len * width * 0.12;
    final hStart = Offset(start.dx + nx, start.dy + ny);
    final hEnd = Offset(end.dx + nx, end.dy + ny);

    final innerHighlight = Paint()
      ..shader = ui.Gradient.linear(
        hStart,
        hEnd,
        [
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.15),
        ],
      )
      ..strokeWidth = width * 0.3
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    canvas.drawLine(hStart, hEnd, innerHighlight);

    // Outer glow
    final glowPaint = Paint()
      ..shader = ui.Gradient.linear(
        start,
        end,
        [
          startColor.withValues(alpha: 0.15),
          endColor.withValues(alpha: 0.15),
        ],
      )
      ..strokeWidth = width + 8
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(start, end, glowPaint);
  }

  /// Draws a rounded cap at a path point (for smooth joints).
  void _drawTubeEndCap(Canvas canvas, Offset center, double width, Color color) {
    final radius = width / 2;

    // Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius + 4, glowPaint);

    // Main cap
    final capPaint = Paint()..color = color;
    canvas.drawCircle(center, radius, capPaint);

    // Highlight on cap
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.15, center.dy - radius * 0.15),
      radius * 0.5,
      highlightPaint,
    );
  }

  /// Draws a waypoint circle with number.
  void _drawWaypoint(Canvas canvas, int row, int col) {
    Waypoint? wp;
    for (final w in gameState.puzzle.waypoints) {
      if (w.row == row && w.col == col) {
        wp = w;
        break;
      }
    }
    if (wp == null) return;

    final isVisited = gameState.path.any((p) => p.row == row && p.col == col);
    final isStart = wp.order == 1;
    final center = Offset(
      col * cellSize + cellSize / 2,
      row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.34;

    // Outer glow for visited waypoints
    if (isVisited) {
      final glowColor = isStart ? AppColors.waypointStartFill : Colors.white;
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius + 4, glowPaint);
    }

    // Waypoint circle fill
    Color fillColor;
    if (isStart) {
      fillColor = isVisited
          ? AppColors.waypointStartFill
          : AppColors.waypointStartFill.withValues(alpha: 0.7);
    } else {
      fillColor = isVisited
          ? AppColors.waypointFill
          : AppColors.waypointFill.withValues(alpha: 0.8);
    }

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center + const Offset(0, 1), radius, shadowPaint);

    // Main fill
    final circlePaint = Paint()..color = fillColor;
    canvas.drawCircle(center, radius, circlePaint);

    // Border ring
    final borderPaint = Paint()
      ..color = isStart
          ? AppColors.waypointStartBorder.withValues(alpha: 0.5)
          : AppColors.waypointBorder.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, borderPaint);

    // Waypoint number
    final textColor = isStart ? Colors.white : AppColors.waypointText;
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${wp.order}',
        style: TextStyle(
          color: textColor,
          fontSize: cellSize * 0.28,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  /// Draws the hint cell highlight.
  void _drawHintCell(Canvas canvas) {
    final hint = gameState.hintCell;
    if (hint == null) return;

    final center = Offset(
      hint.col * cellSize + cellSize / 2,
      hint.row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.35;

    // Outer glow (pulsing effect simulated by stronger blur)
    final glowPaint = Paint()
      ..color = AppColors.hintPurple.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, radius + 8, glowPaint);

    // Fill
    final circlePaint = Paint()
      ..color = AppColors.hintPurple.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, circlePaint);

    // Border ring
    final borderPaint = Paint()
      ..color = AppColors.hintPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.gameState != gameState;
  }
}
