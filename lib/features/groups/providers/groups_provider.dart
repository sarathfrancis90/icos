import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/group_repository.dart';
import '../domain/models/group.dart';

part 'groups_provider.g.dart';

@riverpod
GroupRepository groupRepository(Ref ref) => GroupRepository();

/// Minimal auth snapshot the groups feature needs. Overridable in widget
/// tests so screens never touch `Supabase.instance` directly.
class GroupsSession {
  const GroupsSession({required this.userId, required this.isAnonymous});

  const GroupsSession.signedOut() : this(userId: null, isAnonymous: true);

  final String? userId;
  final bool isAnonymous;

  bool get isSignedIn => userId != null;

  /// True when the user can use social features (has a non-anonymous
  /// account).
  bool get canUseGroups => userId != null && !isAnonymous;
}

@riverpod
GroupsSession groupsSession(Ref ref) {
  // Re-evaluate whenever the auth state changes (guest → account link).
  final user = ref.watch(authNotifierProvider).valueOrNull ??
      SupabaseService.auth.currentUser;
  if (user == null) return const GroupsSession.signedOut();
  return GroupsSession(userId: user.id, isAnonymous: user.isAnonymous);
}

T _unwrap<T>(Result<T, AppError> result) => switch (result) {
      Success(data: final data) => data,
      Failure(error: final error) => throw error,
    };

/// The current user's groups. Kept alive across tab switches; rebuilds when
/// the session changes.
@Riverpod(keepAlive: true)
class MyGroups extends _$MyGroups {
  @override
  Future<List<Group>> build() async {
    final session = ref.watch(groupsSessionProvider);
    if (!session.isSignedIn) return const [];
    final result = await ref.read(groupRepositoryProvider).getMyGroups();
    return _unwrap(result);
  }

  /// Pull-to-refresh: refetches without flashing the loading state.
  Future<void> refresh() async {
    final result = await ref.read(groupRepositoryProvider).getMyGroups();
    switch (result) {
      case Success(data: final groups):
        state = AsyncValue.data(groups);
      case Failure(error: final error):
        state = AsyncValue<List<Group>>.error(error, StackTrace.current)
            .copyWithPrevious(state);
    }
  }

  Future<Result<Group, AppError>> createGroup({
    required String name,
    required String description,
  }) async {
    final result = await ref
        .read(groupRepositoryProvider)
        .createGroup(name: name, description: description);
    if (result case Success(data: final group)) {
      _upsertLocal(group);
    }
    return result;
  }

  Future<Result<Group, AppError>> joinGroup(String inviteCode) async {
    final result = await ref.read(groupRepositoryProvider).joinGroup(inviteCode);
    if (result case Success(data: final group)) {
      _upsertLocal(group);
    }
    return result;
  }

  Future<Result<void, AppError>> leaveGroup(String groupId) async {
    final result = await ref.read(groupRepositoryProvider).leaveGroup(groupId);
    if (result is Success) _removeLocal(groupId);
    return result;
  }

  Future<Result<void, AppError>> deleteGroup(String groupId) async {
    final result = await ref.read(groupRepositoryProvider).deleteGroup(groupId);
    if (result is Success) _removeLocal(groupId);
    return result;
  }

  void _upsertLocal(Group group) {
    final current = state.valueOrNull ?? const <Group>[];
    final others = current.where((g) => g.id != group.id);
    state = AsyncValue.data([group, ...others]);
    ref.invalidate(groupDetailProvider(group.id));
  }

  void _removeLocal(String groupId) {
    final current = state.valueOrNull ?? const <Group>[];
    state = AsyncValue.data(current.where((g) => g.id != groupId).toList());
    ref.invalidate(groupDetailProvider(groupId));
  }
}

/// A single group. Served from the cached list when available, otherwise
/// fetched (e.g. arriving via deep link before the list has loaded).
@riverpod
Future<Group> groupDetail(Ref ref, String groupId) async {
  final cached = ref
      .watch(myGroupsProvider)
      .valueOrNull
      ?.where((g) => g.id == groupId)
      .firstOrNull;
  if (cached != null) return cached;
  final result = await ref.read(groupRepositoryProvider).getGroup(groupId);
  return _unwrap(result);
}

@riverpod
Future<List<GroupMember>> groupMembers(Ref ref, String groupId) async {
  final result = await ref.read(groupRepositoryProvider).getGroupMembers(groupId);
  return _unwrap(result);
}

@riverpod
Future<List<GroupLeaderboardEntry>> dailyLeaderboard(
  Ref ref,
  String groupId,
  String puzzleDate,
) async {
  final result = await ref
      .read(groupRepositoryProvider)
      .getGroupDailyLeaderboard(groupId, puzzleDate);
  return _unwrap(result);
}

@riverpod
Future<List<WeeklyLeaderboardEntry>> weeklyLeaderboard(
  Ref ref,
  String groupId,
  String weekStart,
) async {
  final result = await ref
      .read(groupRepositoryProvider)
      .getGroupWeeklyLeaderboard(groupId, weekStart);
  return _unwrap(result);
}

/// The single realtime channel the groups feature is allowed to hold.
/// Opening a feed for another group tears the previous one down first.
RealtimeChannel? _activeFeedChannel;

/// Live activity feed for [groupId].
///
/// Emits the initial 50 events, then re-emits whenever a `group_feed` row is
/// inserted for this group (via Supabase realtime `postgres_changes`). Each
/// insert also invalidates the daily/weekly leaderboards so ranks refresh.
/// The channel is unsubscribed when the provider is disposed.
@riverpod
Stream<List<GroupFeedEvent>> groupFeed(Ref ref, String groupId) {
  final repo = ref.read(groupRepositoryProvider);
  final controller = StreamController<List<GroupFeedEvent>>();
  var events = <GroupFeedEvent>[];
  var disposed = false;

  void emit(List<GroupFeedEvent> next) {
    if (disposed || controller.isClosed) return;
    events = next;
    controller.add(List.unmodifiable(events));
  }

  Future<void> reload() async {
    final result = await repo.getGroupFeed(groupId);
    if (disposed) return;
    switch (result) {
      case Success(data: final list):
        emit(list);
      case Failure(error: final error):
        if (events.isEmpty && !controller.isClosed) {
          controller.addError(error, StackTrace.current);
        }
    }
  }

  void onInsert(PostgresChangePayload payload) {
    if (disposed) return;
    // Show the row immediately (profile join is not part of the realtime
    // payload), then reconcile with a full fetch to pick up display names.
    try {
      final incoming = GroupFeedEvent.fromJson(payload.newRecord);
      if (!events.any((e) => e.id == incoming.id)) {
        emit([incoming, ...events].take(GroupRepository.defaultFeedLimit).toList());
      }
    } catch (_) {
      // Malformed payload; the reload below is authoritative.
    }
    ref.invalidate(dailyLeaderboardProvider);
    ref.invalidate(weeklyLeaderboardProvider);
    unawaited(reload());
  }

  // Enforce "at most one channel active" for the groups feature.
  final previous = _activeFeedChannel;
  if (previous != null) {
    unawaited(previous.unsubscribe());
    _activeFeedChannel = null;
  }

  final channel = SupabaseService.client
      .channel('group_feed:$groupId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'group_feed',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: groupId,
        ),
        callback: onInsert,
      )
      .subscribe();
  _activeFeedChannel = channel;

  ref.onDispose(() {
    disposed = true;
    if (identical(_activeFeedChannel, channel)) _activeFeedChannel = null;
    unawaited(channel.unsubscribe());
    unawaited(controller.close());
  });

  unawaited(reload());
  return controller.stream;
}
