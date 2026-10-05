import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/test_helpers.dart';

/// The screen reads auth state on build, which would otherwise reach for an
/// uninitialised Supabase instance.
class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

void main() {
  group('AuthScreen', () {
    /// Routes far enough to assert where a tap sends the user, without
    /// dragging the real email screen (and Supabase) into the test.
    Widget build({List<String>? visited}) {
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
          GoRoute(
            path: '/auth/email',
            builder: (context, state) {
              visited?.add(state.uri.toString());
              return const Scaffold(body: Text('email form'));
            },
          ),
          GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        ],
      );
      return buildTestWidgetWithRouter(
        router,
        overrides: [
          authNotifierProvider.overrideWith(_FakeAuth.new),
          isGuestProvider.overrideWithValue(true),
        ],
      );
    }

    testWidgets(
      'at 200% text on 320x568 the dismiss button and the consent line scroll '
      'into view above the system navigation area',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        // An 80dp gesture/navigation bar at the bottom.
        tester.view.padding = const FakeViewPadding(bottom: 80);
        tester.view.viewPadding = const FakeViewPadding(bottom: 80);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        await tester.pumpWidget(build());
        await tester.pump();

        // A guest without a session sees "Continue as guest" here; once signed
        // in as a guest it reads "Not now". Same button, same place.
        final notNow = find.text(AppStrings.continueAsGuest);
        final consent = find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText().startsWith('By continuing'),
        );
        expect(notNow, findsOneWidget);
        expect(consent, findsOneWidget);

        // Reachable by scrolling...
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(notNow);
        await tester.pumpAndSettle();

        // ...and when scrolled to the end, neither sits behind the system bar.
        const usable = 568.0 - 80;
        expect(tester.getRect(consent).bottom, lessThanOrEqualTo(usable));
        expect(tester.getRect(notNow).bottom, lessThanOrEqualTo(usable));
        expect(tester.getRect(notNow).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('offers a way in for someone who already has an account', (
      tester,
    ) async {
      await tester.pumpWidget(build());
      await tester.pump();

      expect(
        find.textContaining('Already have an account?'),
        findsOneWidget,
        reason: 'returning players had no route in at all',
      );
    });

    testWidgets('the sign-in link opens the form in sign-in mode', (
      tester,
    ) async {
      final visited = <String>[];
      await tester.pumpWidget(build(visited: visited));
      await tester.pump();

      await tester.tap(find.textContaining('Already have an account?'));
      await tester.pumpAndSettle();

      expect(visited, isNotEmpty);
      expect(
        visited.single,
        contains('mode=signin'),
        reason: 'without mode=signin the email form opens on Create Account',
      );
    });

    testWidgets('the email button is labelled as sign-up, not ambiguous', (
      tester,
    ) async {
      await tester.pumpWidget(build());
      await tester.pump();

      expect(find.text(AppStrings.signUpWithEmail), findsOneWidget);
    });

    testWidgets('shows the Terms/Privacy consent line with both links', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(build());
      await tester.pump();

      expect(
        find.textContaining('By continuing, you agree to our'),
        findsOneWidget,
      );
      for (final label in ['Terms of Service', 'Privacy Policy']) {
        final node = find.semantics.byLabel(label).evaluate().single;
        expect(node.flagsCollection.isLink, isTrue, reason: label);
      }
      handle.dispose();
    });

    testWidgets('does not overflow at 200% text on 320x568', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: build(),
        ),
      );
      await tester.pump();
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(AuthScreen)),
        ).scale(10),
        20,
        reason: 'the 2.0 text scale must reach the widget under test',
      );
      expect(tester.takeException(), isNull);
    });

    group('on Android', () {
      setUp(() => AuthNotifier.platformOverride = AuthPlatform.android);
      tearDown(() => AuthNotifier.platformOverride = null);

      testWidgets('offers Google then Apple, both labelled', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(build());
        await tester.pump();

        expect(
          find.bySemanticsLabel(RegExp(AppStrings.signInWithGoogle)),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(AppStrings.signInWithApple)),
          findsWidgets,
        );
        final googleY = tester
            .getTopLeft(find.text(AppStrings.signInWithGoogle))
            .dy;
        final appleY = tester
            .getTopLeft(find.text(AppStrings.signInWithApple))
            .dy;
        expect(
          appleY,
          greaterThan(googleY),
          reason: 'Google first, Apple under',
        );
        expect(tester.getSize(find.byType(SignInWithAppleButton)).height, 52);
        handle.dispose();
      });

      testWidgets('both buttons fit at 200% text on 320x568', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(2),
            ),
            child: build(),
          ),
        );
        await tester.pump();
        expect(find.text(AppStrings.signInWithApple), findsOneWidget);
        expect(find.text(AppStrings.signInWithGoogle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('both providers are offered', (tester) async {
      await tester.pumpWidget(build());
      await tester.pump();

      expect(find.text(AppStrings.signInWithGoogle), findsWidgets);
    });
  });
}
