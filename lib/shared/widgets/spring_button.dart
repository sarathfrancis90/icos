import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../core/utils/haptics.dart';
import '../../core/utils/motion.dart';

/// A button wrapper that applies spring-physics scale animation on press.
///
/// On tap down, the child scales to [pressedScale] (default 0.95).
/// On tap up/cancel, it springs back to 1.0 with a slight overshoot.
class SpringButton extends StatefulWidget {
  const SpringButton({
    required this.child,
    required this.onPressed,
    this.pressedScale = 0.95,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double pressedScale;
  final bool enabled;

  @override
  State<SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<SpringButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scaleAnimation;
  double _currentScale = 1.0;

  static const _stiffness = 300.0;
  static const _damping = 15.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _scaleAnimation = AlwaysStoppedAnimation(_currentScale);
    _controller.addListener(() {
      setState(() {
        _currentScale = _scaleAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.enabled || widget.onPressed == null) return;
    Haptics.light();

    if (MotionUtils.shouldReduceMotion(context)) {
      setState(() => _currentScale = widget.pressedScale);
      return;
    }

    _controller.stop();
    setState(() => _currentScale = widget.pressedScale);
  }

  void _onTapUp(TapUpDetails _) {
    if (!widget.enabled || widget.onPressed == null) return;
    _springBack();
    widget.onPressed?.call();
  }

  void _onTapCancel() {
    if (!widget.enabled || widget.onPressed == null) return;
    _springBack();
  }

  void _springBack() {
    if (MotionUtils.shouldReduceMotion(context)) {
      setState(() => _currentScale = 1.0);
      return;
    }

    const spring = SpringDescription(
      mass: 1.0,
      stiffness: _stiffness,
      damping: _damping,
    );
    final simulation = SpringSimulation(spring, _currentScale, 1.0, 0.0);

    _scaleAnimation = _controller.drive(
      Tween<double>(begin: _currentScale, end: 1.0),
    );

    _controller
      ..value = 0.0
      ..animateWith(simulation);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: Transform.scale(
        scale: _currentScale,
        child: widget.child,
      ),
    );
  }
}
