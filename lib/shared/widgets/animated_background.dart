import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/motion.dart';

/// Animated mesh-like gradient background with slowly drifting color points.
///
/// Uses a CustomPainter with radial gradients to simulate a mesh gradient
/// without external dependencies. Falls back to a static gradient when
/// reduced motion is enabled or on older devices.
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({this.child, super.key});

  final Widget? child;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionUtils.shouldReduceMotion(context);
    final palette = context.palette;

    if (reduceMotion) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.meshBase,
              palette.isDark ? const Color(0xFF0D1420) : palette.meshColors[2],
              palette.meshBase,
            ],
          ),
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _MeshGradientPainter(
          progress: _controller.value,
          base: palette.meshBase,
          colors: palette.meshColors,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _MeshGradientPainter extends CustomPainter {
  _MeshGradientPainter({
    required this.progress,
    required this.base,
    required this.colors,
  });

  final double progress;

  /// Base fill and the 4 mesh control-point hues (deep navy/purple in the
  /// dark theme, pale tints in the light one).
  final Color base;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    // Fill with base color
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = base,
    );

    final t = progress * 2 * math.pi;

    // 4 slowly orbiting gradient points
    final points = [
      Offset(
        size.width * (0.2 + 0.1 * math.sin(t * 0.7)),
        size.height * (0.2 + 0.08 * math.cos(t * 0.5)),
      ),
      Offset(
        size.width * (0.8 + 0.1 * math.cos(t * 0.6)),
        size.height * (0.3 + 0.1 * math.sin(t * 0.4)),
      ),
      Offset(
        size.width * (0.3 + 0.12 * math.sin(t * 0.5 + 1)),
        size.height * (0.7 + 0.08 * math.cos(t * 0.6 + 2)),
      ),
      Offset(
        size.width * (0.7 + 0.08 * math.cos(t * 0.8 + 3)),
        size.height * (0.8 + 0.1 * math.sin(t * 0.3 + 1)),
      ),
    ];

    // Draw each point as a large soft radial gradient
    for (int i = 0; i < points.length; i++) {
      final radius = size.width * (0.5 + 0.1 * math.sin(t * 0.3 + i));
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: 0.6),
            colors[i].withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: points[i], radius: radius),
        );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MeshGradientPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.base != base;
  }
}
