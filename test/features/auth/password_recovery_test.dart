import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/router/deep_link.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/email_auth_screen.dart';
import 'package:icos/features/auth/presentation/new_password_screen.dart';
import 'package:icos/features/auth/presentation/widgets/forgot_password_dialog.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session, User;

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  static Result<void, AppError> resetResult = const Result.success(null);
  static Result<void, AppError> updateResult = const Result.success(null);
  static final resetCalls = <String>[];
  static final updateCalls = <String>[];

  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);

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
}

void main() {
  setUpTestEnvironment();
  _recoveryTests();

  setUp(() {
    _FakeAuth.resetResult = const Result.success(null);
    _FakeAuth.updateResult = const Result.success(null);
    _FakeAuth.resetCalls.clear();
    _FakeAuth.updateCalls.clear();
  });

  final overrides = [
    authNotifierProvider.overrideWith(_FakeAuth.new),
    isGuestProvider.overrideWithValue(true),
  ];

  group('classifyPasswordReset', () {
    test('unknown email is neutral; rate limit and network are reported', () {
      expect(
        AuthStrategy.classifyPasswordReset(code: 'user_not_found'),
        PasswordResetFailure.unknownEmail,
      );
      expect(
        AuthStrategy.classifyPasswordReset(message: 'User not found'),
        PasswordResetFailure.unknownEmail,
      );
      // Per-email limit: neutral, or asking twice reveals the account.
      expect(
        AuthStrategy.classifyPasswordReset(code: 'over_email_send_rate_limit'),
        PasswordResetFailure.unknownEmail,
      );
      expect(
        AuthStrategy.classifyPasswordReset(
          statusCode: '429',
          message:
              'For security purposes, you can only request this after 43 seconds.',
        ),
        PasswordResetFailure.unknownEmail,
      );
      // Request / IP-wide limit: genuinely retry later.
      expect(
        AuthStrategy.classifyPasswordReset(code: 'over_request_rate_limit'),
        PasswordResetFailure.rateLimited,
      );
      expect(
        AuthStrategy.classifyPasswordReset(
          message: 'Request rate limit reached',
        ),
        PasswordResetFailure.rateLimited,
      );
      expect(
        AuthStrategy.classifyPasswordReset(statusCode: '429'),
        PasswordResetFailure.rateLimited,
      );
      expect(
        AuthStrategy.classifyPasswordReset(message: 'Failed host lookup'),
        PasswordResetFailure.network,
      );
      expect(
        AuthStrategy.classifyPasswordReset(message: 'boom'),
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
      final events = StreamController<AuthState>.broadcast();
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

      events.add(const AuthState(AuthChangeEvent.passwordRecovery, null));
      await tester.pumpAndSettle();
      expect(find.text('Set a new password'), findsWidgets);
      expect(container.read(passwordRecoveryPendingProvider), isTrue);

      await tester.enterText(find.byType(TextFormField).at(0), 'hunter22');
      await tester.enterText(find.byType(TextFormField).at(1), 'hunter22');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();
      expect(_FakeAuth.updateCalls, ['hunter22']);
      expect(container.read(passwordRecoveryPendingProvider), isFalse);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Password updated.'), findsOneWidget);
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
  Stream<AuthState>? events,
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
      Stream<AuthState>? events,
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
      final events = StreamController<AuthState>.broadcast();
      addTearDown(events.close);
      final h = await pump(tester, events: events.stream);
      events.add(const AuthState(AuthChangeEvent.passwordRecovery, null));
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
      final events = StreamController<AuthState>.broadcast();
      addTearDown(events.close);
      final h = await pump(tester, events: events.stream);
      User user(String id, {bool anon = false}) => User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
        isAnonymous: anon,
      );
      events.add(
        AuthState(
          AuthChangeEvent.signedIn,
          Session(
            accessToken: 'a',
            tokenType: 'bearer',
            user: user('g1', anon: true),
          ),
        ),
      );
      await tester.pump();
      events.add(
        AuthState(
          AuthChangeEvent.passwordRecovery,
          Session(accessToken: 'b', tokenType: 'bearer', user: user('u1')),
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
        AuthStrategy.isRecoverySessionExpired(code: 'session_not_found'),
        isTrue,
      );
      expect(AuthStrategy.isRecoverySessionExpired(statusCode: '401'), isTrue);
      expect(
        AuthStrategy.isRecoverySessionExpired(message: 'Auth session missing!'),
        isTrue,
      );
      expect(
        AuthStrategy.isRecoverySessionExpired(message: 'weak password'),
        isFalse,
      );
    });
  });
}
