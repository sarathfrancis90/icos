import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Premium snake renderer using overlapping circles with radial gradients.
///
/// Inspired by Slither.io's visual technique: the body is a series of
/// overlapping filled circles drawn back-to-front, each with a radial
/// gradient that simulates 3D spheroid lighting.
class SnakeRenderer {
  SnakeRenderer({
    required this.cellSize,
    this.glowBreathValue = 0.5,
    this.eatingProgress = -1.0,
    this.eatingSegmentIndex = -1,
    this.idleBlinkProgress = -1.0,
    this.tongueProgress = -1.0,
    this.invalidLungeOffset = Offset.zero,
  });

  final double cellSize;
  final double glowBreathValue;
  final double eatingProgress;
  final int eatingSegmentIndex;
  final double idleBlinkProgress;
  final double tongueProgress;
  final Offset invalidLungeOffset;

  /// Renders the complete snake given path points and segment progress.
  void paint(
    Canvas canvas,
    List<Offset> points,
    double Function(int index) segmentProgressGetter,
  ) {
    if (points.isEmpty) return;

    // Single cell — just draw the head
    if (points.length == 1) {
      _drawSnakeHead(canvas, points.first, 0, points);
      return;
    }

    // Build the effective points list with segment animation
    final effectivePoints = <Offset>[points.first];
    for (int i = 1; i < points.length; i++) {
      final progress = segmentProgressGetter(i);
      if (progress < 1.0) {
        effectivePoints.add(
          Offset.lerp(points[i - 1], points[i], progress)!,
        );
        break;
      }
      effectivePoints.add(points[i]);
    }

    if (effectivePoints.length < 2) {
      _drawSnakeHead(canvas, effectivePoints.first, 0, effectivePoints);
      return;
    }

    // Generate smooth spline path through all points
    final splinePoints = _generateSplinePath(effectivePoints);

    if (splinePoints.length < 2) {
      _drawSnakeHead(canvas, effectivePoints.last,
          effectivePoints.length - 1, effectivePoints);
      return;
    }

    // Render layers back-to-front for premium depth
    // 1. Per-segment ground shadows
    _drawGroundShadows(canvas, splinePoints);

    // 2. Outer glow (wide, faint neon bloom)
    _drawOuterGlow(canvas, splinePoints);

    // 3. Inner glow (tight, brighter neon tube)
    _drawInnerGlow(canvas, splinePoints);

    // 4. Body circles with radial gradients
    _drawBodyCircles(canvas, splinePoints);

    // 5. Scale crescent shadows
    _drawScaleShadows(canvas, splinePoints);

    // 6. Belly highlight line
    _drawBellyHighlight(canvas, splinePoints);

    // 7. Eating bulge overlay
    if (eatingProgress >= 0 && eatingSegmentIndex >= 0) {
      _drawEatingBulge(canvas, splinePoints);
    }

    // 8. Tail tip
    _drawSnakeTail(canvas, splinePoints);

    // 9-11. Head + features + tongue
    _drawSnakeHead(canvas, effectivePoints.last,
        effectivePoints.length - 1, effectivePoints);
  }

  // ─── Spline Generation ──────────────────────────────────────────

  List<Offset> _generateSplinePath(List<Offset> controlPoints) {
    if (controlPoints.length < 2) return controlPoints;

    if (controlPoints.length == 2) {
      final result = <Offset>[];
      const steps = 12;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        result.add(Offset.lerp(controlPoints[0], controlPoints[1], t)!);
      }
      return result;
    }

    final result = <Offset>[];
    const stepsPerSegment = 10;

    for (int seg = 0; seg < controlPoints.length - 1; seg++) {
      final p0 = seg > 0 ? controlPoints[seg - 1] : controlPoints[0];
      final p1 = controlPoints[seg];
      final p2 = controlPoints[seg + 1];
      final p3 = seg + 2 < controlPoints.length
          ? controlPoints[seg + 2]
          : controlPoints.last;

      for (int i = 0; i <= stepsPerSegment; i++) {
        if (seg > 0 && i == 0) continue;
        final t = i / stepsPerSegment;
        result.add(_catmullRom(p0, p1, p2, p3, t));
      }
    }

    return result;
  }

  Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;

    final x = 0.5 *
        ((2 * p1.dx) +
            (-p0.dx + p2.dx) * t +
            (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
            (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);
    final y = 0.5 *
        ((2 * p1.dy) +
            (-p0.dy + p2.dy) * t +
            (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
            (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);

    return Offset(x, y);
  }

  // ─── Layer 1: Ground Shadows ──────────────────────────────────

  void _drawGroundShadows(Canvas canvas, List<Offset> splinePoints) {
    final maxRadius = cellSize * 0.24;
    final total = splinePoints.length;
    const shadowOffset = Offset(2, 3);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Draw every 2nd point for performance
    for (int i = 0; i < total; i += 2) {
      final t = i / (total - 1); // 0 = tail, 1 = head
      final radius = maxRadius * (0.45 + 0.55 * t);
      canvas.drawCircle(splinePoints[i] + shadowOffset, radius, shadowPaint);
    }
  }

  // ─── Layer 2: Outer Glow ──────────────────────────────────────

  void _drawOuterGlow(Canvas canvas, List<Offset> splinePoints) {
    if (splinePoints.length < 2) return;

    final bodyWidth = cellSize * 0.48;
    final breathAlpha = 0.08 + glowBreathValue * 0.10;

    final path = Path()..moveTo(splinePoints[0].dx, splinePoints[0].dy);
    for (int i = 1; i < splinePoints.length; i++) {
      path.lineTo(splinePoints[i].dx, splinePoints[i].dy);
    }

    final glowPaint = Paint()
      ..color = AppColors.snakeGlowOuter.withValues(alpha: breathAlpha)
      ..strokeWidth = bodyWidth + 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawPath(path, glowPaint);
  }

  // ─── Layer 3: Inner Glow ──────────────────────────────────────

  void _drawInnerGlow(Canvas canvas, List<Offset> splinePoints) {
    if (splinePoints.length < 2) return;

    final bodyWidth = cellSize * 0.48;
    final breathAlpha = 0.15 + glowBreathValue * 0.12;

    final path = Path()..moveTo(splinePoints[0].dx, splinePoints[0].dy);
    for (int i = 1; i < splinePoints.length; i++) {
      path.lineTo(splinePoints[i].dx, splinePoints[i].dy);
    }

    final glowPaint = Paint()
      ..color = AppColors.snakeGlowInner.withValues(alpha: breathAlpha)
      ..strokeWidth = bodyWidth + 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);
  }

  // ─── Layer 4: Body Circles with Radial Gradients ──────────────

  void _drawBodyCircles(Canvas canvas, List<Offset> splinePoints) {
    final maxRadius = cellSize * 0.24;
    final total = splinePoints.length;

    // Draw circles from tail to head (back-to-front overlap)
    for (int i = 0; i < total; i++) {
      final t = i / (total - 1); // 0 = tail, 1 = head

      // Taper: thick at head, thin at tail
      final radius = maxRadius * (0.45 + 0.55 * t);

      // Organic breathing variation
      final breathe =
          1.0 + math.sin(i * 0.8 + glowBreathValue * math.pi * 2) * 0.04;
      final finalRadius = radius * breathe;

      // Eating bulge: inflate segments near the bulge
      double eatInflate = 1.0;
      if (eatingProgress >= 0 && eatingProgress < 1.0) {
        final bulgeCenter = total * (1.0 - eatingProgress * 0.6);
        final dist = (i - bulgeCenter).abs();
        if (dist < 5) {
          final eatCurve = math.sin(eatingProgress * math.pi);
          eatInflate = 1.0 + 0.25 * eatCurve * (1.0 - dist / 5);
        }
      }

      final r = finalRadius * eatInflate;
      final point = splinePoints[i];

      // Get the base body color at this position
      final baseColor = _snakeColorAt(t);
      final highlightColor = Color.lerp(
        baseColor,
        AppColors.snakeSegmentHighlight,
        0.4,
      )!;
      final shadowColor = Color.lerp(
        baseColor,
        AppColors.snakeSegmentShadow,
        0.5,
      )!;

      // Radial gradient for 3D spheroid lighting (lit from upper-left)
      final gradientCenter = Offset(point.dx - r * 0.3, point.dy - r * 0.3);

      final gradient = ui.Gradient.radial(
        gradientCenter,
        r * 1.2,
        [highlightColor, baseColor, shadowColor],
        [0.0, 0.5, 1.0],
      );

      final bodyPaint = Paint()..shader = gradient;
      canvas.drawCircle(point, r, bodyPaint);

      // Subtle dark edge ring for definition (every other circle)
      if (i % 2 == 0) {
        final edgePaint = Paint()
          ..color = shadowColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        canvas.drawCircle(point, r, edgePaint);
      }
    }
  }

  // ─── Layer 5: Scale Crescent Shadows ──────────────────────────

  void _drawScaleShadows(Canvas canvas, List<Offset> splinePoints) {
    if (splinePoints.length < 6) return;

    final maxRadius = cellSize * 0.24;
    final total = splinePoints.length;

    for (int i = 3; i < total - 3; i += 4) {
      final t = i / (total - 1);
      final radius = maxRadius * (0.45 + 0.55 * t);

      if (radius < 3) continue;

      final prev = splinePoints[i - 1];
      final next = splinePoints[i + 1];

      final dx = next.dx - prev.dx;
      final dy = next.dy - prev.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.1) continue;

      final angle = math.atan2(dy, dx);

      final scalePaint = Paint()
        ..color =
            AppColors.snakeSegmentShadow.withValues(alpha: 0.12 + 0.08 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;

      canvas.save();
      canvas.translate(splinePoints[i].dx, splinePoints[i].dy);
      canvas.rotate(angle);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius * 0.7),
        math.pi * 0.7,
        math.pi * 0.6,
        false,
        scalePaint,
      );
      canvas.restore();

      // Dorsal stripe mark every 8th point
      if (i % 8 == 0) {
        final dorsalPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(splinePoints[i], radius * 0.2, dorsalPaint);
      }
    }
  }

  // ─── Layer 6: Belly Highlight ─────────────────────────────────

  void _drawBellyHighlight(Canvas canvas, List<Offset> splinePoints) {
    if (splinePoints.length < 4) return;

    final total = splinePoints.length;

    for (int i = 1; i < total - 1; i += 2) {
      final t = i / (total - 1);
      final prev = splinePoints[i - 1];
      final next = splinePoints[math.min(i + 1, total - 1)];

      final highlightPaint = Paint()
        ..color =
            AppColors.snakeBellyHighlight.withValues(alpha: 0.08 + 0.06 * t)
        ..strokeWidth = cellSize * 0.04
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final dx = next.dx - prev.dx;
      final dy = next.dy - prev.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.1) continue;

      final nx = -dy / len;
      final ny = dx / len;
      final offset = Offset(nx * cellSize * 0.06, ny * cellSize * 0.06);

      canvas.drawLine(
        splinePoints[i] + offset,
        splinePoints[math.min(i + 1, total - 1)] + offset,
        highlightPaint,
      );
    }
  }

  // ─── Layer 7: Eating Bulge ────────────────────────────────────

  void _drawEatingBulge(Canvas canvas, List<Offset> splinePoints) {
    if (eatingProgress < 0 || splinePoints.length < 3) return;

    final totalLen = splinePoints.length - 1;
    final bulgePos = totalLen * (1.0 - eatingProgress * 0.6);
    final idx = bulgePos.floor().clamp(0, totalLen);
    final point = splinePoints[idx];

    final maxRadius = cellSize * 0.24;
    final t = idx / (splinePoints.length - 1);
    final baseRadius = maxRadius * (0.45 + 0.55 * t);

    final bulgeIntensity = math.sin(eatingProgress * math.pi);
    final bulgeRadius = baseRadius * (1.0 + 0.35 * bulgeIntensity);

    if (bulgeIntensity < 0.05) return;

    // Bright glow at bulge position
    final bulgePaint = Paint()
      ..color =
          AppColors.snakeHeadBright.withValues(alpha: 0.35 * bulgeIntensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(point, bulgeRadius, bulgePaint);

    // White flash ring
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2 * bulgeIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(point, bulgeRadius * 1.2, ringPaint);
  }

  // ─── Layer 8: Tail Tip ────────────────────────────────────────

  void _drawSnakeTail(Canvas canvas, List<Offset> splinePoints) {
    if (splinePoints.length < 3) return;

    final tailEnd = splinePoints.first;
    final tailNext = splinePoints[1];

    final dx = tailEnd.dx - tailNext.dx;
    final dy = tailEnd.dy - tailNext.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.1) return;

    final tipLength = cellSize * 0.15;
    final tip = Offset(
      tailEnd.dx + (dx / len) * tipLength,
      tailEnd.dy + (dy / len) * tipLength,
    );

    // Tapered tail: draw 3 circles getting smaller
    final tailRadius = cellSize * 0.10;
    for (int i = 0; i < 3; i++) {
      final tt = i / 3.0;
      final r = tailRadius * (1.0 - tt * 0.6);
      final p = Offset.lerp(tailEnd, tip, tt)!;
      final paint = Paint()
        ..color = AppColors.snakeBodyEnd.withValues(alpha: 1.0 - tt * 0.4);
      canvas.drawCircle(p, r, paint);
    }
  }

  // ─── Layer 9-11: Head ─────────────────────────────────────────

  void _drawSnakeHead(
      Canvas canvas, Offset headPos, int headIndex, List<Offset> points) {
    final headRadius = cellSize * 0.27;

    double angle = 0;
    if (points.length >= 2) {
      final prev = points[headIndex > 0 ? headIndex - 1 : 0];
      angle = math.atan2(headPos.dy - prev.dy, headPos.dx - prev.dx);
    }

    final adjustedHead = headPos + invalidLungeOffset;

    canvas.save();
    canvas.translate(adjustedHead.dx, adjustedHead.dy);
    canvas.rotate(angle);

    // Eating jaw animation
    double jawWidthScale = 1.0;
    double jawLengthScale = 1.0;
    if (eatingProgress >= 0 && eatingProgress < 0.25) {
      final chompT = eatingProgress / 0.25;
      jawWidthScale = 1.0 + 0.15 * math.sin(chompT * math.pi);
      jawLengthScale = 1.0 - 0.08 * math.sin(chompT * math.pi);
    }

    // Head shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(2, 3);
    canvas.drawPath(
      _headPath(headRadius * jawWidthScale, headRadius * jawLengthScale),
      shadowPaint,
    );
    canvas.restore();

    // Head neon glow
    final headGlowPaint = Paint()
      ..color = AppColors.snakeGlowInner.withValues(
          alpha: 0.20 + glowBreathValue * 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      _headPath(headRadius * jawWidthScale * 1.15,
          headRadius * jawLengthScale * 1.15),
      headGlowPaint,
    );

    // Head body with gradient
    final headPath = _headPath(
        headRadius * jawWidthScale, headRadius * jawLengthScale);
    final headGradient = ui.Gradient.radial(
      Offset(-headRadius * 0.2, -headRadius * 0.25),
      headRadius * 2.0,
      [
        AppColors.snakeHeadHighlight,
        AppColors.snakeHeadBright,
        AppColors.snakeBodyStart,
      ],
      [0.0, 0.4, 1.0],
    );
    final headPaint = Paint()..shader = headGradient;
    canvas.drawPath(headPath, headPaint);

    // Head top highlight sheen
    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-headRadius * 0.1, -headRadius * 0.2),
        width: headRadius * 1.0,
        height: headRadius * 0.5,
      ),
      sheenPaint,
    );

    // Central ridge line
    final ridgePaint = Paint()
      ..color = AppColors.snakeBodyMid.withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(-headRadius * 0.3, 0),
      Offset(headRadius * 0.8 * jawLengthScale, 0),
      ridgePaint,
    );

    // Nostrils
    final nostrilPaint = Paint()
      ..color = AppColors.snakeBodyMid.withValues(alpha: 0.5);
    final nostrilX = headRadius * 0.75 * jawLengthScale;
    canvas.drawCircle(
      Offset(nostrilX, -headRadius * 0.18),
      headRadius * 0.05,
      nostrilPaint,
    );
    canvas.drawCircle(
      Offset(nostrilX, headRadius * 0.18),
      headRadius * 0.05,
      nostrilPaint,
    );

    // Tongue
    if (tongueProgress >= 0) {
      _drawTongue(canvas, headRadius * jawLengthScale);
    }

    // Eyes
    _drawEyes(canvas, headRadius, jawWidthScale);

    // Crown scales
    _drawCrownScales(canvas, headRadius);

    canvas.restore();
  }

  /// Shield/kite-shaped head path — wide at back, narrowing to blunted front.
  Path _headPath(double widthRadius, double lengthRadius) {
    final path = Path();
    path.moveTo(-widthRadius * 0.85, 0);
    path.cubicTo(
      -widthRadius * 0.85, -widthRadius * 0.78,
      lengthRadius * 0.3, -widthRadius * 0.55,
      lengthRadius * 1.0, 0,
    );
    path.cubicTo(
      lengthRadius * 0.3, widthRadius * 0.55,
      -widthRadius * 0.85, widthRadius * 0.78,
      -widthRadius * 0.85, 0,
    );
    path.close();
    return path;
  }

  /// Slit-pupil eyes with dual catchlights.
  void _drawEyes(Canvas canvas, double headRadius, double jawWidthScale) {
    final eyeOffsetX = headRadius * 0.35;
    final eyeOffsetY = headRadius * 0.38 * jawWidthScale;
    final eyeRadius = headRadius * 0.32;
    final pupilWidth = headRadius * 0.12;
    final pupilHeight = headRadius * 0.28;

    for (final side in [-1.0, 1.0]) {
      final eyeCenter = Offset(eyeOffsetX, side * eyeOffsetY);

      // Eye glow halo
      final eyeGlowPaint = Paint()
        ..color = AppColors.snakeHeadBright.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(eyeCenter, eyeRadius * 1.3, eyeGlowPaint);

      // Eye sclera
      final eyeWhitePaint = Paint()..color = AppColors.snakeEye;
      canvas.drawCircle(eyeCenter, eyeRadius, eyeWhitePaint);

      // Slit pupil (vertical ellipse)
      final pupilCenter = Offset(
        eyeCenter.dx + pupilWidth * 0.15,
        eyeCenter.dy,
      );
      final pupilPaint = Paint()..color = AppColors.snakePupil;
      canvas.drawOval(
        Rect.fromCenter(
          center: pupilCenter,
          width: pupilWidth,
          height: pupilHeight,
        ),
        pupilPaint,
      );

      // Primary catchlight (upper-left)
      final shinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(
        Offset(eyeCenter.dx - pupilWidth * 0.4,
            eyeCenter.dy - pupilHeight * 0.2),
        pupilWidth * 0.35,
        shinePaint,
      );

      // Secondary catchlight (lower-right)
      final shine2Paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.4);
      canvas.drawCircle(
        Offset(eyeCenter.dx + pupilWidth * 0.5,
            eyeCenter.dy + pupilHeight * 0.3),
        pupilWidth * 0.18,
        shine2Paint,
      );

      // Blink lid
      if (idleBlinkProgress >= 0) {
        final lidClose = idleBlinkProgress;
        if (lidClose > 0.01) {
          canvas.save();
          canvas.clipRect(Rect.fromLTRB(
            eyeCenter.dx - eyeRadius * 1.1,
            eyeCenter.dy - eyeRadius * 1.1,
            eyeCenter.dx + eyeRadius * 1.1,
            eyeCenter.dy - eyeRadius * 1.1 + eyeRadius * 2.2 * lidClose,
          ));
          final lidPaint = Paint()..color = AppColors.snakeHeadBright;
          canvas.drawCircle(eyeCenter, eyeRadius + 1, lidPaint);
          canvas.restore();
        }
      }
    }
  }

  /// Crown scales at the back of the head.
  void _drawCrownScales(Canvas canvas, double headRadius) {
    final crownPaint = Paint()
      ..color = AppColors.snakeHeadHighlight.withValues(alpha: 0.25);

    for (int i = -1; i <= 1; i++) {
      final y = i * headRadius * 0.28;
      canvas.drawCircle(
        Offset(-headRadius * 0.65, y),
        headRadius * 0.07,
        crownPaint,
      );
    }
  }

  /// Forked tongue.
  void _drawTongue(Canvas canvas, double headLength) {
    final tongueLen = headLength * 0.9 * _tongueExtension();
    if (tongueLen < 1) return;

    final tongueStart = Offset(headLength * 0.95, 0);
    final tongueMid = Offset(tongueStart.dx + tongueLen * 0.6, 0);
    final forkSpread = tongueLen * 0.25;

    final tonguePaint = Paint()
      ..color = AppColors.snakeTongue
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(tongueStart, tongueMid, tonguePaint);

    final forkEnd1 = Offset(
      tongueMid.dx + tongueLen * 0.4,
      tongueMid.dy - forkSpread,
    );
    final forkEnd2 = Offset(
      tongueMid.dx + tongueLen * 0.4,
      tongueMid.dy + forkSpread,
    );
    canvas.drawLine(tongueMid, forkEnd1, tonguePaint);
    canvas.drawLine(tongueMid, forkEnd2, tonguePaint);
  }

  double _tongueExtension() {
    if (tongueProgress < 0) return 0;
    if (tongueProgress < 0.3) return tongueProgress / 0.3;
    if (tongueProgress < 0.7) return 1.0;
    return (1.0 - tongueProgress) / 0.3;
  }

  // ─── Color Utilities ──────────────────────────────────────────

  Color _snakeColorAt(double t) {
    const colors = AppColors.snakeGradientColors;
    if (colors.length < 2) return colors.first;

    final segCount = colors.length - 1;
    final seg = (t * segCount).floor().clamp(0, segCount - 1);
    final localT = (t * segCount - seg).clamp(0.0, 1.0);

    return Color.lerp(colors[seg], colors[seg + 1], localT)!;
  }
}
