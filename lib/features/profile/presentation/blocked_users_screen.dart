import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../../../shared/widgets/content_width.dart';
import '../../groups/domain/models/blocked_user.dart';
import '../../groups/presentation/widgets/group_ui.dart';
import '../../groups/providers/blocked_users_provider.dart';

/// Lists the people the current user has blocked and lets them unblock.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.blockedUsers)),
      body: ContentWidth(child: blocked.when(
        data: (users) => users.isEmpty
            ? const GroupEmptyState(
                icon: Icons.block_rounded,
                message: AppStrings.noBlockedUsers,
              )
            : ListView.builder(
                padding: const EdgeInsetsDirectional.all(AppSizes.md),
                itemCount: users.length,
                itemBuilder: (context, index) =>
                    _BlockedUserRow(user: users[index]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => GroupEmptyState(
          icon: Icons.cloud_off_rounded,
          message: AppStrings.blockedUsersLoadFailed,
          action: OutlinedButton(
            onPressed: () => ref.invalidate(blockedUsersProvider),
            child: const Text(AppStrings.retry),
          ),
        ),
      )),
    );
  }
}

class _BlockedUserRow extends ConsumerWidget {
  const _BlockedUserRow({required this.user});

  final BlockedUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: AppSizes.sm),
      decoration: surface.decoration(),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.only(
          start: AppSizes.md,
          end: AppSizes.xs,
        ),
        title: Text(
          user.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        trailing: Semantics(
          button: true,
          label: '${AppStrings.unblockUser}: ${user.displayName}',
          excludeSemantics: true,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AppSizes.minTouchTarget,
                AppSizes.minTouchTarget,
              ),
            ),
            onPressed: () => _unblock(context, ref),
            child: const Text(AppStrings.unblockButton),
          ),
        ),
      ),
    );
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(blockedUsersProvider.notifier)
        .unblock(user.userId);
    if (!context.mounted) return;
    showAppSnackBar(context, switch (result) {
      Success() => AppStrings.userUnblocked(user.displayName),
      Failure(error: final error) => error.userMessage,
    });
  }
}
