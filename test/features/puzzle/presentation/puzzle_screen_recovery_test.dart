import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/puzzle/providers/game_provider.dart';

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _NoAttempts extends PuzzleRepository {
  _NoAttempts()
      : super(invoker: (fn, body) async => const EdgeResponse(500, {}));

  @override
  Future<SubmissionResult?> getOwnAttempt(String userId, String date) async =>
      null;
}

class _SignedIn implements SessionGateway {
  @override
  bool get hasSession => true;

  @override
  Future<void> signInAnonymously() async {}
}

void main() {
  setUpTestEnvironment();

  late Directory dir;
  final today = AppDateUtils.todayUtc();

  setUp(() async {
    dir = await initTestStorage();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  testWidgets('the grid comes back when the game is invalidated underneath '
      'the open screen', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = PuzzleSource.daily(today);
    final puzzle = smallTestPuzzle.copyWith(puzzleDate: today);
    final container = ProviderContainer(
      overrides: [
        puzzleForDateProvider(today).overrideWith((ref) async => puzzle),
        puzzleRepositoryProvider.overrideWithValue(_NoAttempts()),
        authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
        connectivityNotifierProvider.overrideWith(_Online.new),
        edgeInvokerProvider.overrideWithValue(
          (fn, body) async => const EdgeResponse(200, {'nonce': 'n'}),
        ),
        sessionEnsurerProvider.overrideWithValue(
          SessionEnsurer(gateway: _SignedIn()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PuzzleScreen(source: source)),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PuzzleGrid), findsOneWidget);

    container.read(gameNotifierProvider(source).notifier).handleCellTap(0, 0);
    await tester.pump();

    // What a user-id change does to the kept-alive game.
    container.invalidate(gameNotifierProvider);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(PuzzleGrid), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Leaving the screen stops the game's timer.
    await tester.pumpWidget(const SizedBox());
  });
}
