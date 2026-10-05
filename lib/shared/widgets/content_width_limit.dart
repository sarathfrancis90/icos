import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';

/// Caps app content at [AppSizes.contentMaxWidth] and centres it.
///
/// Applied once at the app root so every screen gets the tablet layout
/// (content max 600dp). Descendants also see the capped width through
/// `MediaQuery`, so size formulas based on it (the puzzle grid) follow.
/// Phones are narrower than the cap and unaffected.
class ContentWidthLimit extends StatelessWidget {
  const ContentWidthLimit({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= AppSizes.contentMaxWidth) return child;
    final width = math.min(media.size.width, AppSizes.contentMaxWidth);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SizedBox(
          width: width,
          child: MediaQuery(
            data: media.copyWith(size: Size(width, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}
