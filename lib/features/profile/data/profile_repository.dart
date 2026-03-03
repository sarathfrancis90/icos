import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/models/profile.dart';

class ProfileRepository {
  /// Fetch user profile from Supabase profiles table.
  Future<Result<UserProfile, AppError>> getProfile(String userId) async {
    try {
      final response = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return const Result.failure(
          AppError.notFound('Profile not found'),
        );
      }

      return Result.success(UserProfile.fromJson(response));
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Update profile fields (display name, avatar, colorblind mode).
  Future<Result<UserProfile, AppError>> updateProfile(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? colorblindMode,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (displayName != null) updates['display_name'] = displayName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (colorblindMode != null) updates['colorblind_mode'] = colorblindMode;

      final response = await SupabaseService.client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .single();

      return Result.success(UserProfile.fromJson(response));
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Update settings fields (haptic, sound, theme, notifications).
  Future<Result<UserProfile, AppError>> updateSettings(
    String userId, {
    bool? hapticEnabled,
    bool? soundEnabled,
    String? themeMode,
    bool? notificationEnabled,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (hapticEnabled != null) updates['haptic_enabled'] = hapticEnabled;
      if (soundEnabled != null) updates['sound_enabled'] = soundEnabled;
      if (themeMode != null) updates['theme_mode'] = themeMode;
      if (notificationEnabled != null) {
        updates['notification_enabled'] = notificationEnabled;
      }

      final response = await SupabaseService.client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .single();

      return Result.success(UserProfile.fromJson(response));
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Soft delete account by setting deleted_at timestamp.
  /// The account will be permanently deleted after a 30-day grace period.
  Future<Result<void, AppError>> deleteAccount(String userId) async {
    try {
      await SupabaseService.client.from('profiles').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      return const Result.success(null);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }
}
