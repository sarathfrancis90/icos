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
                isDark: Theme.of(context).brightness == Brightness.dark,
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
    required this.isDark,
  });

  final GameState gameState;
  final double cellSize;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final gridSize = gameState.puzzle.gridSize;

    // Draw grid background
    _drawGridBackground(canvas, size);

    // Draw grid lines
    _drawGridLines(canvas, size, gridSize);

    // Draw cells
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        _drawCell(canvas, row, col);
      }
    }

    // Draw hint cell highlight
    _drawHintCell(canvas);

    // Draw path connections
    _drawPath(canvas);
  }

  void _drawGridBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark ? AppColors.deepNavy : AppColors.lightBackground;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(AppSizes.radiusMd),
      ),
      paint,
    );
  }

  void _drawGridLines(Canvas canvas, Size size, int gridSize) {
    final paint = Paint()
      ..color = isDark ? AppColors.gridLine : AppColors.gridLineLight
      ..strokeWidth = 1;

    for (int i = 0; i <= gridSize; i++) {
      final offset = i * cellSize;
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, offset),
        Offset(size.width, offset),
        paint,
      );
    }
  }

  void _drawCell(Canvas canvas, int row, int col) {
    final cellState = gameState.grid[row][col];
    final rect = Rect.fromLTWH(
      col * cellSize + 1,
      row * cellSize + 1,
      cellSize - 2,
      cellSize - 2,
    );

    switch (cellState) {
      case CellState.wall:
        final paint = Paint()..color = AppColors.wallFill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          paint,
        );

      case CellState.waypoint:
        _drawWaypoint(canvas, row, col, rect);

      case CellState.filled:
        final isInPath = gameState.path.any(
          (p) => p.row == row && p.col == col,
        );
        if (isInPath) {
          final paint = Paint()
            ..color = AppColors.pathFill.withValues(alpha: 0.3);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            paint,
          );
        }

      case CellState.empty:
        break;
    }
  }

  void _drawWaypoint(Canvas canvas, int row, int col, Rect rect) {
    // Find waypoint data
    Waypoint? wp;
    for (final w in gameState.puzzle.waypoints) {
      if (w.row == row && w.col == col) {
        wp = w;
        break;
      }
    }
    if (wp == null) return;

    final isVisited = gameState.path.any(
      (p) => p.row == row && p.col == col,
    );

    // Draw waypoint circle
    final center = Offset(
      col * cellSize + cellSize / 2,
      row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.35;

    final circlePaint = Paint()
      ..color = isVisited
          ? AppColors.coralOrange
          : AppColors.coralOrange.withValues(alpha: 0.6);
    canvas.drawCircle(center, radius, circlePaint);

    // Draw waypoint number
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${wp.order}',
        style: TextStyle(
          color: Colors.white,
          fontSize: cellSize * 0.3,
          fontWeight: FontWeight.w700,
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

  void _drawHintCell(Canvas canvas) {
    final hint = gameState.hintCell;
    if (hint == null) return;

    final center = Offset(
      hint.col * cellSize + cellSize / 2,
      hint.row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.35;

    // Draw outer glow
    final glowPaint = Paint()
      ..color = AppColors.hintPurple.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius + 6, glowPaint);

    // Draw hint circle
    final circlePaint = Paint()
      ..color = AppColors.hintPurple.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, circlePaint);

    // Draw border ring
    final borderPaint = Paint()
      ..color = AppColors.hintPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, borderPaint);
  }

  void _drawPath(Canvas canvas) {
    if (gameState.path.length < 2) return;

    final paint = Paint()
      ..color = AppColors.pathFill
      ..strokeWidth = cellSize * 0.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final first = gameState.path.first;
    path.moveTo(
      first.col * cellSize + cellSize / 2,
      first.row * cellSize + cellSize / 2,
    );

    for (int i = 1; i < gameState.path.length; i++) {
      final pos = gameState.path[i];
      path.lineTo(
        pos.col * cellSize + cellSize / 2,
        pos.row * cellSize + cellSize / 2,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.gameState != gameState;
  }
}
