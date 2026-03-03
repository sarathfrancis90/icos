import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/models/group.dart';
import '../providers/groups_provider.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);
    final authState = ref.watch(authNotifierProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Groups',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                if (groupsAsync.valueOrNull?.isNotEmpty == true)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        tooltip: AppStrings.createGroup,
                        onPressed: () =>
                            _showCreateGroupDialog(context, ref),
                      ),
                      IconButton(
                        icon: const Icon(Icons.group_add_rounded),
                        tooltip: AppStrings.joinGroup,
                        onPressed: () =>
                            _showJoinGroupDialog(context, ref, authState),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            Expanded(
              child: groupsAsync.when(
                data: (groups) {
                  if (groups.isEmpty) {
                    return _EmptyState(
                      onCreateGroup: () =>
                          _showCreateGroupDialog(context, ref),
                      onJoinGroup: () =>
                          _showJoinGroupDialog(context, ref, authState),
                    );
                  }
                  return _GroupsList(groups: groups);
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.errorGeneric,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSizes.md),
                      OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(myGroupsProvider),
                        child: const Text('Retry'),
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

  Future<void> _showCreateGroupDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.createGroup),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'Enter a group name',
                ),
                maxLength: AppSizes.maxGroupNameLength,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a group name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),
              TextFormField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What is this group about?',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true) {
      final group = await ref.read(myGroupsProvider.notifier).createGroup(
            name: nameController.text.trim(),
            description: descriptionController.text.trim(),
          );
      if (group != null && context.mounted) {
        context.push('/groups/${group.id}');
      }
    }

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showJoinGroupDialog(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<dynamic> authState,
  ) async {
    // Check if user is anonymous
    final authNotifier = ref.read(authNotifierProvider.notifier);
    if (authNotifier.isAnonymous) {
      _showUpgradePrompt(context);
      return;
    }

    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.joinGroup),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: codeController,
            decoration: const InputDecoration(
              labelText: AppStrings.groupInviteCode,
              hintText: 'Enter 6-character code',
            ),
            maxLength: AppSizes.inviteCodeLength,
            textCapitalization: TextCapitalization.characters,
            validator: (value) {
              if (value == null || value.trim().length != AppSizes.inviteCodeLength) {
                return 'Please enter a ${AppSizes.inviteCodeLength}-character invite code';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (result == true) {
      final group = await ref
          .read(myGroupsProvider.notifier)
          .joinGroup(codeController.text.trim());
      if (group != null && context.mounted) {
        context.push('/groups/${group.id}');
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to join group. Check the invite code and try again.'),
          ),
        );
      }
    }

    codeController.dispose();
  }

  void _showUpgradePrompt(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account Required'),
        content: const Text(AppStrings.linkAccountPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/auth');
            },
            child: const Text(AppStrings.signIn),
          ),
        ],
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
          Icon(
            Icons.group_add_rounded,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            'Create or join a group to compete\nwith friends and family',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: AppSizes.lg),
          ElevatedButton(
            onPressed: onCreateGroup,
            child: const Text(AppStrings.createGroup),
          ),
          const SizedBox(height: AppSizes.sm),
          OutlinedButton(
            onPressed: onJoinGroup,
            child: const Text(AppStrings.joinGroup),
          ),
        ],
      ),
    );
  }
}

class _GroupsList extends StatelessWidget {
  const _GroupsList({required this.groups});

  final List<Group> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSizes.sm),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.sm,
            ),
            title: Text(
              group.name,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: group.description.isNotEmpty
                ? Text(
                    group.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_rounded,
                  size: 16,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: AppSizes.xs),
                Text(
                  '${group.memberCount}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: AppSizes.sm),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
            onTap: () => context.push('/groups/${group.id}'),
          ),
        );
      },
    );
  }
}
