import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/motion.dart';
import '../../../shared/widgets/spring_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _titles = [
    'Welcome to Icos',
    'One Puzzle Per Day',
    'Compete with Friends',
  ];

  static const _descriptions = [
    'Guide the snake through the grid, eating numbered waypoints in order while filling every cell. Feed the path!',
    'A new puzzle every day at midnight UTC. Same puzzle for everyone worldwide. Difficulty scales Monday to Sunday.',
    'Create or join groups to see daily and weekly leaderboards. Challenge your friends and family!',
  ];

  static const _gradients = [
    [AppColors.snakeBodyStart, AppColors.snakeHeadBright],
    [AppColors.snakeBodyMid, AppColors.snakeHeadBright],
    [AppColors.success, AppColors.electricBlue],
  ];

  void _onNext() {
    if (_currentPage < _titles.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await StorageService.setHasSeenOnboarding(true);
    if (mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: AppSizes.md,
                  top: AppSizes.sm,
                ),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _titles.length,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (context, index) => _OnboardingPage(
                  title: _titles[index],
                  description: _descriptions[index],
                  gradientColors: _gradients[index],
                  isActive: _currentPage == index,
                  pageIndex: index,
                ),
              ),
            ),

            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _titles.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin:
                      const EdgeInsetsDirectional.symmetric(horizontal: 4),
                  width: _currentPage == index ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: _currentPage == index
                        ? AppColors.purpleButtonGradient
                        : null,
                    color: _currentPage == index
                        ? null
                        : AppColors.cellBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),

            // Next/Get Started button — purple gradient with spring
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSizes.lg,
              ),
              child: SpringButton(
                onPressed: _onNext,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.purpleButtonGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.purpleGlow,
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _currentPage == _titles.length - 1
                          ? 'Get Started'
                          : 'Next',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.xl),
          ],
        ),
      ),
    );
  }
}

/// Phase 12: Animated onboarding page with CustomPainter illustrations.
class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({
    required this.title,
    required this.description,
    required this.gradientColors,
    required this.isActive,
    required this.pageIndex,
  });

  final String title;
  final String description;
  final List<Color> gradientColors;
  final bool isActive;
  final int pageIndex;

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isActive) {
      _animController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _OnboardingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionUtils.shouldReduceMotion(context);

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSizes.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated illustration
          SizedBox(
            width: 120,
            height: 120,
            child: AnimatedBuilder(
              animation: reduceMotion
                  ? const AlwaysStoppedAnimation(1.0)
                  : _animController,
              builder: (context, _) => CustomPaint(
                painter: _OnboardingIllustrationPainter(
                  pageIndex: widget.pageIndex,
                  progress: reduceMotion ? 1.0 : _animController.value,
                  colors: widget.gradientColors,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text(
            widget.title,
            // Onboarding always renders on the dark backdrop, so pin the
            // title colour instead of inheriting the (possibly light) theme.
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(color: AppColors.textPrimaryDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            widget.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondaryDark,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Custom painter for animated onboarding illustrations.
class _OnboardingIllustrationPainter extends CustomPainter {
  _OnboardingIllustrationPainter({
    required this.pageIndex,
    required this.progress,
    required this.colors,
  });

  final int pageIndex;
  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    // Background glow circle
    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.15 * progress);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      glowPaint,
    );

    switch (pageIndex) {
      case 0:
        _drawPathGrid(canvas, size);
      case 1:
        _drawCalendar(canvas, size);
      case 2:
        _drawAvatars(canvas, size);
    }
  }

  /// Page 1: Mini path animates through a 3x3 grid.
  void _drawPathGrid(Canvas canvas, Size size) {
    final cellSize = size.width / 5;
    final gridOffset = Offset(cellSize, cellSize);

    // Draw 3x3 grid cells
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final rect = Rect.fromLTWH(
          gridOffset.dx + c * cellSize,
          gridOffset.dy + r * cellSize,
          cellSize - 2,
          cellSize - 2,
        );
        final cellPaint = Paint()
          ..color = AppColors.cellBackground.withValues(alpha: 0.8 * progress);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          cellPaint,
        );
      }
    }

    // Animated path: moves through grid cells
    final pathPoints = [
      Offset(0, 0), Offset(1, 0), Offset(2, 0),
      Offset(2, 1), Offset(1, 1), Offset(0, 1),
      Offset(0, 2), Offset(1, 2), Offset(2, 2),
    ];

    final visibleCount = (pathPoints.length * progress).ceil();
    if (visibleCount < 2) return;

    final pathPaint = Paint()
      ..color = colors.first
      ..strokeWidth = cellSize * 0.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < visibleCount - 1; i++) {
      final start = Offset(
        gridOffset.dx + pathPoints[i].dx * cellSize + cellSize / 2 - 1,
        gridOffset.dy + pathPoints[i].dy * cellSize + cellSize / 2 - 1,
      );

      double segProgress = 1.0;
      if (i == visibleCount - 2) {
        segProgress = (progress * pathPoints.length - i).clamp(0.0, 1.0);
      }

      final end = Offset(
        gridOffset.dx + pathPoints[i + 1].dx * cellSize + cellSize / 2 - 1,
        gridOffset.dy + pathPoints[i + 1].dy * cellSize + cellSize / 2 - 1,
      );
      final interpolatedEnd = Offset.lerp(start, end, segProgress)!;
      canvas.drawLine(start, interpolatedEnd, pathPaint);
    }
  }

  /// Page 2: Calendar cells fill in one by one.
  void _drawCalendar(Canvas canvas, Size size) {
    final cellSize = size.width / 6;
    final offset = Offset(cellSize * 0.5, cellSize * 0.8);

    // 5x5 calendar grid
    final totalCells = 25;
    final filledCount = (totalCells * progress).ceil();

    for (int i = 0; i < totalCells; i++) {
      final r = i ~/ 5;
      final c = i % 5;
      final rect = Rect.fromLTWH(
        offset.dx + c * cellSize,
        offset.dy + r * cellSize,
        cellSize - 2,
        cellSize - 2,
      );

      final isFilled = i < filledCount;
      final cellColor = isFilled
          ? Color.lerp(colors.first, colors.last, i / totalCells)!
          : AppColors.cellBackground;

      final paint = Paint()
        ..color = cellColor.withValues(alpha: isFilled ? 0.8 : 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );

      // Checkmark on filled cells
      if (isFilled && progress > i / totalCells) {
        final checkPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        final cx = rect.center.dx;
        final cy = rect.center.dy;
        final s = cellSize * 0.15;
        canvas.drawLine(
          Offset(cx - s, cy),
          Offset(cx - s * 0.3, cy + s * 0.7),
          checkPaint,
        );
        canvas.drawLine(
          Offset(cx - s * 0.3, cy + s * 0.7),
          Offset(cx + s, cy - s * 0.5),
          checkPaint,
        );
      }
    }
  }

  /// Page 3: User avatars slide in and cluster together.
  void _drawAvatars(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final avatarRadius = size.width * 0.12;

    // 5 avatars slide in from different angles
    final angles = [0.0, 1.2, 2.4, 3.6, 4.8];
    final avatarColors = [
      colors.first,
      colors.last,
      AppColors.pathOrange,
      AppColors.purpleLight,
      AppColors.streakGold,
    ];

    for (int i = 0; i < angles.length; i++) {
      final delay = i * 0.15;
      final localProgress = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
      final eased = Curves.elasticOut.transform(localProgress);

      final angle = angles[i];
      final distance = size.width * 0.28;
      final startX = centerX + math.cos(angle) * size.width;
      final startY = centerY + math.sin(angle) * size.height;
      final endX = centerX + math.cos(angle) * distance;
      final endY = centerY + math.sin(angle) * distance;

      final x = startX + (endX - startX) * eased;
      final y = startY + (endY - startY) * eased;

      // Avatar circle
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.2 * localProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(x, y + 2), avatarRadius, shadowPaint);

      final paint = Paint()..color = avatarColors[i].withValues(alpha: localProgress);
      canvas.drawCircle(Offset(x, y), avatarRadius, paint);

      // Simple face
      if (localProgress > 0.5) {
        final facePaint = Paint()
          ..color = Colors.white.withValues(alpha: (localProgress - 0.5) * 2);
        // Eyes
        canvas.drawCircle(
          Offset(x - avatarRadius * 0.25, y - avatarRadius * 0.1),
          avatarRadius * 0.08,
          facePaint,
        );
        canvas.drawCircle(
          Offset(x + avatarRadius * 0.25, y - avatarRadius * 0.1),
          avatarRadius * 0.08,
          facePaint,
        );
        // Smile
        final smilePaint = Paint()
          ..color = Colors.white.withValues(alpha: (localProgress - 0.5) * 2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        final smileRect = Rect.fromCenter(
          center: Offset(x, y + avatarRadius * 0.15),
          width: avatarRadius * 0.4,
          height: avatarRadius * 0.25,
        );
        canvas.drawArc(smileRect, 0.2, math.pi * 0.6, false, smilePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingIllustrationPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pageIndex != pageIndex;
  }
}
