import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/backend_providers.dart';
import '../../../core/services/edge_function_client.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/group_repository.dart';
import '../domain/models/group.dart';

part 'groups_provider.g.dart';

@riverpod
GroupRepository groupRepository(Ref ref) {
  return GroupRepository(
    client: () => ref.read(dataApiProvider).client,
    invoker: ref.watch(edgeInvokerProvider),
    userId: () => ref.read(authClientProvider).currentUser?.id,
  );
}

/// Minimal auth snapshot the groups feature needs. Overridable in widget
/// tests so screens never touch the auth client directly.
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
  final user =
      ref.watch(authNotifierProvider).valueOrNull ??
      ref.read(authClientProvider).currentUser;
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
        state = AsyncValue<List<Group>>.error(
          error,
          StackTrace.current,
        ).copyWithPrevious(state);
    }
  }

  /// Refetches the list and reports whether [groupId] is still in it:
  /// `true`/`false`, or `null` when the fetch failed (state is left as is).
  /// Used by the detail screen to refresh the member count and to notice
  /// removal by an admin.
  Future<bool?> refreshMembership(String groupId) async {
    final result = await ref.read(groupRepositoryProvider).getMyGroups();
    switch (result) {
      case Success(data: final groups):
        state = AsyncValue.data(groups);
        return groups.any((g) => g.id == groupId);
      case Failure():
        return null;
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
    final result = await ref
        .read(groupRepositoryProvider)
        .joinGroup(inviteCode);
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

  /// Admin-only: swaps the group's invite code. The updated group replaces
  /// the cached one, so the detail screen and list refresh in place.
  Future<Result<Group, AppError>> regenerateInviteCode(String groupId) async {
    final result = await ref
        .read(groupRepositoryProvider)
        .regenerateInviteCode(groupId);
    if (result case Success(data: final group)) {
      _upsertLocal(group);
    }
    return result;
  }

  void _upsertLocal(Group group) {
    final current = state.valueOrNull ?? const <Group>[];
    final index = current.indexWhere((g) => g.id == group.id);
    if (index == -1) {
      state = AsyncValue.data([group, ...current]);
    } else {
      // Known group: replace in place so the list order stays stable.
      state = AsyncValue.data([...current]..[index] = group);
    }
    // groupDetailProvider watches this list, so it refreshes on its own.
    // Invalidating it from here creates a Riverpod circular dependency.
  }

  void _removeLocal(String groupId) {
    final current = state.valueOrNull ?? const <Group>[];
    state = AsyncValue.data(current.where((g) => g.id != groupId).toList());
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
  final result = await ref
      .read(groupRepositoryProvider)
      .getGroupMembers(groupId);
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

/// How often the activity feed is polled while events keep arriving.
const feedPollInterval = Duration(seconds: 15);

/// Poll interval once the feed has been quiet for [feedPollSlowAfter] polls.
const feedPollSlowInterval = Duration(seconds: 60);

/// Consecutive polls without a new event before slowing to
/// [feedPollSlowInterval].
const feedPollSlowAfter = 20;

/// Consecutive polls without a new event before polling stops until
/// [GroupFeedPoller.startFeedPolling] runs again or the app is resumed.
const feedPollStopAfter = 30;

/// Runs a poll callback while started and the app is in the foreground.
///
/// The callback reports whether the poll found at least one new event. The
/// poller polls every [interval] while events keep arriving, slows to
/// [slowInterval] after [slowAfter] consecutive empty polls and stops after
/// [stopAfter] (each Data API call wakes and bills the Free-plan compute).
/// Backgrounding the app ([AppLifecycleState.paused], `hidden`, `detached`)
/// cancels the timer; returning to [AppLifecycleState.resumed] resets the
/// counters, polls once at once and restarts at [interval].
class GroupFeedPoller with WidgetsBindingObserver {
  GroupFeedPoller(
    this._poll, {
    this.interval = feedPollInterval,
    this.slowInterval = feedPollSlowInterval,
    this.slowAfter = feedPollSlowAfter,
    this.stopAfter = feedPollStopAfter,
  });

  final Future<bool> Function(String groupId) _poll;
  final Duration interval;
  final Duration slowInterval;
  final int slowAfter;
  final int stopAfter;

  Timer? _timer;
  String? _groupId;
  bool _foreground = true;
  bool _observing = false;
  int _emptyPolls = 0;
  Duration _current = feedPollInterval;

  /// True while a timer is scheduled.
  bool get isPolling => _timer?.isActive ?? false;

  /// The interval of the scheduled timer (or of the last one).
  Duration get currentInterval => _current;

  /// Consecutive polls that returned no new event.
  int get emptyPolls => _emptyPolls;

  void startFeedPolling(String groupId) {
    _groupId = groupId;
    final binding = WidgetsBinding.instance;
    if (!_observing) {
      binding.addObserver(this);
      _observing = true;
    }
    final state = binding.lifecycleState;
    _foreground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _restart();
  }

  void stopFeedPolling() {
    _cancel();
    _groupId = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_foreground) return;
        _foreground = true;
        final groupId = _groupId;
        if (groupId == null) return;
        _restart();
        unawaited(_run(groupId));
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        _cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Resets the counters and schedules at [interval].
  void _restart() {
    _emptyPolls = 0;
    _schedule(interval);
  }

  void _schedule(Duration every) {
    _cancel();
    _current = every;
    final groupId = _groupId;
    if (groupId == null || !_foreground) return;
    _timer = Timer.periodic(every, (_) => unawaited(_run(groupId)));
  }

  Future<void> _run(String groupId) async {
    bool fresh;
    try {
      fresh = await _poll(groupId);
    } on Object {
      fresh = false;
    }
    // Stopped, backgrounded or switched group while the poll was in flight.
    if (_groupId != groupId || !_foreground) return;
    if (fresh) {
      _emptyPolls = 0;
      if (_current != interval || !isPolling) _schedule(interval);
      return;
    }
    _emptyPolls++;
    if (_emptyPolls >= stopAfter) {
      _cancel();
    } else if (_emptyPolls >= slowAfter && _current != slowInterval) {
      _schedule(slowInterval);
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Activity feed for [groupId].
///
/// Emits the latest 50 events, then polls `group_feed` for rows newer than
/// the newest one held (`id=gt.<lastId>`) every [feedPollInterval] while the
/// provider is alive (the group screen is mounted) and the app is in the
/// foreground, backing off when the feed is quiet (see [GroupFeedPoller]).
/// New rows are prepended and invalidate the daily/weekly leaderboards so
/// ranks refresh; the screen rechecks membership when the
/// newest event changes. Polling stops when the provider is disposed.
@riverpod
Stream<List<GroupFeedEvent>> groupFeed(Ref ref, String groupId) {
  final repo = ref.read(groupRepositoryProvider);
  final controller = StreamController<List<GroupFeedEvent>>();
  var events = <GroupFeedEvent>[];
  var loaded = false;
  var inFlight = false;
  var disposed = false;

  void emit(List<GroupFeedEvent> next) {
    if (disposed || controller.isClosed) return;
    events = next;
    controller.add(List.unmodifiable(events));
  }

  /// Loads (first call) or polls the feed; true when a new event arrived.
  Future<bool> fetch(String id) async {
    if (disposed || inFlight) return false;
    inFlight = true;
    try {
      final afterId = loaded && events.isNotEmpty ? events.first.id : null;
      final result = await repo.getGroupFeed(id, afterId: afterId);
      if (disposed) return false;
      switch (result) {
        case Success(data: final incoming):
          final wasLoaded = loaded;
          loaded = true;
          if (!wasLoaded) {
            emit(incoming);
            return incoming.isNotEmpty;
          }
          final known = {for (final e in events) e.id};
          final fresh = [
            for (final e in incoming)
              if (!known.contains(e.id)) e,
          ];
          if (fresh.isEmpty) return false;
          emit(
            [
              ...fresh,
              ...events,
            ].take(GroupRepository.defaultFeedLimit).toList(),
          );
          ref.invalidate(dailyLeaderboardProvider);
          ref.invalidate(weeklyLeaderboardProvider);
          return true;
        case Failure(error: final error):
          // A failed poll keeps the current list; only a first load with
          // nothing to show surfaces the error.
          if (!loaded && events.isEmpty && !controller.isClosed) {
            controller.addError(error, StackTrace.current);
          }
          return false;
      }
    } finally {
      inFlight = false;
    }
  }

  final poller = GroupFeedPoller(fetch)..startFeedPolling(groupId);

  ref.onDispose(() {
    disposed = true;
    poller.stopFeedPolling();
    unawaited(controller.close());
  });

  unawaited(fetch(groupId));
  return controller.stream;
}
