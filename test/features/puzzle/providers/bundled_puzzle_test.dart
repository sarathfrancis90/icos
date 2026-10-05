import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/services/sync_service.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/puzzle/providers/game_provider.dart';
import 'package:icos/features/puzzle/providers/puzzle_result_provider.dart';
import 'package:icos/features/puzzle/providers/score_submission_provider.dart';

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

class _ControlledConnectivity extends ConnectivityNotifier {
  @override
  bool build() => true;

  void set(bool online) => state = online;
}

/// Repository whose answer can be switched between "server down" (bundled)
/// and "server up".
class _FakeRepository extends PuzzleRepository {
  _FakeRepository()
    : super(invoker: (fn, body) async => const EdgeResponse(500, {}));

  bool serverUp = false;
  int calls = 0;

  @override
  Future<Result<Puzzle, AppError>> getPuzzle(String date) async {
    calls++;
    return Result.success(
      smallTestPuzzle.copyWith(
        puzzleDate: date,
        origin: serverUp ? PuzzleOrigin.server : PuzzleOrigin.bundled,
      ),
    );
  }
}

class _FakeEdge {
  final calls = <(String, Map<String, dynamic>)>[];

  Future<EdgeResponse> call(String fn, Map<String, dynamic> body) async {
    calls.add((fn, body));
    return const EdgeResponse(200, {'completed': true, 'verified': true});
  }
}

class _MutableAuth extends AuthSessionInfo {
  _MutableAuth(this.userId);

  @override
  String? userId;

  @override
  bool get hasSession => userId != null;
}

class _AlreadySignedIn implements SessionGateway {
  @override
  bool get hasSession => true;

  @override
  Future<void> signInAnonymously() async {}
}

GameState _solved(Puzzle puzzle) =>
    createNotStartedGameState(puzzle: puzzle).copyWith(
      status: GameStatus.completed,
      elapsedSeconds: 33,
      path: const [GridPosition(row: 0, col: 0), GridPosition(row: 0, col: 1)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = AppDateUtils.todayUtc();
  late Directory dir;
  late _FakeEdge edge;
  late _FakeRepository repo;
  late ProviderContainer container;

  setUp(() async {
    dir = await initTestStorage();
    edge = _FakeEdge();
    repo = _FakeRepository();
    container = ProviderContainer(
      overrides: [
        edgeInvokerProvider.overrideWithValue(edge.call),
        connectivityNotifierProvider.overrideWith(_ControlledConnectivity.new),
        authSessionProvider.overrideWithValue(const FakeAuthSessionInfo()),
        sessionEnsurerProvider.overrideWithValue(
          SessionEnsurer(gateway: _AlreadySignedIn()),
        ),
        puzzleRepositoryProvider.overrideWithValue(repo),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await dir.delete(recursive: true);
  });

  final bundled = smallTestPuzzle.copyWith(
    puzzleDate: today,
    origin: PuzzleOrigin.bundled,
  );
  final server = smallTestPuzzle.copyWith(puzzleDate: today);

  group('solving a bundled puzzle', () {
    test('is never submitted or queued', () async {
      await container
          .read(scoreSubmitterProvider.notifier)
          .submitScore(_solved(bundled), PuzzleSource.daily(today));

      expect(edge.calls, isEmpty);
      expect(StorageService.syncQueueLength, 0);
      expect(StorageService.getSyncQueueItems(), isEmpty);
    });

    test('is stored apart from the daily result and does not count', () async {
      await container
          .read(scoreSubmitterProvider.notifier)
          .submitScore(_solved(bundled), PuzzleSource.daily(today));

      expect(StorageService.getSubmissionResult(today), isNull);
      expect(StorageService.getBundledResult(today), isNotNull);
      expect(StorageService.solveCount, 0);
    });

    test('does not make the daily result provider report solved', () async {
      await container
          .read(scoreSubmitterProvider.notifier)
          .submitScore(_solved(bundled), PuzzleSource.daily(today));

      final result = await container.read(puzzleResultProvider(today).future);
      expect(result, isNull);
    });

    test('does not block or overwrite the real puzzle\'s result', () async {
      await container
          .read(scoreSubmitterProvider.notifier)
          .submitScore(_solved(bundled), PuzzleSource.daily(today));

      // The server puzzle for the same date becomes available and is solved.
      await container
          .read(scoreSubmitterProvider.notifier)
          .submitScore(_solved(server), PuzzleSource.daily(today));

      expect(edge.calls.where((c) => c.$1 == 'submit-score'), hasLength(1));
      final stored = SubmissionResult.fromJson(
        StorageService.getSubmissionResult(today)!,
      );
      expect(stored.isAccepted, isTrue);
      expect(StorageService.getBundledResult(today), isNotNull);
      expect(StorageService.solveCount, 1);
    });
  });

  group('ScoreSubmitter pins its saves to the user who solved', () {
    test('a user switch during submission does not move the saves', () async {
      final auth = _MutableAuth('test-user');
      container.dispose();
      container = ProviderContainer(
        overrides: [
          edgeInvokerProvider.overrideWithValue(edge.call),
          connectivityNotifierProvider.overrideWith(_ControlledConnectivity.new),
          authSessionProvider.overrideWithValue(auth),
          sessionEnsurerProvider.overrideWithValue(
            SessionEnsurer(gateway: _AlreadySignedIn()),
          ),
          puzzleRepositoryProvider.overrideWithValue(repo),
        ],
      );
      final submitting = container
          .read(scoreSubmitterProvider.notifier)
          .submitScore(_solved(server), PuzzleSource.daily(today));
      auth.userId = 'someone-else';
      await StorageService.setActiveUser('someone-else');
      await submitting;

      expect(StorageService.solveCount, 0);
      expect(StorageService.getSubmissionResult(today), isNull);
      await StorageService.setActiveUser('test-user');
      expect(StorageService.solveCount, 1);
      expect(
        StorageService.getSyncQueueItems().map((e) => e.value['user_id']),
        everyElement('test-user'),
      );
    });
  });

  group('playing a bundled puzzle', () {
    test('keeps its in-progress state apart from the real puzzle\'s', () async {
      final source = PuzzleSource.daily(today);
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.startGame(bundled);
      notifier.handleCellTap(0, 0);

      expect(StorageService.getGameState(today), isNull);
      expect(StorageService.getGameState('bundled_$today'), isNotNull);

      // The real puzzle starts clean, not from the bundled path.
      notifier.startGame(server);
      expect(container.read(gameNotifierProvider(source))!.path, isEmpty);
    });

    test('does not ask the server for a session', () async {
      final source = PuzzleSource.daily(today);
      final notifier = container.read(gameNotifierProvider(source).notifier);
      notifier.startGame(bundled);
      notifier.handleCellTap(0, 0);
      await Future<void>.delayed(Duration.zero);

      expect(edge.calls.where((c) => c.$1 == 'start-puzzle'), isEmpty);
    });
  });

  group('the real puzzle after a bundled one', () {
    test('is offered once connectivity returns', () async {
      final sub = container.listen(puzzleForDateProvider(today), (_, _) {});
      addTearDown(sub.close);
      expect(
        (await container.read(puzzleForDateProvider(today).future)).origin,
        PuzzleOrigin.bundled,
      );

      repo.serverUp = true;
      final connectivity =
          container.read(connectivityNotifierProvider.notifier)
              as _ControlledConnectivity;
      connectivity.set(false);
      connectivity.set(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        (await container.read(puzzleForDateProvider(today).future)).origin,
        PuzzleOrigin.server,
      );
    });

    test(
      'a server puzzle is not re-fetched when connectivity returns',
      () async {
        repo.serverUp = true;
        final sub = container.listen(puzzleForDateProvider(today), (_, _) {});
        addTearDown(sub.close);
        await container.read(puzzleForDateProvider(today).future);
        final callsBefore = repo.calls;

        final connectivity =
            container.read(connectivityNotifierProvider.notifier)
                as _ControlledConnectivity;
        connectivity.set(false);
        connectivity.set(true);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(repo.calls, callsBefore);
      },
    );
  });
}
