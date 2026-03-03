import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/utils/result.dart';
import '../data/group_repository.dart';
import '../domain/models/group.dart';

part 'groups_provider.g.dart';

@riverpod
GroupRepository groupRepository(Ref ref) {
  return GroupRepository();
}

@riverpod
class MyGroups extends _$MyGroups {
  @override
  Future<List<Group>> build() async {
    final repo = ref.read(groupRepositoryProvider);
    final result = await repo.getMyGroups();
    return switch (result) {
      Success(data: final groups) => groups,
      Failure() => [],
    };
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(groupRepositoryProvider);
      final result = await repo.getMyGroups();
      return switch (result) {
        Success(data: final groups) => groups,
        Failure(error: final error) => throw error,
      };
    });
  }

  Future<Group?> createGroup({
    required String name,
    required String description,
  }) async {
    final repo = ref.read(groupRepositoryProvider);
    final result = await repo.createGroup(name: name, description: description);
    return switch (result) {
      Success(data: final group) => () {
          ref.invalidateSelf();
          return group;
        }(),
      Failure() => null,
    };
  }

  Future<Group?> joinGroup(String inviteCode) async {
    final repo = ref.read(groupRepositoryProvider);
    final result = await repo.joinGroup(inviteCode);
    return switch (result) {
      Success(data: final group) => () {
          ref.invalidateSelf();
          return group;
        }(),
      Failure() => null,
    };
  }

  Future<bool> leaveGroup(String groupId) async {
    final repo = ref.read(groupRepositoryProvider);
    final result = await repo.leaveGroup(groupId);
    return switch (result) {
      Success() => () {
          ref.invalidateSelf();
          return true;
        }(),
      Failure() => false,
    };
  }
}

@riverpod
Future<List<GroupMember>> groupMembers(Ref ref, String groupId) async {
  final repo = ref.read(groupRepositoryProvider);
  final result = await repo.getGroupMembers(groupId);
  return switch (result) {
    Success(data: final members) => members,
    Failure(error: final error) => throw error,
  };
}

@riverpod
Future<List<GroupLeaderboardEntry>> groupDailyLeaderboard(
  Ref ref,
  String groupId,
  String date,
) async {
  final repo = ref.read(groupRepositoryProvider);
  final result = await repo.getGroupDailyLeaderboard(groupId, date);
  return switch (result) {
    Success(data: final entries) => entries,
    Failure(error: final error) => throw error,
  };
}

@riverpod
Future<List<GroupLeaderboardEntry>> groupWeeklyLeaderboard(
  Ref ref,
  String groupId,
  String weekStart,
) async {
  final repo = ref.read(groupRepositoryProvider);
  final result = await repo.getGroupWeeklyLeaderboard(groupId, weekStart);
  return switch (result) {
    Success(data: final entries) => entries,
    Failure(error: final error) => throw error,
  };
}
