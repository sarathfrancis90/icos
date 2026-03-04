import 'package:flutter/widgets.dart';

abstract final class MotionUtils {
  /// Returns true if the platform has requested reduced motion.
  /// All animation code should check this and provide static fallbacks.
  static bool shouldReduceMotion(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }
}
