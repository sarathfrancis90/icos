import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/models/group.dart';

class GroupRepository {
  static const _groupsTable = 'groups';
  static const _groupMembersTable = 'group_members';

  /// Creates a new group and adds the current user as admin.
  Future<Result<Group, AppError>> createGroup({
    required String name,
    required String description,
  }) async {
    try {
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId == null) {
        return const Result.failure(AppError.auth('You must be signed in to create a group'));
      }

      final inviteCode = _generateInviteCode();

      final response = await SupabaseService.client
          .from(_groupsTable)
          .insert({
            'name': name,
            'description': description,
            'invite_code': inviteCode,
            'admin_id': userId,
            'member_count': 1,
            'max_members': AppSizes.maxGroupMembers,
            'is_active': true,
          })
          .select()
          .single();

      // Add creator as admin member
      await SupabaseService.client.from(_groupMembersTable).insert({
        'group_id': response['id'],
        'user_id': userId,
        'role': 'admin',
      });

      return Result.success(Group.fromJson(response));
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.unknown(e.toString()));
    }
  }

  /// Joins a group using an invite code via Edge Function.
  Future<Result<Group, AppError>> joinGroup(String inviteCode) async {
    try {
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId == null) {
        return const Result.failure(AppError.auth('You must be signed in to join a group'));
      }

      final response = await SupabaseService.functions.invoke(
        'join-group',
        body: {'invite_code': inviteCode.toUpperCase()},
      );

      if (response.status != 200) {
        final body = jsonDecode(response.data as String) as Map<String, dynamic>;
        final message = body['error'] as String? ?? 'Failed to join group';
        return Result.failure(AppError.validation(message));
      }

      final body = jsonDecode(response.data as String) as Map<String, dynamic>;
      final group = Group.fromJson(body['group'] as Map<String, dynamic>);
      return Result.success(group);
    } on FunctionException catch (e) {
      return Result.failure(AppError.network(e.toString()));
    } catch (e) {
      return Result.failure(AppError.unknown(e.toString()));
    }
  }

  /// Leaves a group. Removes membership and decrements member count.
  Future<Result<void, AppError>> leaveGroup(String groupId) async {
    try {
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId == null) {
        return const Result.failure(AppError.auth('You must be signed in'));
      }

      await SupabaseService.client
          .from(_groupMembersTable)
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);

      await SupabaseService.client.rpc<void>('decrement_group_member_count', params: {
        'p_group_id': groupId,
      });

      return const Result.success(null);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.unknown(e.toString()));
    }
  }

  /// Fetches all groups the current user belongs to.
  Future<Result<List<Group>, AppError>> getMyGroups() async {
    try {
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId == null) {
        return const Result.failure(AppError.auth('You must be signed in'));
      }

      final memberRows = await SupabaseService.client
          .from(_groupMembersTable)
          .select('group_id')
          .eq('user_id', userId);

      if (memberRows.isEmpty) {
        return const Result.success([]);
      }

      final groupIds =
          memberRows.map((row) => row['group_id'] as String).toList();

      final groupRows = await SupabaseService.client
          .from(_groupsTable)
          .select()
          .inFilter('id', groupIds)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final groups = groupRows.map((row) => Group.fromJson(row)).toList();
      return Result.success(groups);
    } on PostgrestException catch (e) {
      // If it's an RLS error for a new user, return empty list
      if (e.code == '42501' || e.code == 'PGRST301') {
        return const Result.success([]);
      }
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Fetches members of a group with profile data.
  Future<Result<List<GroupMember>, AppError>> getGroupMembers(
    String groupId,
  ) async {
    try {
      final response = await SupabaseService.client
          .from(_groupMembersTable)
          .select('*, profiles(display_name, avatar_url)')
          .eq('group_id', groupId)
          .order('joined_at', ascending: true);

      final members = response.map((row) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        return GroupMember.fromJson({
          ...row,
          'display_name': profile?['display_name'],
          'avatar_url': profile?['avatar_url'],
        });
      }).toList();

      return Result.success(members);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Fetches the daily leaderboard for a group using an RPC call.
  Future<Result<List<GroupLeaderboardEntry>, AppError>>
      getGroupDailyLeaderboard(String groupId, String date) async {
    try {
      final response = await SupabaseService.client.rpc<List<dynamic>>(
        'get_group_daily_leaderboard',
        params: {
          'p_group_id': groupId,
          'p_date': date,
        },
      );

      final entries = response
          .map((row) =>
              GroupLeaderboardEntry.fromJson(row as Map<String, dynamic>))
          .toList();

      return Result.success(entries);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Fetches the weekly leaderboard for a group using an RPC call.
  Future<Result<List<GroupLeaderboardEntry>, AppError>>
      getGroupWeeklyLeaderboard(String groupId, String weekStart) async {
    try {
      final response = await SupabaseService.client.rpc<List<dynamic>>(
        'get_group_weekly_leaderboard',
        params: {
          'p_group_id': groupId,
          'p_week_start': weekStart,
        },
      );

      final entries = response
          .map((row) =>
              GroupLeaderboardEntry.fromJson(row as Map<String, dynamic>))
          .toList();

      return Result.success(entries);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Generates a 6-character uppercase alphanumeric invite code.
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(
      AppSizes.inviteCodeLength,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
