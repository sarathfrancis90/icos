import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/providers/game_provider.dart';
import 'package:icos/features/puzzle/providers/hint_engine.dart';

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

/// Records edge calls; `start-puzzle` returns a nonce.
class _FakeEdge {
  final calls = <(String, Map<String, dynamic>)>[];

  Future<EdgeResponse> call(String fn, Map<String, dynamic> body) async {
    calls.add((fn, body));
    if (fn == 'start-puzzle') {
      return EdgeResponse(200, {
        'puzzle_date': body['puzzle_date'],
        'nonce': 'nonce-${body['puzzle_date']}',
        'started_at': '2026-09-09T00:00:00Z',
        'already_completed': false,
      });
    }
    return const EdgeResponse(200, {});
  }
}

/// Scripted hint engine with a completer so "thinking" can be observed.
class _FakeHintEngine implements HintEngine {
  _FakeHintEngine(this.result);

  HintResult result;
  int solveCalls = 0;
  int hintCalls = 0;
  Future<void> Function()? gate;

  @override
  Future<List<GridPosition>?> solve(Puzzle puzzle) async {
    solveCalls++;
    return const [GridPosition(row: 0, col: 0)];
  }

  @override
  Future<HintResult> hint(
    Puzzle puzzle,
    List<GridPosition> path,
    List<GridPosition>? solution,
  ) async {
    hintCalls++;
    if (gate != null) await gate!();
    return result;
  }
}

void main() {
  late Directory tempDir;
  late _FakeEdge edge;
  late _FakeHintEngine hintEngine;
  const source = PuzzleSource.daily('2026-09-09');

  // Full solution of smallTestPuzzle (3x3, (0,0) -> (2,2), no walls).
  const solution = [
    [0, 0],
    [0, 1],
    [0, 2],
    [1, 2],
    [1, 1],
    [1, 0],
    [2, 0],
    [2, 1],
    [2, 2],
  ];

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await initTestStorage();
    edge = _FakeEdge();
    hintEngine = _FakeHintEngine(
      const HintResult.nextCell(GridPosition(row: 0, col: 1)),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        edgeInvokerProvider.overrideWithValue(edge.call),
        connectivityNotifierProvider.overrideWith(_Online.new),
        hintEngineProvider.overrideWithValue(hintEngine),
        authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('GameNotifier', () {
    testWidgets('timer starts on the first move and ticks once per second',
        (tester) async {
      final container = makeContainer();
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.startGame(smallTestPuzzle);

      expect(container.read(gameNotifierProvider(source))!.status,
          GameStatus.notStarted);

      notifier.handleCellTap(0, 0);
      var state = container.read(gameNotifierProvider(source))!;
      expect(state.status, GameStatus.playing);
      expect(state.elapsedSeconds, 0);

      await tester.pump(const Duration(seconds: 3));
      state = container.read(gameNotifierProvider(source))!;
      expect(state.elapsedSeconds, 3);

      notifier.pauseTimer();
      await tester.pump(const Duration(seconds: 3));
      expect(container.read(gameNotifierProvider(source))!.elapsedSeconds, 3);

      notifier.resumeTimer();
      await tester.pump(const Duration(seconds: 2));
      expect(container.read(gameNotifierProvider(source))!.elapsedSeconds, 5);
      notifier.pauseTimer();
    });

    testWidgets('first move requests a start-puzzle session once',
        (tester) async {
      final container = makeContainer();
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.startGame(smallTestPuzzle);
      notifier.handleCellTap(0, 0);
      notifier.handleCellTap(0, 1);
      await tester.pump();

      final starts = edge.calls.where((c) => c.$1 == 'start-puzzle').toList();
      expect(starts, hasLength(1));
      expect(starts.single.$2['puzzle_date'], '2026-09-09');
      expect(StorageService.getSessionNonce('2026-09-09'), 'nonce-2026-09-09');
      notifier.pauseTimer();
    });

    testWidgets('practice sources never start a server session',
        (tester) async {
      final container = makeContainer();
      const practice =
          PuzzleSource.practice(seed: 1, size: 3, difficulty: 'easy');
      final notifier = container.read(gameNotifierProvider(practice).notifier);
      notifier.startGame(smallTestPuzzle);
      notifier.handleCellTap(0, 0);
      await tester.pump();
      expect(edge.calls, isEmpty);
      notifier.pauseTimer();
    });

    testWidgets('save / restore round trip across containers', (tester) async {
      final first = makeContainer();
      final notifier = first.read(gameNotifierProvider(source).notifier);
      notifier.startGame(smallTestPuzzle);
      notifier.handleCellTap(0, 0);
      notifier.handleCellTap(0, 1);
      notifier.handleCellTap(0, 2);
      notifier.undo();
      await tester.pump(const Duration(seconds: 7));
      notifier.pauseTimer();

      final saved = StorageService.getGameState(source.storageKey)!;
      expect(saved['path'], [
        [0, 0],
        [0, 1],
      ]);
      expect(saved['undos_used'], 1);
      expect(saved['status'], 'playing');

      // Fresh container: state must be rebuilt from storage.
      final second = makeContainer();
      final restoredNotifier =
          second.read(gameNotifierProvider(source).notifier);
      restoredNotifier.startGame(smallTestPuzzle);
      final restored = second.read(gameNotifierProvider(source))!;
      expect(restored.path, const [
        GridPosition(row: 0, col: 0),
        GridPosition(row: 0, col: 1),
      ]);
      expect(restored.elapsedSeconds, 7);
      expect(restored.undosUsed, 1);
      expect(restored.status, GameStatus.playing);
      expect(restored.grid[0][1], CellState.filled);
      restoredNotifier.pauseTimer();
    });

    testWidgets('startGame is idempotent for the same puzzle', (tester) async {
      final container = makeContainer();
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.startGame(smallTestPuzzle);
      notifier.handleCellTap(0, 0);
      notifier.handleCellTap(0, 1);
      notifier.startGame(smallTestPuzzle);
      expect(container.read(gameNotifierProvider(source))!.path, hasLength(2));
      notifier.pauseTimer();
    });

    testWidgets('completing the path stops the timer and marks completed',
        (tester) async {
      final container = makeContainer();
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.startGame(smallTestPuzzle);
      for (final cell in solution) {
        notifier.handleCellTap(cell[0], cell[1]);
      }
      final done = container.read(gameNotifierProvider(source))!;
      expect(done.status, GameStatus.completed);
      expect(done.path, hasLength(9));

      await tester.pump(const Duration(seconds: 5));
      expect(container.read(gameNotifierProvider(source))!.elapsedSeconds, 0);

      // Input is ignored after completion.
      notifier.handleCellTap(0, 0);
      notifier.undo();
      expect(container.read(gameNotifierProvider(source))!.path, hasLength(9));
    });

    testWidgets('loadCompleted replays a stored result read-only',
        (tester) async {
      final container = makeContainer();
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.loadCompleted(
        smallTestPuzzle,
        SubmissionResult(
          date: '2026-09-09',
          status: SubmissionStatus.verified,
          timeSeconds: 77,
          hintsUsed: 1,
          undosUsed: 2,
          path: solution,
          completedAt: DateTime.utc(2026, 9, 9),
        ),
      );
      final state = container.read(gameNotifierProvider(source))!;
      expect(notifier.isReplay, isTrue);
      expect(state.status, GameStatus.completed);
      expect(state.elapsedSeconds, 77);
      expect(state.hintsUsed, 1);
      expect(state.undosUsed, 2);
      expect(state.path, hasLength(9));
      expect(StorageService.getGameState(source.storageKey), isNull);
    });

    group('hints', () {
      testWidgets('nextCell highlights the cell and counts a hint',
          (tester) async {
        final container = makeContainer();
        final notifier = container.read(gameNotifierProvider(source).notifier);
        notifier.startGame(smallTestPuzzle);
        notifier.handleCellTap(0, 0);

        await notifier.useHint();
        final state = container.read(gameNotifierProvider(source))!;
        expect(state.hintCell, const GridPosition(row: 0, col: 1));
        expect(state.hintsUsed, 1);
        expect(container.read(hintUiProvider(source)).isIdle, isTrue);
        expect(hintEngine.solveCalls, 1);

        // Moving clears the highlight.
        notifier.handleCellTap(0, 1);
        expect(container.read(gameNotifierProvider(source))!.hintCell, isNull);
        notifier.pauseTimer();
      });

      testWidgets('wrongCell surfaces the divergent cell without a hintCell',
          (tester) async {
        hintEngine.result =
            const HintResult.wrongCell(GridPosition(row: 1, col: 0));
        final container = makeContainer();
        final notifier = container.read(gameNotifierProvider(source).notifier);
        notifier.startGame(smallTestPuzzle);
        notifier.handleCellTap(0, 0);
        notifier.handleCellTap(1, 0);

        await notifier.useHint();
        final state = container.read(gameNotifierProvider(source))!;
        expect(state.hintCell, isNull);
        expect(state.hintsUsed, 1);
        final ui = container.read(hintUiProvider(source));
        expect(ui.wrongCell, const GridPosition(row: 1, col: 0));
        expect(ui.thinking, isFalse);

        // Undoing (backtracking) clears the wrong-cell state.
        notifier.undo();
        expect(container.read(hintUiProvider(source)).isIdle, isTrue);
        notifier.pauseTimer();
      });

      testWidgets('none reports noHint and does not count', (tester) async {
        hintEngine.result = const HintResult.none();
        final container = makeContainer();
        final notifier = container.read(gameNotifierProvider(source).notifier);
        notifier.startGame(smallTestPuzzle);
        notifier.handleCellTap(0, 0);
        await notifier.useHint();
        expect(container.read(gameNotifierProvider(source))!.hintsUsed, 0);
        expect(container.read(hintUiProvider(source)).noHint, isTrue);
        notifier.pauseTimer();
      });

      testWidgets('shows thinking while solving and ignores re-entrant taps',
          (tester) async {
        var release = false;
        hintEngine.gate = () async {
          while (!release) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        };
        final container = makeContainer();
        final notifier = container.read(gameNotifierProvider(source).notifier);
        notifier.startGame(smallTestPuzzle);
        notifier.handleCellTap(0, 0);

        final first = notifier.useHint();
        await tester.pump();
        expect(container.read(hintUiProvider(source)).thinking, isTrue);

        // Second tap while thinking is a no-op.
        await notifier.useHint();
        expect(hintEngine.hintCalls, 1);

        release = true;
        await tester.pump(const Duration(milliseconds: 50));
        await first;
        expect(container.read(hintUiProvider(source)).thinking, isFalse);
        expect(container.read(gameNotifierProvider(source))!.hintsUsed, 1);
        notifier.pauseTimer();
      });

      testWidgets('a hint requested before the first move starts the game',
          (tester) async {
        final container = makeContainer();
        final notifier = container.read(gameNotifierProvider(source).notifier);
        notifier.startGame(smallTestPuzzle);
        await notifier.useHint();
        await tester.pump();
        final state = container.read(gameNotifierProvider(source))!;
        expect(state.status, GameStatus.playing);
        expect(state.hintCell, const GridPosition(row: 0, col: 1));
        expect(edge.calls.where((c) => c.$1 == 'start-puzzle'), hasLength(1));
        notifier.pauseTimer();
      });

      testWidgets('a stale verdict (path changed while thinking) is dropped',
          (tester) async {
        var release = false;
        hintEngine.gate = () async {
          while (!release) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        };
        final container = makeContainer();
        final notifier = container.read(gameNotifierProvider(source).notifier);
        notifier.startGame(smallTestPuzzle);
        notifier.handleCellTap(0, 0);
        final pending = notifier.useHint();
        await tester.pump();
        notifier.handleCellTap(0, 1); // player keeps going
        release = true;
        await tester.pump(const Duration(milliseconds: 50));
        await pending;
        final state = container.read(gameNotifierProvider(source))!;
        expect(state.hintCell, isNull);
        expect(state.hintsUsed, 0);
        notifier.pauseTimer();
      });
    });
  });
}
