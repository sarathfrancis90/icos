import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/auth/providers/auth_provider.dart'
    show authStateChangesProvider;
import 'package:icos/features/auth/providers/user_scope_keeper.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/providers/game_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session, User;

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _SignedIn implements SessionGateway {
  @override
  bool get hasSession => true;

  @override
  Future<void> signInAnonymously() async {}
}

AuthState _event(AuthChangeEvent event, String id) => AuthState(
      event,
      Session(
        accessToken: 't',
        tokenType: 'bearer',
        user: User(
          id: id,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late StreamController<AuthState> events;
  late ProviderContainer container;
  const date = '2026-09-09';
  final source = PuzzleSource.daily(date);
  final puzzle = smallTestPuzzle.copyWith(puzzleDate: date);

  setUp(() async {
    dir = await initTestStorage(userId: 'user-a');
    events = StreamController<AuthState>.broadcast();
    container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => events.stream),
        authSessionProvider.overrideWithValue(
          const FakeAuthSessionInfo(userId: 'user-a'),
        ),
        edgeInvokerProvider.overrideWithValue(
          (fn, body) async => const EdgeResponse(200, {'nonce': 'n'}),
        ),
        connectivityNotifierProvider.overrideWith(_Online.new),
        sessionEnsurerProvider.overrideWithValue(
          SessionEnsurer(gateway: _SignedIn()),
        ),
      ],
    );
    container.read(userScopeKeeperProvider);
  });

  tearDown(() async {
    container.dispose();
    await events.close();
    await dir.delete(recursive: true);
  });

  Future<void> emit(AuthChangeEvent e, String id) async {
    events.add(_event(e, id));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  void playOneMove() {
    final notifier = container.read(gameNotifierProvider(source).notifier);
    notifier.startGame(puzzle);
    notifier.handleCellTap(0, 0);
  }

  test('a different user id starts fresh and nothing of A\'s lands under B',
      () async {
    playOneMove();
    expect(container.read(gameNotifierProvider(source))!.path, isNotEmpty);
    expect(StorageService.getGameState(date), isNotNull);

    await emit(AuthChangeEvent.signedIn, 'user-b');

    expect(StorageService.activeUserId, 'user-b');
    expect(container.read(gameNotifierProvider(source)), isNull);
    container.read(gameNotifierProvider(source).notifier).startGame(puzzle);
    expect(container.read(gameNotifierProvider(source))!.path, isEmpty);
    expect(StorageService.getGameState(date), isNull);

    // A's progress is intact for when A signs back in.
    await StorageService.setActiveUser('user-a');
    expect(StorageService.getGameState(date), isNotNull);
  });

  test('a link that keeps the same user id keeps the game in progress',
      () async {
    playOneMove();
    final before = container.read(gameNotifierProvider(source))!;

    await emit(AuthChangeEvent.userUpdated, 'user-a');

    final after = container.read(gameNotifierProvider(source));
    expect(after, isNotNull);
    expect(after!.path, before.path);
  });
}
