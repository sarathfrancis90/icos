import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../domain/models/group.dart';
import '../providers/groups_provider.dart';
import 'widgets/account_required_card.dart';
import 'widgets/create_group_dialog.dart';
import 'widgets/group_ui.dart';
import 'widgets/join_group_dialog.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  static const emptyMessage =
      'Create or join a group to compete\nwith friends and family';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(groupsSessionProvider);
    final groupsAsync = ref.watch(myGroupsProvider);
    final hasGroups = groupsAsync.valueOrNull?.isNotEmpty == true;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AppSizes.lg,
          end: AppSizes.lg,
          top: AppSizes.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.navGroups,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                if (session.canUseGroups && hasGroups)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GlassIconButton(
                        icon: Icons.add_rounded,
                        tooltip: AppStrings.createGroup,
                        onPressed: () => _create(context, ref),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      _GlassIconButton(
                        icon: Icons.group_add_rounded,
                        tooltip: AppStrings.joinGroup,
                        onPressed: () => _join(context, ref),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            Expanded(
              child: !session.canUseGroups
                  ? const AccountRequiredCard()
                  : AsyncRefreshList<Group>(
                      value: groupsAsync,
                      onRefresh: () =>
                          ref.read(myGroupsProvider.notifier).refresh(),
                      padding: const EdgeInsetsDirectional.only(
                        bottom: AppSizes.lg,
                      ),
                      itemBuilder: (context, group, _) =>
                          _GroupCard(group: group),
                      errorMessage: AppStrings.errorGeneric,
                      empty: _EmptyState(
                        onCreateGroup: () => _create(context, ref),
                        onJoinGroup: () => _join(context, ref),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    if (!_requireAccount(context, ref)) return;
    final group = await showCreateGroupDialog(context);
    if (group != null && context.mounted) {
      context.push('/groups/${group.id}');
    }
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    if (!_requireAccount(context, ref)) return;
    final group = await showJoinGroupDialog(context);
    if (group != null && context.mounted) {
      context.push('/groups/${group.id}');
    }
  }

  bool _requireAccount(BuildContext context, WidgetRef ref) {
    if (ref.read(groupsSessionProvider).canUseGroups) return true;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.accountRequired),
        content: const Text(AppStrings.linkAccountPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/auth');
            },
            child: const Text(AccountRequiredCard.ctaLabel),
          ),
        ],
      ),
    );
    return false;
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isDark ? AppColors.elevatedSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            child: Container(
              width: AppSizes.minTouchTarget,
              height: AppSizes.minTouchTarget,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                border: Border.all(
                  color: isDark
                      ? AppColors.cellBorder.withValues(alpha: 0.5)
                      : AppColors.lightGridLine,
                ),
              ),
              child: Icon(icon, size: 20, color: secondaryTextColor(context)),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppColors.purpleLight.withValues(alpha: 0.15),
                  AppColors.purpleDeep.withValues(alpha: 0.03),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.group_add_rounded,
              size: 40,
              color: AppColors.purpleLight.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            GroupsScreen.emptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor(context),
                ),
          ),
          const SizedBox(height: AppSizes.lg),
          SizedBox(
            width: 200,
            height: AppSizes.minTouchTarget + 4,
            child: FilledButton(
              key: const Key('groups_empty_create'),
              onPressed: onCreateGroup,
              child: const Text(AppStrings.createGroup),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          SizedBox(
            width: 200,
            height: AppSizes.minTouchTarget + 4,
            child: OutlinedButton(
              key: const Key('groups_empty_join'),
              onPressed: onJoinGroup,
              child: const Text(AppStrings.joinGroup),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);
    final members = '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}';

    return Semantics(
      button: true,
      label: '${group.name}, $members',
      child: Container(
        margin: const EdgeInsetsDirectional.only(bottom: AppSizes.sm),
        decoration: surface.decoration(),
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          title: Text(group.name, style: theme.textTheme.titleMedium),
          subtitle: group.description.isNotEmpty
              ? Text(
                  group.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                )
              : null,
          trailing: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_rounded,
                  size: 16,
                  color: secondaryTextColor(context),
                ),
                const SizedBox(width: AppSizes.xs),
                Text('${group.memberCount}', style: theme.textTheme.bodySmall),
                const SizedBox(width: AppSizes.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: secondaryTextColor(context),
                ),
              ],
            ),
          ),
          onTap: () => context.push('/groups/${group.id}'),
        ),
      ),
    );
  }
}
