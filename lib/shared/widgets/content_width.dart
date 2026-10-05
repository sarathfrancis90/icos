import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';

/// Caps a screen BODY at [AppSizes.contentMaxWidth] (600dp) and centres it.
///
/// Use inside a screen's body, never around the whole app: backgrounds, the
/// bottom navigation bar, dialogs, SnackBars and overlays must stay
/// full-bleed. Height constraints pass through unchanged and nothing happens
/// on phones (narrower than the cap).
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    required this.child,
    this.maxWidth = AppSizes.contentMaxWidth,
    super.key,
  });

  final Widget child;

  /// The cap; defaults to the 600dp content width.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) return child;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: math.min(constraints.maxWidth, maxWidth),
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}
