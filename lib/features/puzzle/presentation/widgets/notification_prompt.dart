import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/services/storage_service.dart';

/// Pre-permission screen shown before the OS notification dialog.
/// Shown after first puzzle completion.
class NotificationPromptDialog extends StatelessWidget {
  const NotificationPromptDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    if (StorageService.hasSeenNotificationPrompt) return false;
    if (StorageService.solveCount < 1) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const NotificationPromptDialog(),
    );

    await StorageService.setHasSeenNotificationPrompt(true);
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.electricBlue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_rounded,
              size: 32,
              color: AppColors.electricBlue,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            'Never miss a puzzle!',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Get notified when the daily puzzle is ready. We only send one notification per day.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not Now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Enable'),
        ),
      ],
    );
  }
}
