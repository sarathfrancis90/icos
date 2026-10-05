import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/features/auth/domain/auth_outcome.dart';
import 'package:icos/features/auth/providers/auth_provider.dart'
    show authStateChangesProvider;
import 'package:icos/features/auth/providers/session_keeper.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

class _FakeGateway implements SessionGateway {
  _FakeGateway({this.hasSession = false});

  @override
  bool hasSession;

  int signInCalls = 0;

  /// When set, the next sign-in fails with this error.
  Object? failWith;

  /// When set, sign-in waits for it before succeeding.
  Completer<void>? gate;

  @override
  Future<void> signInAnonymously() async {
    signInCalls++;
    await gate?.future;
    final error = failWith;
    if (error != null) throw error;
    hasSession = true;
  }
}

class _ControlledConnectivity extends ConnectivityNotifier {
  @override
  bool build() => true;

  void set(bool online) => state = online;
}

void main() {
  group('SessionEnsurer', () {
    test('signs in anonymously when there is no session', () async {
      final gateway = _FakeGateway();
      final ensurer = SessionEnsurer(gateway: gateway);

      expect(await ensurer.ensureSession(), isTrue);
      expect(gateway.signInCalls, 1);
    });

    test('does nothing when a session exists', () async {
      final gateway = _FakeGateway(hasSession: true);
      expect(await SessionEnsurer(gateway: gateway).ensureSession(), isTrue);
      expect(gateway.signInCalls, 0);
    });

    test('concurrent calls make exactly one sign-in request', () async {
      final gateway = _FakeGateway()..gate = Completer<void>();
      final ensurer = SessionEnsurer(gateway: gateway);

      final results = [
        ensurer.ensureSession(),
        ensurer.ensureSession(),
        ensurer.ensureSession(),
      ];
      gateway.gate!.complete();

      expect(await Future.wait(results), [true, true, true]);
      expect(gateway.signInCalls, 1);
    });

    test('never throws and reports false when sign-in fails', () async {
      final gateway = _FakeGateway()..failWith = StateError('offline');
      final ensurer = SessionEnsurer(gateway: gateway);

      expect(await ensurer.ensureSession(), isFalse);

      // A failed attempt does not wedge later ones.
      gateway.failWith = null;
      expect(await ensurer.ensureSession(), isTrue);
      expect(gateway.signInCalls, 2);
    });

    test('gives up on a hung request after the timeout', () async {
      final gateway = _FakeGateway()..gate = Completer<void>();
      final ensurer = SessionEnsurer(
        gateway: gateway,
        signInTimeout: const Duration(milliseconds: 20),
      );

      expect(await ensurer.ensureSession(), isFalse);
    });
  });

  group('SessionKeeper', () {
    late _FakeGateway gateway;
    late ProviderContainer container;
    late StreamController<AuthState> authEvents;

    setUp(() {
      gateway = _FakeGateway()..failWith = StateError('offline');
      authEvents = StreamController<AuthState>.broadcast();
      container = ProviderContainer(
        overrides: [
          sessionEnsurerProvider.overrideWithValue(
            SessionEnsurer(gateway: gateway),
          ),
          connectivityNotifierProvider.overrideWith(
            _ControlledConnectivity.new,
          ),
          authStateChangesProvider.overrideWith((ref) => authEvents.stream),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await authEvents.close();
    });

    test(
      'failed startup sign-in, then connectivity returns: session exists',
      () async {
        // Startup attempt (what main() does) fails: no network.
        expect(
          await container.read(sessionEnsurerProvider).ensureSession(),
          isFalse,
        );
        expect(gateway.hasSession, isFalse);

        container.read(sessionKeeperProvider);
        final connectivity =
            container.read(connectivityNotifierProvider.notifier)
                as _ControlledConnectivity;
        connectivity.set(false);
        await Future<void>.delayed(Duration.zero);
        expect(gateway.hasSession, isFalse);

        gateway.failWith = null;
        connectivity.set(true);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(gateway.hasSession, isTrue);
        expect(gateway.signInCalls, 2);
      },
    );

    test('a session lost while running is recreated', () async {
      gateway
        ..failWith = null
        ..hasSession = true;
      container.read(sessionKeeperProvider);

      gateway.hasSession = false; // refresh token revoked, SDK signs out
      authEvents.add(const AuthState(AuthChangeEvent.signedOut, null));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(gateway.hasSession, isTrue);
    });
  });

  group('switchToExistingAccount', () {
    test('a cancelled provider flow leaves the guest session usable', () async {
      final gateway = _FakeGateway(hasSession: true);
      final ensurer = SessionEnsurer(gateway: gateway);

      final outcome = await switchToExistingAccount(
        ensurer: ensurer,
        providerFlow: () async => const AuthCancelled(),
      );

      expect(outcome, isA<AuthCancelled>());
      expect(gateway.hasSession, isTrue);
      expect(gateway.signInCalls, 0, reason: 'the guest was never replaced');
    });

    test('a failed flow that lost the session recreates a guest', () async {
      final gateway = _FakeGateway(hasSession: true);
      final ensurer = SessionEnsurer(gateway: gateway);

      final outcome = await switchToExistingAccount(
        ensurer: ensurer,
        providerFlow: () async {
          gateway.hasSession = false;
          return const AuthFailure('boom');
        },
      );

      expect(outcome, isA<AuthFailure>());
      expect(gateway.hasSession, isTrue);
    });

    test('a flow that throws is reported as a failure, session kept', () async {
      final gateway = _FakeGateway(hasSession: true);
      final outcome = await switchToExistingAccount(
        ensurer: SessionEnsurer(gateway: gateway),
        providerFlow: () async => throw StateError('sheet crashed'),
      );

      expect(outcome, isA<AuthFailure>());
      expect(gateway.hasSession, isTrue);
    });
  });
}
