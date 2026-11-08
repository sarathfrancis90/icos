import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/router/deep_link.dart';
import 'package:icos/core/services/app_config_provider.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/email_auth_screen.dart';
import 'package:icos/features/auth/presentation/new_password_screen.dart';
import 'package:icos/features/auth/presentation/widgets/forgot_password_dialog.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/core/services/storage_service.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  static Result<void, AppError> resetResult = const Result.success(null);
  static Result<void, AppError> updateResult = const Result.success(null);
  static final resetCalls = <String>[];
  static final updateCalls = <String>[];
  static final completeCalls = <(String, String)>[];

  @override
  AsyncValue<AppUser?> build() => const AsyncValue.data(null);

  @override
  Future<Result<void, AppError>> sendPasswordReset(String email) async {
    resetCalls.add(email);
    return resetResult;
  }

  @override
  Future<Result<void, AppError>> updatePassword(String newPassword) async {
    updateCalls.add(newPassword);
    return updateResult;
  }

  @override
  Future<Result<void, AppError>> completePasswordReset(
    String token,
    String newPassword,
  ) async {
    completeCalls.add((token, newPassword));
    return updateResult;
  }
}

void main() {
  setUpTestEnvironment();
  _recoveryTests();

  setUp(() {
    _FakeAuth.resetResult = const Result.success(null);
    _FakeAuth.updateResult = const Result.success(null);
    _FakeAuth.resetCalls.clear();
    _FakeAuth.updateCalls.clear();
    _FakeAuth.completeCalls.clear();
  });

  final overrides = [
    authNotifierProvider.overrideWith(_FakeAuth.new),
    isGuestProvider.overrideWithValue(true),
  ];

  group('classifyPasswordReset', () {
    test('a server-side "email invalid" answer is neutral, not an error', () {
      // Format validation already passed on the client, so surfacing it
      // would both scare the user and reveal whether the account exists.
      expect(
        AuthStrategy.classifyPasswordReset(
          const AppError.validation(
            'Email address "qa@example.com" is invalid',
          ),
        ),
        PasswordResetFailure.unknownEmail,
      );
      expect(
        AuthStrategy.classifyPasswordReset(
          const AppError.validation('Invalid email'),
        ),
        PasswordResetFailure.unknownEmail,
      );
    });

    test('unknown email is neutral; rate limit and network are reported', () {
      expect(
        AuthStrategy.classifyPasswordReset(
          const AppError.notFound('User not found'),
        ),
        PasswordResetFailure.unknownEmail,
      );
      expect(
        AuthStrategy.classifyPasswordReset(
          const AppError.validation('User not found'),
        ),
        PasswordResetFailure.unknownEmail,
      );
      expect(
        AuthStrategy.classifyPasswordReset(
          const AppError.rateLimit('Too many requests'),
        ),
        PasswordResetFailure.rateLimited,
      );
      expect(
        AuthStrategy.classifyPasswordReset(
          const AppError.network('Failed host lookup'),
        ),
        PasswordResetFailure.network,
      );
      expect(
        AuthStrategy.classifyPasswordReset(const AppError.unknown('boom')),
        PasswordResetFailure.other,
      );
      expect(
        AuthStrategy.classifyPasswordReset(const AppError.auth('boom')),
        PasswordResetFailure.other,
      );
    });
  });

  group('Forgot password entry point', () {
    testWidgets('visible in sign-in mode', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const EmailAuthScreen(initialSignUp: false),
          overrides: overrides,
        ),
      );
      await tester.pump();
      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('hidden in sign-up mode', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const EmailAuthScreen(initialSignUp: true),
          overrides: overrides,
        ),
      );
      await tester.pump();
      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('opens the dialog prefilled with the typed email', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          const EmailAuthScreen(initialSignUp: false),
          overrides: overrides,
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, 'me@x.com');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
      expect(find.text('me@x.com'), findsWidgets);
    });
  });

  group('ForgotPasswordDialog', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showForgotPasswordDialog(context, initialEmail: 'a@b.co'),
              child: const Text('open'),
            ),
          ),
          overrides: overrides,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    const neutral =
        'If an account exists for that email, a reset link is on its way. '
        'It can take a few minutes — check your spam folder too.';

    testWidgets('shows the neutral confirmation on success', (tester) async {
      await open(tester);
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.resetCalls, ['a@b.co']);
      expect(find.text(neutral), findsOneWidget);
    });

    testWidgets('an unknown email gets the very same confirmation', (
      tester,
    ) async {
      // The notifier maps "user not found" to success (see classify test).
      _FakeAuth.resetResult = const Result.success(null);
      await open(tester);
      await tester.enterText(find.byType(TextFormField), 'nobody@x.com');
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(find.text(neutral), findsOneWidget);
    });

    testWidgets('rate limit shows a retry-later message, no confirmation', (
      tester,
    ) async {
      _FakeAuth.resetResult = const Result.failure(AppError.rateLimit('x'));
      await open(tester);
      await tester.tap(find.text('Send link'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('try again in a little while'),
        findsOneWidget,
      );
      expect(find.text(neutral), findsNothing);
    });
  });

  group('password recovery routing', () {
    testWidgets('passwordRecovery event routes to the new-password screen', (
      tester,
    ) async {
      final events = StreamController<AuthStateChange>.broadcast();
      addTearDown(events.close);
      final container = ProviderContainer(
        overrides: [
          ...overrides,
          authStateChangesProvider.overrideWith((ref) => events.stream),
        ],
      );
      addTearDown(container.dispose);

      final refresh = ValueNotifier(0);
      container.listen<bool>(
        passwordRecoveryPendingProvider,
        (_, _) => refresh.value++,
      );
      final router = GoRouter(
        refreshListenable: refresh,
        redirect: (context, state) => recoveryRedirect(
          path: state.uri.path,
          pending: container.read(passwordRecoveryPendingProvider),
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: kNewPasswordPath,
            builder: (_, _) => const NewPasswordScreen(),
          ),
          GoRoute(
            path: '/auth',
            builder: (_, state) =>
                Scaffold(body: Text('AUTH ${state.uri.query}')),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);

      events.add(const AuthStateChange(AuthEvent.passwordRecovery));
      await tester.pumpAndSettle();
      expect(find.text('Set a new password'), findsWidgets);
      expect(container.read(passwordRecoveryPendingProvider), isTrue);

      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.enterText(find.byType(TextFormField).at(1), 'hunter22');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.updateCalls, ['hunter22']);
      expect(container.read(passwordRecoveryPendingProvider), isFalse);
      // A reset does not sign the player in: they sign in with it next.
      expect(find.text('AUTH mode=signin'), findsOneWidget);
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
    });

    testWidgets('/reset?token=abc opens the screen with the token, and a '
        'successful reset goes to sign-in', (tester) async {
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      final refresh = ValueNotifier(0);
      container.listen<bool>(
        passwordRecoveryPendingProvider,
        (_, _) => refresh.value++,
      );
      final router = GoRouter(
        initialLocation: '/reset?token=abc',
        refreshListenable: refresh,
        redirect: (context, state) => appRedirect(
          uri: state.uri,
          gate: AppGate.ok,
          banned: false,
          pendingDeletion: false,
          recoveryPending: container.read(passwordRecoveryPendingProvider),
          hasSeenOnboarding: true,
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: kNewPasswordPath,
            builder: (_, _) => const NewPasswordScreen(),
          ),
          GoRoute(
            path: kResetLinkPath,
            builder: (_, state) => NewPasswordScreen(
              resetToken: state.uri.queryParameters['token'],
            ),
          ),
          GoRoute(
            path: '/auth',
            builder: (_, state) =>
                Scaffold(body: Text('AUTH ${state.uri.query}')),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set a new password'), findsWidgets);
      expect(router.routeInformationProvider.value.uri.path, kResetLinkPath);
      expect(container.read(passwordRecoveryPendingProvider), isTrue);
      expect(
        container.read(passwordRecoveryPendingProvider.notifier).token,
        'abc',
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.enterText(find.byType(TextFormField).at(1), 'hunter22');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.completeCalls, [('abc', 'hunter22')]);
      expect(_FakeAuth.updateCalls, isEmpty);
      expect(container.read(passwordRecoveryPendingProvider), isFalse);
      expect(find.text('AUTH mode=signin'), findsOneWidget);
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
    });
  });

  group('NewPasswordScreen', () {
    Widget screen() =>
        buildTestWidget(const NewPasswordScreen(), overrides: overrides);

    testWidgets('mismatched passwords are rejected', (tester) async {
      await tester.pumpWidget(screen());
      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.enterText(find.byType(TextFormField).at(1), 'hunter23');
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(_FakeAuth.updateCalls, isEmpty);
    });

    testWidgets('a too-short password is rejected', (tester) async {
      await tester.pumpWidget(screen());
      await tester.enterText(find.byType(TextFormField).at(0), 'abc');
      await tester.enterText(find.byType(TextFormField).at(1), 'abc');
      await tester.tap(find.text('Save password'));
      await tester.pump();
      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
      expect(_FakeAuth.updateCalls, isEmpty);
    });

    testWidgets('a server error is shown inline', (tester) async {
      _FakeAuth.updateResult = const Result.failure(
        AppError.auth('Choose a password you have not used before.'),
      );
      await tester.pumpWidget(screen());
      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.enterText(find.byType(TextFormField).at(1), 'hunter22');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a password you have not used before.'),
        findsOneWidget,
      );
    });
  });
}

class _Harness {
  _Harness(this.container, this.router);
  final ProviderContainer container;
  final GoRouter router;
}

_Harness _recoveryHarness(
  List<Override> overrides, {
  Stream<AuthStateChange>? events,
}) {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      if (events != null)
        authStateChangesProvider.overrideWith((ref) => events),
    ],
  );
  addTearDown(container.dispose);
  final refresh = ValueNotifier(0);
  container.listen<bool>(
    passwordRecoveryPendingProvider,
    (_, _) => refresh.value++,
  );
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) => recoveryRedirect(
      path: state.uri.path,
      pending: container.read(passwordRecoveryPendingProvider),
    ),
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: kNewPasswordPath,
        builder: (_, _) => const NewPasswordScreen(),
      ),
    ],
  );
  return _Harness(container, router);
}

void _recoveryTests() {
  group('recovery escape hatches', () {
    final overrides = [
      authNotifierProvider.overrideWith(_FakeAuth.new),
      isGuestProvider.overrideWithValue(true),
    ];

    Future<_Harness> pump(
      WidgetTester tester, {
      Stream<AuthStateChange>? events,
    }) async {
      final h = _recoveryHarness(overrides, events: events);
      h.container.read(passwordRecoveryPendingProvider.notifier);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp.router(routerConfig: h.router),
        ),
      );
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('Not now leaves the password unchanged and goes home', (
      tester,
    ) async {
      final events = StreamController<AuthStateChange>.broadcast();
      addTearDown(events.close);
      final h = await pump(tester, events: events.stream);
      events.add(const AuthStateChange(AuthEvent.passwordRecovery));
      await tester.pumpAndSettle();
      expect(find.text('Not now'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Not now')).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(h.container.read(passwordRecoveryPendingProvider), isFalse);
      expect(_FakeAuth.updateCalls, isEmpty);
    });

    testWidgets('expired recovery session offers a new link', (tester) async {
      _FakeAuth.updateResult = const Result.failure(
        AppError.auth(AuthStrategy.recoverySessionExpiredMessage),
      );
      await tester.pumpWidget(
        buildTestWidget(const NewPasswordScreen(), overrides: overrides),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.enterText(find.byType(TextFormField).at(1), 'hunter22');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This reset link has expired. Request a new one to set a new password.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Send a new link'));
      await tester.tap(find.text('Send a new link'));
      await tester.pumpAndSettle();
      expect(find.text('Reset your password'), findsOneWidget);
    });

    testWidgets('warns when the link replaced a guest with progress', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final dir = await initTestStorage(userId: 'g1');
        addTearDown(() => dir.delete(recursive: true));
        await StorageService.saveSubmissionResult('2026-10-01', {
          'x': 1,
        }, userId: 'g1');
      });
      final events = StreamController<AuthStateChange>.broadcast();
      addTearDown(events.close);
      final h = await pump(tester, events: events.stream);
      events.add(
        AuthStateChange(
          AuthEvent.signedIn,
          const AppUser(id: 'g1', isAnonymous: true),
        ),
      );
      await tester.pump();
      // The reset link opens the app while the guest is still signed in;
      // signing in to the account afterwards replaces the guest.
      events.add(
        AuthStateChange(
          AuthEvent.passwordRecovery,
          const AppUser(id: 'g1', isAnonymous: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.container.read(recoveryReplacesGuestProvider), isTrue);
      expect(find.textContaining("won't carry over"), findsOneWidget);
    });

    test('clearing recovery also clears the early-arrival latch', () {
      final h = _recoveryHarness(overrides);
      PasswordRecoveryLatch.arrivedBeforeStart = true;
      h.container.read(passwordRecoveryPendingProvider.notifier).clear();
      expect(PasswordRecoveryLatch.arrivedBeforeStart, isFalse);
    });

    test('recovery-session-expired classification', () {
      expect(
        AuthStrategy.isRecoverySessionExpired(
          const AppError.validation('Invalid token'),
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isRecoverySessionExpired(
          const AppError.auth('Unauthorized'),
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isRecoverySessionExpired(
          const AppError.validation('Token expired'),
        ),
        isTrue,
      );
      expect(
        AuthStrategy.isRecoverySessionExpired(
          const AppError.validation('Password too short'),
        ),
        isFalse,
      );
      expect(
        AuthStrategy.isRecoverySessionExpired(
          const AppError.network('offline'),
        ),
        isFalse,
      );
    });

    test(
      'a reset link token is kept for the new password and cleared after',
      () {
        final h = _recoveryHarness(overrides);
        final pending = h.container.read(
          passwordRecoveryPendingProvider.notifier,
        );
        PasswordRecoveryLatch.arrive('early-token');
        // A link that arrived before the providers existed.
        final late = _recoveryHarness(overrides);
        expect(late.container.read(passwordRecoveryPendingProvider), isTrue);
        expect(
          late.container.read(passwordRecoveryPendingProvider.notifier).token,
          'early-token',
        );
        pending.start('t-1');
        expect(h.container.read(passwordRecoveryPendingProvider), isTrue);
        expect(pending.token, 't-1');
        pending.clear();
        expect(pending.token, isNull);
        expect(PasswordRecoveryLatch.token, isNull);
      },
    );
  });
}
