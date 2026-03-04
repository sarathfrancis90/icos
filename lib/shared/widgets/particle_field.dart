import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/motion.dart';

/// Ambient floating particle system for atmospheric depth.
///
/// 15-20 particles drift slowly with sin-wave wobble, barely visible.
/// Hidden entirely when reduced motion is enabled.
class ParticleField extends StatefulWidget {
  const ParticleField({super.key});

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _random = math.Random();

  static const _particleCount = 18;

  @override
  void initState() {
    super.initState();
    _particles = List.generate(_particleCount, (_) => _generateParticle());
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )
      ..addListener(_tick)
      ..repeat();
  }

  _Particle _generateParticle() {
    return _Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      size: 1.0 + _random.nextDouble() * 2.0,
      alpha: 0.03 + _random.nextDouble() * 0.05,
      speed: 0.0002 + _random.nextDouble() * 0.0004,
      wobbleOffset: _random.nextDouble() * math.pi * 2,
      wobbleAmplitude: 0.001 + _random.nextDouble() * 0.002,
    );
  }

  void _tick() {
    for (final p in _particles) {
      p.y -= p.speed;
      p.x += math.sin(p.y * 20 + p.wobbleOffset) * p.wobbleAmplitude;

      // Wrap around
      if (p.y < -0.05) {
        p.y = 1.05;
        p.x = _random.nextDouble();
      }
      if (p.x < -0.05) p.x = 1.05;
      if (p.x > 1.05) p.x = -0.05;
    }
    // CustomPaint repaints via animation listener
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionUtils.shouldReduceMotion(context)) {
      return const SizedBox.expand();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ParticlePainter(_particles),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.alpha,
    required this.speed,
    required this.wobbleOffset,
    required this.wobbleAmplitude,
  });

  double x;
  double y;
  final double size;
  final double alpha;
  final double speed;
  final double wobbleOffset;
  final double wobbleAmplitude;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.particles);

  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: p.alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
