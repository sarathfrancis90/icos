import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/analytics_service.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/profile_repository.dart';
import '../domain/models/profile.dart';

part 'profile_provider.g.dart';

@riverpod
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository();
}

@riverpod
Future<UserProfile?> profile(Ref ref) async {
  final user = SupabaseService.auth.currentUser;
  if (user == null) return null;

  final repo = ref.read(profileRepositoryProvider);
  final result = await repo.getProfile(user.id);
  return switch (result) {
    Success(data: final profile) => profile,
    Failure() => null,
  };
}

/// Set to true (once) when a pending account deletion was automatically
/// cancelled after sign-in. UI shows a "Deletion cancelled" SnackBar and
/// calls [DeletionCancelledFlag.consume].
@Riverpod(keepAlive: true)
class DeletionCancelledFlag extends _$DeletionCancelledFlag {
  @override
  bool build() => false;

  void raise() => state = true;

  void consume() => state = false;
}

/// True when the signed-in profile is banned. The router should redirect
/// to `BannedScreen` when this is true.
@riverpod
bool isBanned(Ref ref) =>
    ref.watch(profileNotifierProvider).valueOrNull?.isBanned ?? false;

@riverpod
class ProfileNotifier extends _$ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() {
    // Reload whenever the signed-in user changes (guest → account, sign out).
    ref.watch(authNotifierProvider.select((s) => s.valueOrNull?.id));
    _loadProfile();
    return const AsyncValue.loading();
  }

  Future<void> _loadProfile() async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      state = const AsyncValue.data(null);
      return;
    }

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.getProfile(user.id);
    switch (result) {
      case Success(data: final profile):
        if (profile.deletedAt != null) {
          await _autoCancelDeletion(repo, user.id, profile);
        } else {
          state = AsyncValue.data(profile);
        }
      case Failure():
        state = const AsyncValue.data(null);
    }
  }

  /// A user who signs in during the grace period wants to keep the account.
  Future<void> _autoCancelDeletion(
    ProfileRepository repo,
    String userId,
    UserProfile profile,
  ) async {
    final cancel = await repo.cancelAccountDeletion();
    switch (cancel) {
      case Success():
        AppLogger.info('Pending account deletion cancelled on sign-in');
        await AnalyticsService.logEvent(AnalyticsEvents.accountDeleteCancelled);
        final refreshed = await repo.getProfile(userId);
        state = switch (refreshed) {
          Success(data: final p) => AsyncValue.data(p),
          Failure() => AsyncValue.data(profile.copyWith(deletedAt: null)),
        };
        ref.read(deletionCancelledFlagProvider.notifier).raise();
      case Failure(error: final e):
        AppLogger.warn('Cancelling pending deletion failed', error: e);
        state = AsyncValue.data(profile);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadProfile();
  }

  Future<Result<UserProfile, AppError>> updateDisplayName(
    String displayName,
  ) async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.updateProfile(
      user.id,
      displayName: displayName,
    );

    switch (result) {
      case Success(data: final profile):
        state = AsyncValue.data(profile);
        await AnalyticsService.logEvent(AnalyticsEvents.displayNameChanged);
      case Failure():
        break;
    }
    return result;
  }

  Future<Result<UserProfile, AppError>> updateColorblindMode(
    String mode,
  ) async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.updateProfile(
      user.id,
      colorblindMode: mode,
    );

    switch (result) {
      case Success(data: final profile):
        state = AsyncValue.data(profile);
        await StorageService.setColorblindMode(mode);
      case Failure():
        break;
    }
    return result;
  }

  Future<Result<UserProfile, AppError>> updateHaptic(bool enabled) async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

    // Update local storage immediately for responsiveness
    await StorageService.setHapticEnabled(enabled);

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.updateSettings(
      user.id,
      hapticEnabled: enabled,
    );

    switch (result) {
      case Success(data: final profile):
        state = AsyncValue.data(profile);
      case Failure():
        // Local storage is already updated, so the setting still works locally
        break;
    }
    return result;
  }

  Future<Result<UserProfile, AppError>> updateSound(bool enabled) async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

    await StorageService.setSoundEnabled(enabled);

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.updateSettings(
      user.id,
      soundEnabled: enabled,
    );

    switch (result) {
      case Success(data: final profile):
        state = AsyncValue.data(profile);
      case Failure():
        break;
    }
    return result;
  }

  /// Toggles the daily reminder locally (schedule/cancel) and mirrors the
  /// flag to the profile. Returns false when OS permission was denied.
  Future<bool> updateNotification(bool enabled, {TimeOfDay? time}) async {
    if (enabled) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        await NotificationService.cancelReminder();
        return false;
      }
      await NotificationService.scheduleDailyReminder(
        time ?? await NotificationService.reminderTime(),
      );
    } else {
      await NotificationService.cancelReminder();
      await NotificationService.cancelStreakReminder();
    }

    final user = SupabaseService.auth.currentUser;
    if (user == null) return enabled;

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.updateSettings(
      user.id,
      notificationEnabled: enabled,
    );
    switch (result) {
      case Success(data: final profile):
        state = AsyncValue.data(profile);
      case Failure():
        break;
    }
    return true;
  }

  Future<void> updateReminderTime(TimeOfDay time) async {
    await NotificationService.scheduleDailyReminder(time);
    ref.invalidate(reminderSettingsProvider);
  }

  /// Requests deletion (30-day grace) then signs out.
  Future<Result<void, AppError>> deleteAccount() async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.requestAccountDeletion();
    if (result is Success) {
      await AnalyticsService.logEvent(AnalyticsEvents.accountDeleteRequested);
      await NotificationService.cancelReminder();
      await NotificationService.cancelStreakReminder();
      await ref.read(authNotifierProvider.notifier).signOut();
    }
    return result;
  }

  /// Explicit cancel (e.g. from a banner) — normally handled automatically
  /// on sign-in.
  Future<Result<void, AppError>> cancelAccountDeletion() async {
    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.cancelAccountDeletion();
    if (result is Success) {
      await AnalyticsService.logEvent(AnalyticsEvents.accountDeleteCancelled);
      await refresh();
    }
    return result;
  }

  /// Downloads the user's data via the `export-data` edge function and
  /// writes it to a JSON file in the temp directory. Returns the file.
  Future<Result<File, AppError>> exportData() async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }
    final repo = ref.read(profileRepositoryProvider);
    final result = await repo.exportData();
    switch (result) {
      case Success(data: final data):
        try {
          final dir = await getTemporaryDirectory();
          final stamp = DateTime.now()
              .toUtc()
              .toIso8601String()
              .replaceAll(':', '-')
              .split('.')
              .first;
          final file = File('${dir.path}/icos-export-$stamp.json');
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
          );
          await AnalyticsService.logEvent(AnalyticsEvents.dataExport);
          return Result.success(file);
        } catch (e, st) {
          AppLogger.warn('Writing export file failed', error: e, st: st);
          return Result.failure(AppError.unknown(e.toString()));
        }
      case Failure(error: final e):
        return Result.failure(e);
    }
  }
}

/// Local daily-reminder settings (persisted by [NotificationService]).
typedef ReminderSettings = ({bool enabled, TimeOfDay time});

@riverpod
Future<ReminderSettings> reminderSettings(Ref ref) async {
  return (
    enabled: await NotificationService.isEnabled(),
    time: await NotificationService.reminderTime(),
  );
}
