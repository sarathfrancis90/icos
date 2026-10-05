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
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, User;

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
      expect(
        AuthStrategy.classifyPasswordReset(code: 'over_email_send_rate_limit'),
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
        "If an account exists for that email, we've sent a link to reset your "
        'password.';

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
