import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'grid_palette.dart';

/// Draws the player's line: one continuous stroke with rounded corners, a
/// gradient running start -> head, a soft bloom underneath, and caps at both
/// ends.
///
/// Deliberately plain. The grid, the walls and the waypoint numbers must stay
/// readable at 8x8, so the line carries no texture or ornament; direction is
/// communicated by the gradient (dark at the start, bright at the head) and by
/// the head cap.
class PathRenderer {
  const PathRenderer({
    required this.cellSize,
    required this.palette,
    this.glowBreathValue = 0.0,
  });

  final double cellSize;
  final GridPalette palette;

  /// 0..1 breathing value used to modulate the bloom only.
  final double glowBreathValue;

  /// Stroke width. Keeps roughly half the cell clear on each side.
  double get strokeWidth => cellSize * 0.44;

  /// Corner radius where the line turns. Slightly under half the stroke so
  /// turns read as rounded rather than circular.
  double get _cornerRadius => math.min(cellSize * 0.32, strokeWidth * 0.9);

  /// [points] are cell centres in order. [segmentProgressGetter] returns 0..1
  /// for the segment ending at that index, so the newest segment can grow in.
  void paint(
    Canvas canvas,
    List<Offset> points,
    double Function(int index) segmentProgressGetter,
  ) {
    if (points.isEmpty) return;

    final effective = _effectivePoints(points, segmentProgressGetter);

    if (effective.length < 2) {
      _drawCap(canvas, effective.first, palette.pathStart, isHead: true);
      return;
    }

    final linePath = _roundedPath(effective);

    _drawGlow(canvas, linePath);
    _strokeAlongArcLength(canvas, linePath);

    if (palette.patterns) _drawPatternTicks(canvas, effective);

    _drawCap(canvas, effective.first, palette.pathStart, isHead: false);
    _drawCap(canvas, effective.last, palette.pathHead, isHead: true);
  }

  // ─── Geometry ───────────────────────────────────────────────────────

  /// The full path, with the final segment truncated to its animation progress.
  List<Offset> _effectivePoints(
    List<Offset> points,
    double Function(int index) segmentProgressGetter,
  ) {
    final result = <Offset>[points.first];
    for (var i = 1; i < points.length; i++) {
      final progress = segmentProgressGetter(i);
      if (progress < 1.0) {
        // Guard against a zero-length segment, which would make the rounded
        // path builder emit a degenerate corner.
        if (progress > 0.01) {
          result.add(Offset.lerp(points[i - 1], points[i], progress)!);
        }
        break;
      }
      result.add(points[i]);
    }
    return result;
  }

  /// Polyline with each interior corner replaced by a quadratic arc. Grid moves
  /// are axis-aligned, so this produces clean 90-degree rounded turns without
  /// the overshoot a Catmull-Rom spline would introduce.
  Path _roundedPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);

    for (var i = 1; i < pts.length - 1; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final next = pts[i + 1];

      final inLen = (curr - prev).distance;
      final outLen = (next - curr).distance;
      if (inLen == 0 || outLen == 0) continue;

      // Never eat more than half of either neighbouring segment.
      final r = math.min(_cornerRadius, math.min(inLen, outLen) / 2);

      final inDir = (curr - prev) / inLen;
      final outDir = (next - curr) / outLen;

      // Collinear: no corner to round.
      if ((inDir - outDir).distance < 0.001) {
        path.lineTo(curr.dx, curr.dy);
        continue;
      }

      final cornerStart = curr - inDir * r;
      final cornerEnd = curr + outDir * r;
      path.lineTo(cornerStart.dx, cornerStart.dy);
      path.quadraticBezierTo(
        curr.dx,
        curr.dy,
        cornerEnd.dx,
        cornerEnd.dy,
      );
    }

    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  /// Colour sampled at [t] (0 = start, 1 = head) across [GridPalette.pathGradient].
  Color _colorAt(double t) {
    final colors = palette.pathGradient;
    if (colors.length == 1) return colors.first;
    final clamped = t.clamp(0.0, 1.0);
    final scaled = clamped * (colors.length - 1);
    final i = scaled.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[i], colors[i + 1], scaled - i) ?? colors[i];
  }

  // ─── Layers ─────────────────────────────────────────────────────────

  /// Strokes the line in short pieces coloured by distance travelled.
  ///
  /// A single linear gradient between the first and last point collapses
  /// whenever the head loops back near the start: the ramp would span only the
  /// straight-line distance between the ends, clamping most of the line to the
  /// two extreme colours. Walking the arc length keeps the ramp proportional to
  /// how much of the path is drawn, which is what communicates progress.
  void _strokeAlongArcLength(Canvas canvas, Path linePath) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final metrics = linePath.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    if (total <= 0) return;

    // ~3 pieces per cell: fine enough to read as a smooth ramp, coarse enough
    // to stay cheap on an 8x8 board.
    final step = math.max(cellSize / 3, 4.0);
    var travelled = 0.0;

    for (final metric in metrics) {
      for (var d = 0.0; d < metric.length; d += step) {
        // Overlap slightly so consecutive pieces leave no seam.
        final end = math.min(d + step + 0.75, metric.length);
        paint.color = _colorAt((travelled + d) / total);
        canvas.drawPath(metric.extractPath(d, end), paint);
      }
      travelled += metric.length;
    }
  }

  void _drawGlow(Canvas canvas, Path linePath) {
    final breath = 0.85 + 0.15 * glowBreathValue;
    canvas.drawPath(
      linePath,
      Paint()
        ..color = palette.pathGlow
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.55 * breath
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.13)
        ..isAntiAlias = true,
    );
  }

  void _drawCap(Canvas canvas, Offset at, Color color, {required bool isHead}) {
    final radius = strokeWidth * (isHead ? 0.62 : 0.5);
    if (isHead) {
      canvas.drawCircle(
        at,
        radius * 1.6,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.1),
      );
    }
    canvas.drawCircle(at, radius, Paint()..color = color);
  }

  /// Colourblind modes: short perpendicular ticks give the line a texture cue
  /// that does not depend on hue.
  void _drawPatternTicks(Canvas canvas, List<Offset> pts) {
    final paint = Paint()
      ..color = palette.patternOverlay
      ..strokeWidth = math.max(1.0, cellSize * 0.035)
      ..strokeCap = StrokeCap.round;
    final half = strokeWidth * 0.3;

    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final len = (b - a).distance;
      if (len < 1) continue;
      final dir = (b - a) / len;
      final normal = Offset(-dir.dy, dir.dx);
      final mid = Offset.lerp(a, b, 0.5)!;
      canvas.drawLine(mid - normal * half, mid + normal * half, paint);
    }
  }
}
