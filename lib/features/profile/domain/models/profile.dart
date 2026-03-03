import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@Freezed(fromJson: true, toJson: true)
abstract class UserProfile with _$UserProfile {
  // ignore: invalid_annotation_target
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory UserProfile({
    required String id,
    required String displayName,
    String? avatarUrl,
    @Default(true) bool isAnonymous,
    @Default(false) bool isBanned,
    @Default('none') String colorblindMode,
    @Default('system') String themeMode,
    @Default(true) bool hapticEnabled,
    @Default(true) bool soundEnabled,
    @Default(true) bool notificationEnabled,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}
