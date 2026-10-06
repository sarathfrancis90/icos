import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';

/// One-time hint shown above the grid on the first puzzle ever opened on this
/// device. Static (nothing moves, so no reduced-motion variant), wraps at large
/// text sizes and can be dismissed by tapping it.
class FirstPlayTooltip extends StatelessWidget {
  const FirstPlayTooltip({
    required this.onDismiss,
    this.tapToDraw = false,
    super.key,
  });

  final VoidCallback onDismiss;

  /// Tap-to-draw mode is on: the copy tells the player to tap, not drag.
  final bool tapToDraw;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = tapToDraw
        ? AppStrings.firstPlayTooltipTap
        : AppStrings.firstPlayTooltip;
    return Semantics(
      container: true,
      button: true,
      label: text,
      onTap: onDismiss,
      child: ExcludeSemantics(
        child: Material(
          color: palette.elevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            side: BorderSide(color: palette.border),
          ),
          child: InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swipe_rounded, size: 18, color: palette.accent),
                    const SizedBox(width: AppSizes.sm),
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
