import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/auth/presentation/email_auth_screen.dart';
import 'package:icos/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/test_helpers.dart';

class _FakeAuth extends AuthNotifier {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);
}

void main() {
  setUpTestEnvironment();

  Widget build() => buildTestWidget(
    const EmailAuthScreen(),
    overrides: [
      authNotifierProvider.overrideWith(_FakeAuth.new),
      isGuestProvider.overrideWithValue(true),
    ],
  );

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
    expect(find.bySemanticsLabel('Terms of Service'), findsOneWidget);
    expect(find.bySemanticsLabel('Privacy Policy'), findsOneWidget);
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
        tester.element(find.byType(EmailAuthScreen)),
      ).scale(10),
      20,
      reason: 'the 2.0 text scale must reach the widget under test',
    );
    expect(tester.takeException(), isNull);
  });
}
