import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/models/group.dart';
import 'group_ui.dart';

/// Medal colours for the podium.
const _gold = AppColors.streakGold;
const _silver = Color(0xFFC0C0C0);
const _bronze = Color(0xFFCD7F32);

Color? medalColor(int rank) => switch (rank) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => null,
    };

/// Rank badge: a medal icon for the top three, otherwise the number.
class RankBadge extends StatelessWidget {
  const RankBadge({required this.rank, super.key});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = medalColor(rank);
    final color = medal ?? theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Semantics(
      label: medal != null ? 'Rank $rank medal' : 'Rank $rank',
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: medal != null
            ? Icon(Icons.emoji_events_rounded, size: 20, color: medal)
            : Text(
                '$rank',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// Small badge indicating whether a solve time was server-verified.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({required this.verified, super.key});

  static const unverifiedMessage = 'Time not verified';
  static const verifiedMessage = 'Verified time';

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final message = verified ? verifiedMessage : unverifiedMessage;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        label: message,
        child: Icon(
          verified ? Icons.verified_rounded : Icons.help_outline_rounded,
          size: 16,
          color: verified ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}

/// Shared frame for daily and weekly rows.
class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({
    required this.rank,
    required this.displayName,
    required this.avatarUrl,
    required this.isCurrentUser,
    required this.subtitle,
    required this.trailing,
    required this.semanticsLabel,
    this.badge,
  });

  final int rank;
  final String displayName;
  final String? avatarUrl;
  final bool isCurrentUser;
  final String subtitle;
  final Widget trailing;
  final String semanticsLabel;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);
    final name = displayName.isEmpty ? 'Player' : displayName;

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Container(
        margin: const EdgeInsetsDirectional.only(bottom: AppSizes.sm),
        decoration: surface.decoration(
          highlight: isCurrentUser ? theme.colorScheme.primary : null,
        ),
        child: ListTile(
          minVerticalPadding: AppSizes.sm,
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.xs,
          ),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RankBadge(rank: rank),
              const SizedBox(width: AppSizes.sm),
              MemberAvatar(displayName: name, avatarUrl: avatarUrl, radius: 16),
            ],
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight:
                        isCurrentUser ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (isCurrentUser) ...[
                const SizedBox(width: AppSizes.xs),
                GroupChip(label: 'You', color: theme.colorScheme.primary),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryTextColor(context),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              trailing,
              if (badge != null) ...[
                const SizedBox(width: AppSizes.xs),
                badge!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DailyLeaderboardRow extends StatelessWidget {
  const DailyLeaderboardRow({
    required this.entry,
    required this.isCurrentUser,
    super.key,
  });

  final GroupLeaderboardEntry entry;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = entry.completed
        ? AppDateUtils.formatTime(entry.timeSeconds)
        : 'In progress';
    final hints = '${entry.hintsUsed} hint${entry.hintsUsed == 1 ? '' : 's'}';
    final undos = '${entry.undosUsed} undo${entry.undosUsed == 1 ? '' : 's'}';

    return _LeaderboardTile(
      rank: entry.rank,
      displayName: entry.displayName,
      avatarUrl: entry.avatarUrl,
      isCurrentUser: isCurrentUser,
      subtitle: '$hints · $undos',
      semanticsLabel: 'Rank ${entry.rank}, ${entry.displayName}'
          '${isCurrentUser ? ' (you)' : ''}, $time, $hints, $undos, '
          '${entry.verified ? 'verified' : 'time not verified'}',
      trailing: Text(
        time,
        style: theme.textTheme.titleMedium?.copyWith(
          color: entry.completed
              ? theme.colorScheme.primary
              : secondaryTextColor(context),
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      badge: entry.completed ? VerifiedBadge(verified: entry.verified) : null,
    );
  }
}

class WeeklyLeaderboardRow extends StatelessWidget {
  const WeeklyLeaderboardRow({
    required this.entry,
    required this.isCurrentUser,
    super.key,
  });

  final WeeklyLeaderboardEntry entry;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = entry.avgTimeSecondsRounded;
    final avgText = avg == null ? '—' : AppDateUtils.formatTime(avg);
    final solved =
        '${entry.completedCount} solved${entry.completedCount == 1 ? '' : ''}';
    final hints = '${entry.totalHints} hint${entry.totalHints == 1 ? '' : 's'}';

    return _LeaderboardTile(
      rank: entry.rank,
      displayName: entry.displayName,
      avatarUrl: entry.avatarUrl,
      isCurrentUser: isCurrentUser,
      subtitle: '$solved · $hints',
      semanticsLabel: 'Rank ${entry.rank}, ${entry.displayName}'
          '${isCurrentUser ? ' (you)' : ''}, ${entry.completedCount} solved, '
          'average time ${avg == null ? 'none' : avgText}, $hints',
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            avgText,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            'avg',
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
}
