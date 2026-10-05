import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';
import 'package:icos/features/auth/presentation/auth_screen.dart';
import 'package:icos/features/auth/presentation/email_auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:icos/features/groups/presentation/widgets/account_required_card.dart';
import 'package:icos/features/puzzle/presentation/widgets/game_controls.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

/// Labels (in the whole semantics tree) in which a line is read twice, e.g.
/// "Continue with Google\nContinue with Google": a Semantics wrapper that
/// repeats its child's own text.
List<String> _duplicatedLabels(WidgetTester tester) {
  final duplicated = <String>[];
  void visit(SemanticsNode node) {
    final lines = node.label.split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.length != lines.toSet().length) duplicated.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return duplicated;
}

void main() {
  setUpTestEnvironment();

  Widget authApp(Widget screen) {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    );
    addTearDown(router.dispose);
    return buildTestWidgetWithRouter(
      router,
      overrides: [
        authNotifierProvider.overrideWith(_FakeAuth.new),
        isGuestProvider.overrideWithValue(true),
      ],
    );
  }

  testWidgets('auth screen reads each button once', (tester) async {
    final handle = tester.ensureSemantics();
    AuthNotifier.platformOverride = AuthPlatform.ios;
    addTearDown(() => AuthNotifier.platformOverride = null);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(authApp(const AuthScreen()));
    await tester.pump();

    expect(_duplicatedLabels(tester), isEmpty);
    expect(find.bySemanticsLabel(AppStrings.signInWithGoogle), findsOneWidget);
    expect(find.bySemanticsLabel(AppStrings.signInWithApple), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Already have an account')),
      findsOneWidget,
    );
    // The label replaces the child's text, so the action must live on it.
    expect(
      tester.getSemantics(find.bySemanticsLabel(AppStrings.signInWithGoogle)),
      matchesSemantics(
        label: AppStrings.signInWithGoogle,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: false,
        isFocusable: false,
      ),
    );
    handle.dispose();
  });

  for (final signUp in [true, false]) {
    testWidgets('email form (${signUp ? 'sign up' : 'sign in'}) reads its '
        'submit button once', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(authApp(EmailAuthScreen(initialSignUp: signUp)));
      await tester.pump();

      expect(_duplicatedLabels(tester), isEmpty);
      handle.dispose();
    });
  }

  testWidgets('other custom buttons read once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      buildTestWidget(
        Scaffold(
          body: Column(
            children: [
              const AccountRequiredCard(),
              GameControls(
                gameState: createPlayingGameState(),
                onUndo: () {},
                onReset: () {},
                onHint: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(_duplicatedLabels(tester), isEmpty);
    handle.dispose();
  });
}
