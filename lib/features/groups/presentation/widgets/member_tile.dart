import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';
import '../../domain/models/group.dart';
import 'group_ui.dart';

enum MemberAction { remove, makeAdmin, report, block, unblock }

/// One row in the Members tab with a role chip and a context-sensitive
/// overflow menu.
class MemberTile extends StatelessWidget {
  const MemberTile({
    required this.member,
    required this.isCurrentUser,
    required this.isBlocked,
    required this.viewerIsAdmin,
    required this.onAction,
    super.key,
  });

  final GroupMember member;
  final bool isCurrentUser;

  /// The viewer has blocked this member: the name is hidden and the menu
  /// offers Unblock instead of Block. The row stays so an admin can still
  /// remove the member.
  final bool isBlocked;
  final bool viewerIsAdmin;
  final void Function(MemberAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);
    final name = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : 'Player';
    final shownName = isBlocked ? AppStrings.blockedUserName : name;
    final roleLabel = member.isAdmin ? 'Admin' : 'Member';

    final actions = <PopupMenuEntry<MemberAction>>[
      if (viewerIsAdmin && !member.isAdmin)
        const PopupMenuItem(
          value: MemberAction.makeAdmin,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsetsDirectional.zero,
            leading: Icon(Icons.admin_panel_settings_rounded),
            title: Text('Make admin'),
          ),
        ),
      if (viewerIsAdmin)
        const PopupMenuItem(
          value: MemberAction.remove,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsetsDirectional.zero,
            leading: Icon(Icons.person_remove_rounded),
            title: Text('Remove member'),
          ),
        ),
      const PopupMenuItem(
        value: MemberAction.report,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsetsDirectional.zero,
          leading: Icon(Icons.flag_rounded),
          title: Text('Report user'),
        ),
      ),
      if (isBlocked)
        const PopupMenuItem(
          value: MemberAction.unblock,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsetsDirectional.zero,
            leading: Icon(Icons.lock_open_rounded),
            title: Text(AppStrings.unblockUser),
          ),
        )
      else
        const PopupMenuItem(
          value: MemberAction.block,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsetsDirectional.zero,
            leading: Icon(Icons.block_rounded),
            title: Text(AppStrings.blockUser),
          ),
        ),
    ];

    return Semantics(
      label: isBlocked
          ? AppStrings.blockedUserName
          : '$name, $roleLabel${isCurrentUser ? ', you' : ''}',
      container: true,
      child: Container(
        margin: const EdgeInsetsDirectional.only(bottom: AppSizes.sm),
        decoration: surface.decoration(
          highlight: isCurrentUser ? theme.colorScheme.primary : null,
        ),
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.only(
            start: AppSizes.md,
            end: AppSizes.xs,
            top: AppSizes.xs,
            bottom: AppSizes.xs,
          ),
          leading: isBlocked
              ? ExcludeSemantics(
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        secondaryTextColor(context).withValues(alpha: 0.15),
                    child: Icon(
                      Icons.block_rounded,
                      color: secondaryTextColor(context),
                    ),
                  ),
                )
              : MemberAvatar(displayName: name, avatarUrl: member.avatarUrl),
          title: Text(
            shownName,
            overflow: TextOverflow.ellipsis,
            style: isBlocked
                ? theme.textTheme.titleMedium?.copyWith(
                    color: secondaryTextColor(context),
                    fontStyle: FontStyle.italic,
                  )
                : theme.textTheme.titleMedium,
          ),
          subtitle: Row(
            children: [
              GroupChip(
                label: roleLabel,
                color: member.isAdmin
                    ? context.palette.coral
                    : secondaryTextColor(context),
              ),
              if (isCurrentUser) ...[
                const SizedBox(width: AppSizes.xs),
                GroupChip(label: 'You', color: theme.colorScheme.primary),
              ],
            ],
          ),
          trailing: isCurrentUser
              ? null
              : SizedBox(
                  width: AppSizes.minTouchTarget,
                  height: AppSizes.minTouchTarget,
                  child: PopupMenuButton<MemberAction>(
                    key: Key('member_menu_${member.userId}'),
                    tooltip: 'Options for $shownName',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: onAction,
                    itemBuilder: (_) => actions,
                  ),
                ),
        ),
      ),
    );
  }
}
