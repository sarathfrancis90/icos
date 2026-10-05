// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'blocked_user.freezed.dart';
part 'blocked_user.g.dart';

String _nameOrPlayer(Object? value) {
  final name = value?.toString().trim() ?? '';
  return name.isEmpty ? 'Player' : name;
}

/// Row returned by the `list_blocked_users()` RPC.
@freezed
sealed class BlockedUser with _$BlockedUser {
  const factory BlockedUser({
    required String userId,
    @JsonKey(fromJson: _nameOrPlayer) @Default('Player') String displayName,
    required DateTime blockedAt,
  }) = _BlockedUser;

  factory BlockedUser.fromJson(Map<String, dynamic> json) =>
      _$BlockedUserFromJson(json);
}
