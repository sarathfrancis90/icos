import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/models/blocked_user.dart';
import 'groups_provider.dart';

part 'blocked_users_provider.g.dart';

/// The users the current user has blocked, newest first.
///
/// Blocking is enforced server-side (leaderboard RPCs and the `group_feed`
/// policy drop the blocked user's rows), so after a successful [block] or
/// [unblock] every provider that serves that filtered data is invalidated.
///
/// Dependency direction: this notifier only *invalidates* the group data
/// providers from its action methods; none of them watch it, so there is no
/// provider cycle (see the note on `MyGroups._upsertLocal`). Widgets that need
/// to know who is blocked watch [blockedUserIdsProvider].
@Riverpod(keepAlive: true)
class BlockedUsers extends _$BlockedUsers {
  @override
  Future<List<BlockedUser>> build() async {
    final session = ref.watch(groupsSessionProvider);
    if (!session.isSignedIn) return const [];
    final result = await ref.read(groupRepositoryProvider).listBlockedUsers();
    return switch (result) {
      Success(data: final users) => users,
      Failure(error: final error) => throw error,
    };
  }

  Future<Result<void, AppError>> block(String userId) async {
    final result = await ref.read(groupRepositoryProvider).blockUser(userId);
    if (result is Success) await _afterChange();
    return result;
  }

  Future<Result<void, AppError>> unblock(String userId) async {
    final result = await ref.read(groupRepositoryProvider).unblockUser(userId);
    if (result is Success) await _afterChange();
    return result;
  }

  Future<void> _afterChange() async {
    // Refetch quietly (no loading flash), then drop everything the server now
    // filters differently for this user.
    final refreshed = await ref
        .read(groupRepositoryProvider)
        .listBlockedUsers();
    if (refreshed case Success(data: final users)) {
      state = AsyncValue.data(users);
    } else {
      ref.invalidateSelf();
    }
    ref.invalidate(dailyLeaderboardProvider);
    ref.invalidate(weeklyLeaderboardProvider);
    ref.invalidate(groupFeedProvider);
  }
}

/// Ids of blocked users, for cheap membership checks in widgets. Empty while
/// loading or on error, so rows never flash as blocked.
@riverpod
Set<String> blockedUserIds(Ref ref) {
  final users = ref.watch(blockedUsersProvider).valueOrNull ?? const [];
  return {for (final u in users) u.userId};
}
