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

  test('A to B resets before the switch I/O: a timer tick cannot save A\'s '
      'game under B', () async {
    playOneMove();
    final before = container.read(gameNotifierProvider(source))!;
    expect(before.path, isNotEmpty);

    // main()'s listener switches the scope first; the keeper then runs.
    await StorageService.setActiveUser('user-b');
    events.add(_event(AuthChangeEvent.signedIn, 'user-b'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(StorageService.getGameState(date), isNull);
  });

  group('with no session at first', () {
    setUp(() async {
      // Replace the signed-in setup: the device has no session yet.
      container.dispose();
      await StorageService.setActiveUser(null);
      container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => events.stream),
          authSessionProvider.overrideWithValue(
            const FakeAuthSessionInfo(userId: null, hasSession: false),
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

    test('the first user is not an account switch: the open game keeps '
        'going and auto-saves under that user', () async {
      playOneMove();
      expect(StorageService.getGameState(date), isNotNull); // under u.none.
      final before = container.read(gameNotifierProvider(source))!;

      await StorageService.setActiveUser('user-a'); // main()'s listener
      events.add(_event(AuthChangeEvent.signedIn, 'user-a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final after = container.read(gameNotifierProvider(source));
      expect(after, isNotNull);
      expect(after!.path, before.path);
      // The no-session record was carried over to A...
      expect(StorageService.getGameState(date), isNotNull);
      expect(
        StorageService.prefs.getKeys().where((k) => k.startsWith('u.none.')),
        isEmpty,
      );
      // ...and the next move saves under A.
      container.read(gameNotifierProvider(source).notifier).handleCellTap(0, 1);
      expect(StorageService.getGameState(date)!['path'], hasLength(2));
    });
  });
}
