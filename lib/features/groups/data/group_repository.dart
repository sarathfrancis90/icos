import 'dart:io';

import 'package:postgrest/postgrest.dart';

import '../../../core/backend/data_api.dart';
import '../../../core/services/edge_function_client.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/invite_code.dart';
import '../domain/models/blocked_user.dart';
import '../domain/models/group.dart';
import 'group_parsers.dart';

/// Data access for groups, membership, leaderboards, the activity feed and
/// content reports.
///
/// Every mutation goes through a Data API RPC or a server route so that
/// invite codes, `member_count`, admin transfer and soft-delete are enforced
/// by the database, never by the client. All methods return
/// `Result<T, AppError>` and never throw.
class GroupRepository {
  static const _groupsTable = 'groups';
  static const _groupMembersTable = 'group_members';
  static const _groupFeedTable = 'group_feed';

  static const groupColumns = 'id, name, description, invite_code, admin_id, '
      'member_count, max_members, is_active, created_at';
  static const memberColumns =
      'id, group_id, user_id, role, joined_at, profiles(display_name, avatar_url)';
  static const feedColumns = '*, profiles(display_name, avatar_url)';

  /// Default page size for the activity feed.
  static const defaultFeedLimit = 50;

  /// [client] resolves the Data API (PostgREST) client (tables + RPCs);
  /// [invoker] calls the server routes (`join-group`, `report`, `block`,
  /// `unblock`); [userId] reads the signed-in user's id.
  GroupRepository({
    required PostgrestClientGetter client,
    required EdgeInvoker invoker,
    required String? Function() userId,
  })  : _clientGetter = client,
        _invoke = invoker,
        _currentUserId = userId;

  final PostgrestClientGetter _clientGetter;
  final EdgeInvoker _invoke;
  final String? Function() _currentUserId;

  PostgrestClient get _client => _clientGetter();

  String? get _userId => _currentUserId();

  // ─── Group lifecycle ───────────────────────────────────────────────

  /// Creates a group via the `create_group` RPC. The server sanitises the
  /// name, generates the invite code and adds the caller as admin.
  Future<Result<Group, AppError>> createGroup({
    required String name,
    required String description,
  }) {
    return _guard(() async {
      if (_userId == null) {
        throw const AppErrorException(
          AppError.auth('You must be signed in to create a group'),
        );
      }
      final response = await _client.rpc<dynamic>(
        'create_group',
        params: {
          'p_name': name.trim(),
          'p_description': description.trim(),
        },
      );
      return GroupParsers.parseGroupRow(response);
    });
  }

  /// Joins a group via the `join-group` route.
  ///
  /// `ALREADY_MEMBER` is treated as success (the existing group is fetched).
  Future<Result<Group, AppError>> joinGroup(String inviteCode) {
    return _guard(() async {
      final validation = InviteCode.validate(inviteCode);
      if (validation != null) {
        throw AppErrorException(AppError.validation(validation));
      }
      if (_userId == null) {
        throw const AppErrorException(
          AppError.auth('You must be signed in to join a group'),
        );
      }
      final code = InviteCode.normalize(inviteCode);

      final response = await _invoke('join-group', {'invite_code': code});
      if (_isSuccess(response.status)) {
        return GroupParsers.parseJoinGroupResponse(response.body);
      }
      final failure =
          GroupParsers.parseJoinGroupError(response.status, response.body);
      if (failure.code == JoinGroupErrorCode.alreadyMember) {
        final existing = failure.groupId != null
            ? await _fetchGroup(failure.groupId!)
            : await _fetchGroupByInviteCode(code);
        if (existing != null) return existing;
      }
      throw AppErrorException(failure.error);
    });
  }

  /// Leaves the group via the `leave_group` RPC (admin leaving auto-transfers
  /// or deactivates server-side).
  Future<Result<void, AppError>> leaveGroup(String groupId) {
    return _guard(() => _rpcVoid('leave_group', {'p_group_id': groupId}));
  }

  /// Admin-only: removes [userId] from the group.
  Future<Result<void, AppError>> removeMember({
    required String groupId,
    required String userId,
  }) {
    return _guard(
      () => _rpcVoid('remove_group_member', {
        'p_group_id': groupId,
        'p_user_id': userId,
      }),
    );
  }

  /// Admin-only: hands admin rights to [newAdminId].
  Future<Result<void, AppError>> transferAdmin({
    required String groupId,
    required String newAdminId,
  }) {
    return _guard(
      () => _rpcVoid('transfer_group_admin', {
        'p_group_id': groupId,
        'p_new_admin_id': newAdminId,
      }),
    );
  }

  /// Admin-only: soft-deletes the group (`is_active = false`).
  Future<Result<void, AppError>> deleteGroup(String groupId) {
    return _guard(() => _rpcVoid('delete_group', {'p_group_id': groupId}));
  }

  /// Admin-only: replaces the invite code via the `regenerate_invite_code`
  /// RPC. The old code stops working immediately; returns the updated group.
  Future<Result<Group, AppError>> regenerateInviteCode(String groupId) {
    return _guard(() async {
      if (_userId == null) {
        throw const AppErrorException(AppError.auth('You must be signed in'));
      }
      final response = await _client.rpc<dynamic>(
        'regenerate_invite_code',
        params: {'p_group_id': groupId},
      );
      return GroupParsers.parseGroupRow(response);
    });
  }

  // ─── Reads ─────────────────────────────────────────────────────────

  /// Active groups the current user belongs to, newest first.
  Future<Result<List<Group>, AppError>> getMyGroups() {
    return _guard(() async {
      final userId = _userId;
      if (userId == null) return const <Group>[];

      final memberRows = await _client
          .from(_groupMembersTable)
          .select('group_id')
          .eq('user_id', userId);
      final groupIds = memberRows
          .map((row) => row['group_id']?.toString())
          .whereType<String>()
          .toList();
      if (groupIds.isEmpty) return const <Group>[];

      final groupRows = await _client
          .from(_groupsTable)
          .select(groupColumns)
          .inFilter('id', groupIds)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      return groupRows.map(Group.fromJson).toList();
    }, onDatabaseError: (e) {
      // A brand-new user with no memberships can hit RLS before the
      // profile row exists; treat as "no groups" rather than an error.
      if (e.code == '42501' || e.code == 'PGRST301') {
        return const Result.success(<Group>[]);
      }
      return null;
    });
  }

  /// A single active group the user can see (membership enforced by RLS).
  Future<Result<Group, AppError>> getGroup(String groupId) {
    return _guard(() async {
      final group = await _fetchGroup(groupId);
      if (group == null) {
        throw const AppErrorException(AppError.notFound('Group not found'));
      }
      return group;
    });
  }

  Future<Result<List<GroupMember>, AppError>> getGroupMembers(String groupId) {
    return _guard(() async {
      final rows = await _client
          .from(_groupMembersTable)
          .select(memberColumns)
          .eq('group_id', groupId)
          .order('joined_at', ascending: true);
      return GroupParsers.parseMembers(rows);
    });
  }

  /// `get_group_daily_leaderboard(p_group_id, p_puzzle_date)`.
  Future<Result<List<GroupLeaderboardEntry>, AppError>> getGroupDailyLeaderboard(
    String groupId,
    String puzzleDate,
  ) {
    return _guard(() async {
      final response = await _client.rpc<dynamic>(
        'get_group_daily_leaderboard',
        params: {
          'p_group_id': groupId,
          'p_puzzle_date': puzzleDate,
        },
      );
      return GroupParsers.parseDailyLeaderboard(response);
    });
  }

  /// `get_group_weekly_leaderboard(p_group_id, p_week_start)`.
  Future<Result<List<WeeklyLeaderboardEntry>, AppError>>
      getGroupWeeklyLeaderboard(String groupId, String weekStart) {
    return _guard(() async {
      final response = await _client.rpc<dynamic>(
        'get_group_weekly_leaderboard',
        params: {
          'p_group_id': groupId,
          'p_week_start': weekStart,
        },
      );
      return GroupParsers.parseWeeklyLeaderboard(response);
    });
  }

  /// Most recent [limit] activity events for the group, newest first
  /// (`order=id.desc`; ids are a bigint identity, so newer rows have larger
  /// ids). With [afterId] only rows with `id > afterId` are returned (the
  /// feed poll's incremental fetch).
  Future<Result<List<GroupFeedEvent>, AppError>> getGroupFeed(
    String groupId, {
    int limit = defaultFeedLimit,
    String? afterId,
  }) {
    return _guard(() async {
      var query = _client
          .from(_groupFeedTable)
          .select(feedColumns)
          .eq('group_id', groupId);
      if (afterId != null) query = query.gt('id', afterId);
      final rows = await query.order('id', ascending: false).limit(limit);
      return GroupParsers.parseFeed(rows);
    });
  }

  // ─── Blocking ──────────────────────────────────────────────────────

  /// Blocks [userId] via `POST /api/block`. Their scores and activity are
  /// hidden from the caller server-side; the developer is notified through a
  /// `reports` row the route files.
  Future<Result<void, AppError>> blockUser(String userId) {
    return _guard(() => _routeVoid('block', {'user_id': userId}));
  }

  /// Unblocks [userId] via `POST /api/unblock`.
  Future<Result<void, AppError>> unblockUser(String userId) {
    return _guard(() => _routeVoid('unblock', {'user_id': userId}));
  }

  /// The caller's blocked users, newest first (`list_blocked_users`).
  Future<Result<List<BlockedUser>, AppError>> listBlockedUsers() {
    return _guard(() async {
      if (_userId == null) return const <BlockedUser>[];
      final response = await _client.rpc<dynamic>('list_blocked_users');
      return GroupParsers.asRows(response).map(BlockedUser.fromJson).toList();
    });
  }

  // ─── Reports ───────────────────────────────────────────────────────

  /// Files a report via `POST /api/report` (201 `{id}`).
  Future<Result<void, AppError>> reportUser({
    required String userId,
    required String reason,
    String details = '',
  }) {
    return _fileReport({'reported_user_id': userId}, reason, details);
  }

  Future<Result<void, AppError>> reportGroup({
    required String groupId,
    required String reason,
    String details = '',
  }) {
    return _fileReport({'reported_group_id': groupId}, reason, details);
  }

  Future<Result<void, AppError>> _fileReport(
    Map<String, dynamic> target,
    String reason,
    String details,
  ) {
    return _guard(() async {
      if (_userId == null) {
        throw const AppErrorException(
          AppError.auth('You must be signed in to report'),
        );
      }
      await _route('report', {
        ...target,
        'reason': reason,
        'details': details.trim(),
      });
    });
  }

  // ─── Internals ─────────────────────────────────────────────────────

  Future<Group?> _fetchGroup(String groupId) async {
    final row = await _client
        .from(_groupsTable)
        .select(groupColumns)
        .eq('id', groupId)
        .maybeSingle();
    return row == null ? null : Group.fromJson(row);
  }

  Future<Group?> _fetchGroupByInviteCode(String code) async {
    final row = await _client
        .from(_groupsTable)
        .select(groupColumns)
        .eq('invite_code', code)
        .maybeSingle();
    return row == null ? null : Group.fromJson(row);
  }

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  Future<void> _routeVoid(String name, Map<String, dynamic> body) async {
    if (_userId == null) {
      throw const AppErrorException(AppError.auth('You must be signed in'));
    }
    await _route(name, body);
  }

  /// `POST /api/<name>`; a non-2xx answer becomes an [AppErrorException].
  Future<EdgeResponse> _route(String name, Map<String, dynamic> body) async {
    final response = await _invoke(name, body);
    if (_isSuccess(response.status)) return response;
    throw AppErrorException(routeError(response));
  }

  /// Maps a route's `{error, code}` failure to an [AppError].
  static AppError routeError(EdgeResponse response) {
    final raw = response.json?['error'];
    final message = raw is String && raw.isNotEmpty ? raw : null;
    return switch (response.status) {
      400 || 422 => AppError.validation(message ?? 'Invalid request'),
      401 => AppError.auth(message ?? 'You must be signed in'),
      403 => AppError.auth(message ?? 'You do not have permission to do that'),
      404 => AppError.notFound(message ?? 'Not found'),
      429 => AppError.rateLimit(message ?? 'Too many requests'),
      _ => AppError.network('Service unavailable (${response.status})'),
    };
  }

  Future<void> _rpcVoid(String fn, Map<String, dynamic> params) async {
    if (_userId == null) {
      throw const AppErrorException(AppError.auth('You must be signed in'));
    }
    await _client.rpc<dynamic>(fn, params: params);
  }

  /// Runs [body], translating every failure mode into an [AppError].
  Future<Result<T, AppError>> _guard<T>(
    Future<T> Function() body, {
    Result<T, AppError>? Function(PostgrestException e)? onDatabaseError,
  }) async {
    try {
      return Result.success(await body());
    } on AppErrorException catch (e) {
      return Result.failure(e.error);
    } on PostgrestException catch (e) {
      final override = onDatabaseError?.call(e);
      if (override != null) return override;
      return Result.failure(_mapPostgrest(e));
    } on SocketException {
      return const Result.failure(AppError.network('No connection'));
    } on FormatException catch (e) {
      return Result.failure(AppError.unknown(e.message));
    } catch (e) {
      final text = e.toString();
      if (text.contains('SocketException') ||
          text.contains('ClientException') ||
          text.contains('Failed host lookup')) {
        return const Result.failure(AppError.network('No connection'));
      }
      return Result.failure(AppError.unknown(text));
    }
  }

  /// Surfaces `RAISE EXCEPTION` messages from the group RPCs (profanity,
  /// length, not-admin, group full) as validation errors so the UI can show
  /// the server's wording verbatim.
  static AppError _mapPostgrest(PostgrestException e) {
    final code = e.code ?? '';
    if (code == 'P0001' || code.startsWith('P00')) {
      return AppError.validation(e.message);
    }
    if (code == '42501') {
      return const AppError.auth('You do not have permission to do that');
    }
    if (code == 'PGRST116') {
      return const AppError.notFound('Group not found');
    }
    return AppError.database(e.message);
  }
}

/// Internal carrier so `_guard` can unwrap a pre-built [AppError].
class AppErrorException implements Exception {
  const AppErrorException(this.error);
  final AppError error;

  @override
  String toString() => 'AppErrorException($error)';
}
