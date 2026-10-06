import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';

/// Shown above the grid while a bundled (offline) puzzle stands in for the
/// real daily puzzle. Static on purpose: nothing moves, so it needs no
/// reduced-motion alternative. The text wraps, so it survives large text.
class OfflinePuzzleNotice extends StatelessWidget {
  const OfflinePuzzleNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: AppStrings.offlinePuzzleNotice,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          decoration: BoxDecoration(
            color: context.palette.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(color: context.palette.warning.withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 18,
                  color: context.palette.warning,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  AppStrings.offlinePuzzleNotice,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
