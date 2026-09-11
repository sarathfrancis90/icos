import 'dart:math' as math;
import 'dart:ui' as ui;

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
    final shader = _gradientShader(effective);

    _drawGlow(canvas, linePath);

    canvas.drawPath(
      linePath,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

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

  /// Gradient along the dominant axis of the line so the ramp reads as
  /// start -> head rather than as an arbitrary screen-space wash.
  ui.Shader _gradientShader(List<Offset> pts) {
    final from = pts.first;
    final to = pts.last;
    // Degenerate when the line doubles back exactly; nudge so the shader is valid.
    final end = (to - from).distance < 1.0 ? from + const Offset(1, 1) : to;
    return ui.Gradient.linear(
      from,
      end,
      palette.pathGradient,
      _evenStops(palette.pathGradient.length),
    );
  }

  List<double> _evenStops(int n) =>
      [for (var i = 0; i < n; i++) n == 1 ? 0.0 : i / (n - 1)];

  // ─── Layers ─────────────────────────────────────────────────────────

  void _drawGlow(Canvas canvas, Path linePath) {
    final breath = 0.85 + 0.15 * glowBreathValue;
    canvas.drawPath(
      linePath,
      Paint()
        ..color = palette.pathGlow
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.9 * breath
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.18)
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
