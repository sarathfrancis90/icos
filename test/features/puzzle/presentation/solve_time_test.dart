import 'dart:convert';
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
import 'package:icos/features/puzzle/presentation/widgets/celebration_overlay.dart';
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

const _snake = [
  [0, 0], [0, 1], [0, 2], [1, 2], [1, 1], [1, 0], [2, 0], [2, 1], [2, 2], //
];

void main() {
  setUpTestEnvironment();

  late Directory dir;
  final today = AppDateUtils.todayUtc();

  setUp(() async {
    dir = await initTestStorage();
    await StorageService.setHasSeenNotificationPrompt(true);
  });
  tearDown(() async => dir.delete(recursive: true));

  testWidgets('a restored game shows, stores and submits restored + played '
      'seconds', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const restored = 77;
    const played = 5;
    final source = PuzzleSource.daily(today);
    // The app was killed mid-solve: eight of nine cells drawn, 77 s on the
    // clock.
    await StorageService.saveGameState(source.storageKey, {
      'path': _snake.take(8).toList(),
      'elapsed_seconds': restored,
      'hints_used': 0,
      'undos_used': 0,
      'status': 'playing',
    });

    final puzzle = smallTestPuzzle.copyWith(puzzleDate: today);
    final submitted = <Map<String, dynamic>>[];
    final container = ProviderContainer(
      overrides: [
        puzzleForDateProvider(today).overrideWith((ref) async => puzzle),
        puzzleRepositoryProvider.overrideWithValue(_NoAttempts()),
        authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
        connectivityNotifierProvider.overrideWith(_Online.new),
        edgeInvokerProvider.overrideWithValue((fn, body) async {
          if (fn == 'submit-score') submitted.add(body);
          return const EdgeResponse(200, {'nonce': 'n', 'completed': true});
        }),
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
    expect(
      container.read(gameNotifierProvider(source))!.elapsedSeconds,
      restored,
    );

    for (var i = 0; i < played; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final notifier = container.read(gameNotifierProvider(source).notifier);
    expect(
      container.read(gameNotifierProvider(source))!.elapsedSeconds,
      restored + played,
    );
    notifier.handleCellTap(2, 2);

    // The card is read while it is still animating in: it must already show
    // the final time, not a count-up frame.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final expected = AppDateUtils.formatTime(restored + played);
    expect(
      find.text('Puzzle Complete!').evaluate().isNotEmpty ||
          find.text('Crushed It!').evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byType(CelebrationOverlay),
        matching: find.text(expected),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(CelebrationOverlay),
        matching: find.text('00:00'),
      ),
      findsNothing,
      reason:
          'the result card must show the submitted time from the first '
          'frame, not a count-up frame',
    );

    await tester.pump(const Duration(seconds: 3));
    final stored = SubmissionResult.fromJson(
      StorageService.getSubmissionResult(source.storageKey)!,
    );
    expect(stored.timeSeconds, restored + played);
    final queued = StorageService.getSyncQueueItems();
    final times = [
      for (final item in queued) item.value['time_seconds'],
      for (final body in submitted) body['time_seconds'],
    ];
    expect(times, isNotEmpty);
    expect(times.every((t) => t == restored + played), isTrue);
    expect(jsonEncode(times), isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
