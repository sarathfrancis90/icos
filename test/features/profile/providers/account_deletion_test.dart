import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/profile/data/profile_repository.dart';
import 'package:icos/features/profile/domain/models/profile.dart';
import 'package:icos/features/profile/providers/profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class _FakeRepo extends ProfileRepository {
  _FakeRepo({this.pendingDeletion = true});
  bool pendingDeletion;
  int cancelCalls = 0;

  @override
  Future<Result<UserProfile, AppError>> getProfile(String userId) async =>
      Result.success(
        UserProfile(
          id: userId,
          displayName: 'P',
          isAnonymous: false,
          deletedAt: pendingDeletion ? DateTime.utc(2026, 10, 1) : null,
        ),
      );

  @override
  Future<Result<void, AppError>> cancelAccountDeletion() async {
    cancelCalls++;
    pendingDeletion = false;
    return const Result.success(null);
  }
}

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);

  void signInAs(String id) => state = AsyncValue.data(
    User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        authSessionProvider.overrideWithValue(
          const FakeAuthSessionInfo(userId: 'u1'),
        ),
        authNotifierProvider.overrideWith(_FakeAuth.new),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<UserProfile?> load() async {
    final sub = container.listen(profileNotifierProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    return container.read(profileNotifierProvider).valueOrNull;
  }

  test(
    'merely loading the profile does not cancel a pending deletion',
    () async {
      final profile = await load();
      expect(repo.cancelCalls, 0);
      expect(profile?.deletedAt, isNotNull);
    },
  );

  test('refreshing the profile does not cancel a pending deletion', () async {
    await load();
    await container.read(profileNotifierProvider.notifier).refresh();
    expect(repo.cancelCalls, 0);
  });

  test('the explicit Cancel deletion action cancels it', () async {
    await load();
    final result = await container
        .read(profileNotifierProvider.notifier)
        .cancelAccountDeletion();
    expect(result, isA<Success<void, AppError>>());
    expect(repo.cancelCalls, 1);
    await pumpEventQueue();
    expect(
      container.read(profileNotifierProvider).valueOrNull?.deletedAt,
      isNull,
    );
  });

  test(
    'a deliberate sign-in to the account cancels it, as the dialog says',
    () async {
      await load();
      expect(repo.cancelCalls, 0);
      (container.read(authNotifierProvider.notifier) as _FakeAuth).signInAs(
        'u1',
      );
      await pumpEventQueue();
      expect(repo.cancelCalls, 1);
      expect(container.read(deletionCancelledFlagProvider), isTrue);
    },
  );
}
