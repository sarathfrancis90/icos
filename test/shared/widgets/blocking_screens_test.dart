import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/theme/app_theme.dart';
import 'package:icos/shared/widgets/blocking_screens.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  group('Blocking screens', () {
    testWidgets('ForceUpdateScreen shows update copy and button',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ForceUpdateScreen(
            storeUrl: 'https://example.com',
            latestVersion: '2.0.0',
          ),
        ),
      );
      expect(find.text('Update required'), findsOneWidget);
      expect(find.textContaining('2.0.0'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('MaintenanceScreen shows custom message and retry',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(
        buildTestWidget(
          MaintenanceScreen(
            message: 'Back at noon',
            onRetry: () => retried = true,
          ),
        ),
      );
      expect(find.text('Back soon'), findsOneWidget);
      expect(find.text('Back at noon'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('BannedScreen shows support contact and sign out',
        (tester) async {
      var signedOut = false;
      await tester.pumpWidget(
        buildTestWidget(BannedScreen(onSignOut: () => signedOut = true)),
      );
      expect(find.text('Account suspended'), findsOneWidget);
      expect(find.textContaining(BannedScreen.supportEmail), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      expect(signedOut, isTrue);
    });

    testWidgets('renders in light theme', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const MaintenanceScreen(),
          theme: AppTheme.lightTheme,
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Back soon'), findsOneWidget);
    });
  });
}
