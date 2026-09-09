import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_service.dart';

/// Offline notice + "results waiting to sync" chip, shown in the app shell
/// (never during gameplay). Renders nothing while online with an empty queue.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityNotifierProvider);
    final queued = ref.watch(syncQueueLengthProvider).valueOrNull ?? 0;

    if (online && queued == 0) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!online)
              Container(
                key: const Key('offline-banner'),
                width: double.infinity,
                color: AppColors.warning.withValues(alpha: 0.18),
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.sm,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(
                        "You're offline — progress is saved on this device",
                        style: TextStyle(
                          color: AppColors.textPrimaryDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (queued > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: AppSizes.xs,
                  start: AppSizes.md,
                  end: AppSizes.md,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    key: const Key('sync-pending-chip'),
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSizes.sm + 4,
                      vertical: AppSizes.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.elevatedSurface,
                      borderRadius: BorderRadius.circular(AppSizes.radiusXl),
                      border: Border.all(
                        color: AppColors.cellBorder.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sync_rounded,
                          size: 14,
                          color: AppColors.textSecondaryDark,
                        ),
                        const SizedBox(width: AppSizes.xs),
                        Text(
                          '$queued result${queued == 1 ? '' : 's'} waiting to sync',
                          style: const TextStyle(
                            color: AppColors.textSecondaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
