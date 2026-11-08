import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';

/// Shows [FreshStartDialog] once; see `LegacyCleanup`.
Future<void> showFreshStartDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const FreshStartDialog(),
  );
}

/// One-time notice for players upgrading from the old backend: their
/// progress and groups were not carried over.
class FreshStartDialog extends StatelessWidget {
  const FreshStartDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(
        AppSizes.lg,
        AppSizes.md,
        AppSizes.lg,
        AppSizes.sm,
      ),
      title: const Text(AppStrings.freshStartTitle),
      content: const SingleChildScrollView(
        child: Text(AppStrings.freshStartBody),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(
              AppSizes.minTouchTarget,
              AppSizes.minTouchTarget,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.ok),
        ),
      ],
    );
  }
}
