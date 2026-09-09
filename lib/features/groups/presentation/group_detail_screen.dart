import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/result.dart';
import '../domain/models/group.dart';
import '../providers/groups_provider.dart';
import 'widgets/feed_tile.dart';
import 'widgets/group_ui.dart';
import 'widgets/invite_share.dart';
import 'widgets/leaderboard_row.dart';
import 'widgets/member_tile.dart';
import 'widgets/report_dialog.dart';

enum _GroupMenuAction { share, qr, report, leave, delete }

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
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final session = ref.watch(groupsSessionProvider);

    return groupAsync.when(
      data: (group) => _buildContent(context, group, session),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: GroupEmptyState(
          icon: Icons.group_off_rounded,
          message: error is AppError ? error.userMessage : AppStrings.groupNotFound,
          action: OutlinedButton(
            onPressed: () => ref.invalidate(groupDetailProvider(widget.groupId)),
            child: const Text('Retry'),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Group group, GroupsSession session) {
    final theme = Theme.of(context);
    final isAdmin = session.userId != null && group.adminId == session.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Share invite',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => shareGroupInvite(context, group),
          ),
          PopupMenuButton<_GroupMenuAction>(
            key: const Key('group_menu'),
            tooltip: 'Group options',
            onSelected: (action) => _onMenuAction(action, group),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _GroupMenuAction.share,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_rounded),
                  title: Text('Share invite'),
                ),
              ),
              const PopupMenuItem(
                value: _GroupMenuAction.qr,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_2_rounded),
                  title: Text('Show QR code'),
                ),
              ),
              const PopupMenuItem(
                value: _GroupMenuAction.report,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.flag_rounded),
                  title: Text('Report group'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _GroupMenuAction.leave,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                  title: Text(
                    AppStrings.leaveGroup,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
              if (isAdmin)
                PopupMenuItem(
                  value: _GroupMenuAction.delete,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_forever_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete group',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
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
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: secondaryTextColor(context),
            tabs: const [
              Tab(text: 'Today'),
              Tab(text: 'Week'),
              Tab(text: AppStrings.groupMembers),
              Tab(text: 'Activity'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DailyTab(groupId: group.id, currentUserId: session.userId),
                _WeeklyTab(groupId: group.id, currentUserId: session.userId),
                _MembersTab(group: group, session: session),
                _ActivityTab(groupId: group.id, currentUserId: session.userId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenuAction(_GroupMenuAction action, Group group) async {
    switch (action) {
      case _GroupMenuAction.share:
        await shareGroupInvite(context, group);
      case _GroupMenuAction.qr:
        await showInviteQrDialog(context, group);
      case _GroupMenuAction.report:
        final sent = await showReportDialog(
          context,
          target: ReportTarget.group,
          targetId: group.id,
          targetName: group.name,
        );
        if (sent && mounted) showAppSnackBar(context, 'Report submitted. Thank you.');
      case _GroupMenuAction.leave:
        await _leave(group);
      case _GroupMenuAction.delete:
        await _delete(group);
    }
  }

  Future<void> _leave(Group group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: AppStrings.leaveGroup,
      message: 'Leave "${group.name}"? You can rejoin later with the invite code.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await ref.read(myGroupsProvider.notifier).leaveGroup(group.id);
    if (!mounted) return;
    switch (result) {
      case Success():
        _exit();
      case Failure(error: final error):
        showAppSnackBar(context, error.userMessage);
    }
  }

  Future<void> _delete(Group group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete group',
      message: 'Delete "${group.name}" for everyone? Members will lose access '
          'and the invite code will stop working. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await ref.read(myGroupsProvider.notifier).deleteGroup(group.id);
    if (!mounted) return;
    switch (result) {
      case Success():
        _exit();
      case Failure(error: final error):
        showAppSnackBar(context, error.userMessage);
    }
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/groups');
    }
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSizes.md,
        0,
        AppSizes.md,
        AppSizes.sm,
      ),
      child: Container(
        padding: const EdgeInsetsDirectional.all(AppSizes.md),
        decoration: surface.decoration(),
        child: Column(
          children: [
            if (group.description.isNotEmpty) ...[
              Text(
                group.description,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor(context),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_rounded,
                  size: 16,
                  color: secondaryTextColor(context),
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
                Semantics(
                  label: 'Invite code ${group.inviteCode.split('').join(' ')}',
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
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
                ),
                const SizedBox(width: AppSizes.xs),
                IconButton(
                  tooltip: 'Copy invite code',
                  iconSize: 18,
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.minTouchTarget,
                    minHeight: AppSizes.minTouchTarget,
                  ),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => copyInviteCode(context, group),
                ),
                IconButton(
                  tooltip: 'Show QR code',
                  iconSize: 18,
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.minTouchTarget,
                    minHeight: AppSizes.minTouchTarget,
                  ),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  onPressed: () => showInviteQrDialog(context, group),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTab extends ConsumerWidget {
  const _DailyTab({required this.groupId, required this.currentUserId});

  final String groupId;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = AppDateUtils.todayUtc();
    final provider = dailyLeaderboardProvider(groupId, today);

    return AsyncRefreshList<GroupLeaderboardEntry>(
      value: ref.watch(provider),
      onRefresh: () => ref.refresh(provider.future),
      errorMessage: 'Could not load the leaderboard. Pull to retry.',
      empty: const GroupEmptyState(
        icon: Icons.leaderboard_rounded,
        message: 'No one has played today yet.\nBe the first!',
      ),
      itemBuilder: (context, entry, _) => DailyLeaderboardRow(
        entry: entry,
        isCurrentUser: entry.userId == currentUserId,
      ),
    );
  }
}

class _WeeklyTab extends ConsumerWidget {
  const _WeeklyTab({required this.groupId, required this.currentUserId});

  final String groupId;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = AppDateUtils.formatDate(AppDateUtils.weekStart());
    final provider = weeklyLeaderboardProvider(groupId, weekStart);

    return AsyncRefreshList<WeeklyLeaderboardEntry>(
      value: ref.watch(provider),
      onRefresh: () => ref.refresh(provider.future),
      errorMessage: 'Could not load the leaderboard. Pull to retry.',
      empty: const GroupEmptyState(
        icon: Icons.calendar_month_rounded,
        message: 'No solves this week yet.\nThe week resets Monday 00:00 UTC.',
      ),
      itemBuilder: (context, entry, _) => WeeklyLeaderboardRow(
        entry: entry,
        isCurrentUser: entry.userId == currentUserId,
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.group, required this.session});

  final Group group;
  final GroupsSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = groupMembersProvider(group.id);
    final viewerIsAdmin = session.userId != null && group.adminId == session.userId;

    return AsyncRefreshList<GroupMember>(
      value: ref.watch(provider),
      onRefresh: () => ref.refresh(provider.future),
      errorMessage: 'Could not load members. Pull to retry.',
      empty: const GroupEmptyState(
        icon: Icons.people_outline_rounded,
        message: 'No members yet',
      ),
      itemBuilder: (context, member, _) => MemberTile(
        member: member,
        isCurrentUser: member.userId == session.userId,
        viewerIsAdmin: viewerIsAdmin,
        onAction: (action) => _onAction(context, ref, member, action),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    GroupMember member,
    MemberAction action,
  ) async {
    final name = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : 'this member';
    final repo = ref.read(groupRepositoryProvider);

    switch (action) {
      case MemberAction.remove:
        final ok = await showConfirmDialog(
          context,
          title: 'Remove member',
          message: 'Remove $name from "${group.name}"? They can rejoin with '
              'the invite code.',
          confirmLabel: 'Remove',
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final result = await repo.removeMember(
          groupId: group.id,
          userId: member.userId,
        );
        if (!context.mounted) return;
        _afterMutation(context, ref, result, '$name was removed');
      case MemberAction.makeAdmin:
        final ok = await showConfirmDialog(
          context,
          title: 'Make admin',
          message: 'Hand admin rights to $name? You will become a regular '
              'member of "${group.name}".',
          confirmLabel: 'Make admin',
        );
        if (!ok || !context.mounted) return;
        final result = await repo.transferAdmin(
          groupId: group.id,
          newAdminId: member.userId,
        );
        if (!context.mounted) return;
        _afterMutation(context, ref, result, '$name is now the admin');
      case MemberAction.report:
        final sent = await showReportDialog(
          context,
          target: ReportTarget.user,
          targetId: member.userId,
          targetName: name,
        );
        if (sent && context.mounted) {
          showAppSnackBar(context, 'Report submitted. Thank you.');
        }
    }
  }

  void _afterMutation(
    BuildContext context,
    WidgetRef ref,
    Result<void, AppError> result,
    String successMessage,
  ) {
    switch (result) {
      case Success():
        showAppSnackBar(context, successMessage);
        ref.invalidate(groupMembersProvider(group.id));
        ref.invalidate(groupDetailProvider(group.id));
        ref.invalidate(myGroupsProvider);
      case Failure(error: final error):
        showAppSnackBar(context, error.userMessage);
    }
  }
}

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.groupId, required this.currentUserId});

  final String groupId;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = groupFeedProvider(groupId);

    return AsyncRefreshList<GroupFeedEvent>(
      value: ref.watch(provider),
      onRefresh: () async => ref.invalidate(provider),
      errorMessage: 'Could not load activity. Pull to retry.',
      empty: const GroupEmptyState(
        icon: Icons.bolt_rounded,
        message: 'No activity yet.\nSolves by members show up here live.',
      ),
      itemBuilder: (context, event, _) => FeedTile(
        event: event,
        isCurrentUser: event.userId == currentUserId,
      ),
    );
  }
}
