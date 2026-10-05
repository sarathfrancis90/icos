import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/router/deep_link.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/features/profile/domain/account_deletion_copy.dart';
import 'package:icos/shared/widgets/blocking_screens.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  test('deletionRedirect blocks every route while pending', () {
    expect(deletionRedirect(path: '/', pending: true), kDeletionPendingPath);
    expect(
      deletionRedirect(path: '/puzzle/2026-10-05', pending: true),
      kDeletionPendingPath,
    );
    expect(deletionRedirect(path: kDeletionPendingPath, pending: true), isNull);
    expect(deletionRedirect(path: kDeletionPendingPath, pending: false), '/');
    expect(deletionRedirect(path: '/stats', pending: false), isNull);
  });

  Widget screen({
    Future<String?> Function()? cancel,
    Future<void> Function()? signOut,
  }) => buildTestWidget(
    AccountDeletionPendingScreen(
      deletionDate: DateTime.utc(2026, 10, 31, 12),
      onCancelDeletion: cancel ?? () async => null,
      onSignOut: signOut ?? () async {},
    ),
  );

  testWidgets('states the date and offers both actions', (tester) async {
    await tester.pumpWidget(screen());
    expect(find.textContaining('Oct 31, 2026'), findsOneWidget);
    expect(find.text('Cancel deletion'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('Cancel deletion calls the handler; failure is shown', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      screen(
        cancel: () async {
          calls++;
          return 'Could not cancel the deletion. Please try again.';
        },
      ),
    );
    await tester.tap(find.text('Cancel deletion'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Could not cancel'), findsOneWidget);
  });

  testWidgets('Sign out calls the handler', (tester) async {
    var out = 0;
    await tester.pumpWidget(screen(signOut: () async => out++));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(out, 1);
  });

  testWidgets('a failing sign-out leaves the screen usable', (tester) async {
    await tester.pumpWidget(
      screen(signOut: () async => throw Exception('network down')),
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Sign out'),
    );
    expect(button.onPressed, isNotNull);
  });

  test('offline cancel failure shows the offline message', () {
    expect(
      AccountDeletionCopy.cancelFailureMessage(const AppError.network('x')),
      "You're offline. Try again when you're connected.",
    );
    expect(
      AccountDeletionCopy.cancelFailureMessage(const AppError.database('x')),
      isNot(contains('offline')),
    );
  });

  testWidgets('offline Cancel failure is shown inline', (tester) async {
    await tester.pumpWidget(
      screen(
        cancel: () async => AccountDeletionCopy.cancelFailureMessage(
          const AppError.network('x'),
        ),
      ),
    );
    await tester.tap(find.text('Cancel deletion'));
    await tester.pumpAndSettle();
    expect(find.text("You're offline. Try again when you're connected."),
        findsOneWidget);
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
        child: screen(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
