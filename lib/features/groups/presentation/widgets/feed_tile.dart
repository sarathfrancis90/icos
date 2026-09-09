import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/models/group.dart';
import 'group_ui.dart';

/// Human-readable relative timestamp ("just now", "5m ago", "2h ago",
/// "3d ago", else the date).
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final diff = reference.difference(time.toUtc());
  if (diff.isNegative || diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return AppDateUtils.formatDate(time.toUtc());
}

/// Maps a `group_feed.event` value to a sentence fragment.
String describeFeedEvent(GroupFeedEvent event, {String? today}) {
  final todayUtc = today ?? AppDateUtils.todayUtc();
  final date = event.puzzleDate;
  final puzzle = date == null
      ? 'the puzzle'
      : date == todayUtc
          ? "today's puzzle"
          : 'the $date puzzle';

  final time = event.timeSeconds;
  final timeSuffix = time == null ? '' : ' in ${AppDateUtils.formatTime(time)}';

  return switch (event.event) {
    'solved' || 'solve' || 'puzzle_solved' || 'completed' =>
      'solved $puzzle$timeSuffix',
    'joined' || 'member_joined' => 'joined the group',
    'left' || 'member_left' => 'left the group',
    'created' || 'group_created' => 'created the group',
    'admin_transferred' || 'promoted' => 'became the admin',
    'streak' || 'streak_milestone' => 'hit a streak milestone',
    final other when other.isEmpty => 'did something',
    final other => other.replaceAll('_', ' '),
  };
}

IconData _iconFor(String event) => switch (event) {
      'solved' || 'solve' || 'puzzle_solved' || 'completed' =>
        Icons.check_circle_rounded,
      'joined' || 'member_joined' => Icons.person_add_alt_1_rounded,
      'left' || 'member_left' => Icons.logout_rounded,
      'created' || 'group_created' => Icons.auto_awesome_rounded,
      'admin_transferred' || 'promoted' => Icons.admin_panel_settings_rounded,
      'streak' || 'streak_milestone' => Icons.local_fire_department_rounded,
      _ => Icons.bolt_rounded,
    };

class FeedTile extends StatelessWidget {
  const FeedTile({
    required this.event,
    required this.isCurrentUser,
    super.key,
  });

  final GroupFeedEvent event;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);
    final name = isCurrentUser
        ? 'You'
        : (event.displayName?.trim().isNotEmpty == true
            ? event.displayName!.trim()
            : 'Someone');
    final description = describeFeedEvent(event);
    final when = formatRelativeTime(event.createdAt);

    return Semantics(
      label: '$name $description, $when',
      container: true,
      child: Container(
        margin: const EdgeInsetsDirectional.only(bottom: AppSizes.sm),
        decoration: surface.decoration(),
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.xs,
          ),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              MemberAvatar(
                displayName: event.displayName ?? name,
                avatarUrl: event.avatarUrl,
              ),
              PositionedDirectional(
                end: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsetsDirectional.all(2),
                  decoration: BoxDecoration(
                    color: surface.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconFor(event.event),
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          title: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' $description'),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            when,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryTextColor(context),
            ),
          ),
        ),
      ),
    );
  }
}
