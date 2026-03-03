import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
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

@riverpod
class ProfileNotifier extends _$ProfileNotifier {
  @override
  AsyncValue<UserProfile?> build() {
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
    state = switch (result) {
      Success(data: final profile) => AsyncValue.data(profile),
      Failure() => const AsyncValue.data(null),
    };
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

  Future<Result<UserProfile, AppError>> updateNotification(
    bool enabled,
  ) async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

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
    return result;
  }

  Future<Result<void, AppError>> deleteAccount() async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) {
      return const Result.failure(AppError.auth('Not authenticated'));
    }

    final repo = ref.read(profileRepositoryProvider);
    return repo.deleteAccount(user.id);
  }
}
