import 'dart:convert';

import 'package:postgrest/postgrest.dart';

import '../../../core/backend/data_api.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/edge_function_client.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/models/profile.dart';

class ProfileRepository {
  /// [client] resolves the Data API (PostgREST) client; [invoker] calls the
  /// server routes (`export-data`).
  ProfileRepository({
    required PostgrestClientGetter client,
    required EdgeInvoker invoker,
  }) : _clientGetter = client,
       _invoke = invoker;

  final PostgrestClientGetter _clientGetter;
  final EdgeInvoker _invoke;

  PostgrestClient get _client => _clientGetter();

  /// Explicit column list — never `select()` so schema additions (or
  /// sensitive columns) can't leak into the client model unintentionally.
  static const String columns = 'id, display_name, avatar_url, is_anonymous, '
      'is_banned, colorblind_mode, theme_mode, haptic_enabled, sound_enabled, '
      'notification_enabled, deleted_at, created_at, updated_at';

  /// Fetch user profile from the profiles table.
  Future<Result<UserProfile, AppError>> getProfile(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select(columns)
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (displayName != null) updates['display_name'] = displayName;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      if (colorblindMode != null) updates['colorblind_mode'] = colorblindMode;

      final response = await _client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select(columns)
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (hapticEnabled != null) updates['haptic_enabled'] = hapticEnabled;
      if (soundEnabled != null) updates['sound_enabled'] = soundEnabled;
      if (themeMode != null) updates['theme_mode'] = themeMode;
      if (notificationEnabled != null) {
        updates['notification_enabled'] = notificationEnabled;
      }

      final response = await _client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select(columns)
          .single();

      return Result.success(UserProfile.fromJson(response));
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Schedules the account for deletion via the `request_account_deletion`
  /// RPC (server sets `deleted_at`; a cron purges after the 30-day grace
  /// period and anonymises leaderboard rows).
  Future<Result<void, AppError>> requestAccountDeletion() async {
    try {
      await _client.rpc<void>('request_account_deletion');
      return const Result.success(null);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Cancels a pending deletion via the `cancel_account_deletion` RPC.
  Future<Result<void, AppError>> cancelAccountDeletion() async {
    try {
      await _client.rpc<void>('cancel_account_deletion');
      return const Result.success(null);
    } on PostgrestException catch (e) {
      return Result.failure(AppError.database(e.message));
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }

  /// Calls the `export-data` route and returns the user's data as a
  /// JSON-encodable map.
  Future<Result<Map<String, dynamic>, AppError>> exportData() async {
    try {
      final response = await _invoke('export-data', const {});
      if (response.status < 200 || response.status >= 300) {
        AppLogger.warn(
          'export-data failed',
          data: {'status': response.status, 'code': response.code},
        );
        if (response.status == 429) {
          return const Result.failure(
            AppError.rateLimit('Too many export requests'),
          );
        }
        final message = response.json?['error'];
        return Result.failure(
          AppError.database(
            message is String && message.isNotEmpty
                ? message
                : 'Export failed (${response.status})',
          ),
        );
      }
      final data = response.body;
      if (data is Map<String, dynamic>) return Result.success(data);
      if (data is Map) return Result.success(Map<String, dynamic>.from(data));
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return Result.success(decoded);
      }
      return const Result.failure(
        AppError.unknown('Unexpected export format'),
      );
    } catch (e) {
      return Result.failure(AppError.network(e.toString()));
    }
  }
}
