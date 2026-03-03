import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/models/group.dart';
import '../providers/groups_provider.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myGroupsProvider);
    final theme = Theme.of(context);

    return groupsAsync.when(
      data: (groups) {
        final group = groups.where((g) => g.id == widget.groupId).firstOrNull;
        if (group == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Group not found')),
          );
        }
        return _buildContent(context, theme, group);
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(color: AppColors.purpleLight)),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme, Group group) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') {
                _showLeaveConfirmation(context, group);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave Group'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _GroupHeader(group: group),
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.purpleLight,
            labelColor: AppColors.purpleLight,
            unselectedLabelColor: AppColors.textSecondaryDark,
            tabs: const [
              Tab(text: 'Daily'),
              Tab(text: 'Weekly'),
              Tab(text: AppStrings.groupMembers),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DailyLeaderboardTab(groupId: widget.groupId),
                _WeeklyLeaderboardTab(groupId: widget.groupId),
                _MembersTab(groupId: widget.groupId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLeaveConfirmation(
    BuildContext context,
    Group group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave "${group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success =
          await ref.read(myGroupsProvider.notifier).leaveGroup(group.id);
      if (success && context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            children: [
              if (group.description.isNotEmpty) ...[
                Text(
                  group.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.sm),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_rounded,
                    size: 16,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: AppSizes.xs),
                  Text(
                    '${group.memberCount}/${group.maxMembers} members',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.sm,
                      vertical: AppSizes.xs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: Text(
                      group.inviteCode,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy invite code',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: group.inviteCode),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invite code copied'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, size: 18),
                    tooltip: 'Share invite code',
                    onPressed: () {
                      Share.share(
                        'Join my ${AppStrings.appName} group "${group.name}"! Use code: ${group.inviteCode}',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyLeaderboardTab extends ConsumerWidget {
  const _DailyLeaderboardTab({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = AppDateUtils.todayUtc();
    final leaderboardAsync =
        ref.watch(groupDailyLeaderboardProvider(groupId, today));

    return leaderboardAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.leaderboard_rounded,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'No one has played today yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          );
        }
        return _LeaderboardList(entries: entries);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => const Center(child: Text('Failed to load leaderboard')),
    );
  }
}

class _WeeklyLeaderboardTab extends ConsumerWidget {
  const _WeeklyLeaderboardTab({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = AppDateUtils.formatDate(AppDateUtils.weekStart());
    final leaderboardAsync =
        ref.watch(groupWeeklyLeaderboardProvider(groupId, weekStart));

    return leaderboardAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.leaderboard_rounded,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'No data for this week yet',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          );
        }
        return _LeaderboardList(entries: entries);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => const Center(child: Text('Failed to load leaderboard')),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({required this.entries});

  final List<GroupLeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.all(AppSizes.md),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSizes.sm),
          child: ListTile(
            leading: _RankBadge(rank: entry.rank),
            title: Text(
              entry.displayName,
              style: theme.textTheme.titleMedium,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppDateUtils.formatTime(entry.timeSeconds),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (entry.hintsUsed > 0)
                  Text(
                    '${entry.hintsUsed} hint${entry.hintsUsed == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => AppColors.streakGold,
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final theme = Theme.of(context);

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return const Center(child: Text('No members'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSizes.md),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            return Card(
              margin: const EdgeInsets.only(bottom: AppSizes.sm),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: member.avatarUrl != null
                      ? NetworkImage(member.avatarUrl!)
                      : null,
                  child: member.avatarUrl == null
                      ? Text(
                          (member.displayName ?? '?')[0].toUpperCase(),
                          style: theme.textTheme.titleMedium,
                        )
                      : null,
                ),
                title: Text(
                  member.displayName ?? 'Anonymous',
                  style: theme.textTheme.titleMedium,
                ),
                trailing: member.role == 'admin'
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.sm,
                          vertical: AppSizes.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.coralOrange.withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusSm),
                        ),
                        child: Text(
                          'Admin',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.coralOrange,
                          ),
                        ),
                      )
                    : null,
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => const Center(child: Text('Failed to load members')),
    );
  }
}
