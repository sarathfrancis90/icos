import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_strings.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/practice/providers/practice_provider.dart';
import 'package:icos/features/puzzle/data/puzzle_repository.dart';
import 'package:icos/features/puzzle/data/submission_result.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/first_play_tooltip.dart';
import 'package:icos/features/puzzle/presentation/widgets/offline_puzzle_notice.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';
import 'package:icos/features/puzzle/providers/game_provider.dart';

import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _SignedIn implements SessionGateway {
  @override
  bool get hasSession => true;

  @override
  Future<void> signInAnonymously() async {}
}

const _source = PracticePuzzleSource(seed: 7, size: 3, difficulty: 'easy');

ProviderContainer _container(Puzzle puzzle) {
  final c = ProviderContainer(
    overrides: [
      practicePuzzleProvider(_source).overrideWith((ref) async => puzzle),
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
  addTearDown(c.dispose);
  return c;
}

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container, {
  bool reduceMotion = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize,
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const MaterialApp(home: PuzzleScreen(source: _source)),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _cue(WidgetTester tester) =>
    tester.widget<PuzzleGrid>(find.byType(PuzzleGrid)).showStartCue;

Finder get _board => find
    .descendant(of: find.byType(PuzzleGrid), matching: find.byType(CustomPaint))
    .first;

Future<void> _drag(WidgetTester tester) async {
  final topLeft = tester.getTopLeft(_board);
  final cell = tester.getSize(_board).width / 3;
  await tester.dragFrom(topLeft + Offset(cell / 2, cell / 2), Offset(cell, 0));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUpTestEnvironment();

  late Directory dir;
  final puzzle = smallTestPuzzle.copyWith(puzzleDate: 'practice');

  setUp(() async {
    dir = await initTestStorage();
    await StorageService.setHasSeenNotificationPrompt(true);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('first open shows ring and tooltip; a drag clears both and '
      'sets the flag; the next open shows neither', (tester) async {
    phone(tester);
    await _open(tester, _container(puzzle));
    expect(_cue(tester), isTrue);
    expect(find.text(AppStrings.firstPlayTooltip), findsOneWidget);
    expect(StorageService.hasSeenFirstPlayHint, isFalse);

    await _drag(tester);
    expect(_cue(tester), isFalse);
    expect(StorageService.hasSeenFirstPlayHint, isTrue);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.text(AppStrings.firstPlayTooltip),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
    await _leave(tester);

    await _open(tester, _container(puzzle));
    expect(_cue(tester), isFalse);
    expect(find.text(AppStrings.firstPlayTooltip), findsNothing);
    await _leave(tester);
  });

  testWidgets('a first tap-to-select move also dismisses', (tester) async {
    phone(tester);
    await _open(tester, _container(puzzle));
    final cell = tester.getSize(_board).width / 3;
    await tester.tapAt(tester.getTopLeft(_board) + Offset(cell / 2, cell / 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_cue(tester), isFalse);
    expect(StorageService.hasSeenFirstPlayHint, isTrue);
    await _leave(tester);
  });

  testWidgets('tapping the tooltip dismisses it', (tester) async {
    phone(tester);
    await _open(tester, _container(puzzle));
    await tester.tap(find.text(AppStrings.firstPlayTooltip));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_cue(tester), isFalse);
    expect(StorageService.hasSeenFirstPlayHint, isTrue);
    await _leave(tester);
  });

  testWidgets('a puzzle restored mid-solve shows nothing', (tester) async {
    phone(tester);
    await StorageService.setHasSeenFirstPlayHint(true);
    final first = _container(puzzle);
    await _open(tester, first);
    first.read(gameNotifierProvider(_source).notifier).handleCellTap(0, 0);
    await tester.pump(const Duration(milliseconds: 300));
    await _leave(tester);

    await StorageService.setHasSeenFirstPlayHint(false);
    await _open(tester, _container(puzzle));
    expect(_cue(tester), isFalse);
    expect(find.text(AppStrings.firstPlayTooltip), findsNothing);
    expect(StorageService.hasSeenFirstPlayHint, isTrue);
    await _leave(tester);
  });

  testWidgets('reduced motion: ring present, nothing ticking', (tester) async {
    phone(tester);
    await _open(tester, _container(puzzle), reduceMotion: true);
    expect(_cue(tester), isTrue);
    await tester.pump(const Duration(seconds: 2));
    // Only the screen's own ambient animations may run; the grid adds none.
    final withCue = tester.binding.transientCallbackCount;
    await _drag(tester);
    expect(_cue(tester), isFalse);
    expect(withCue, lessThanOrEqualTo(tester.binding.transientCallbackCount));
    await _leave(tester);
  });

  testWidgets('no overflow at 200% text on 320x568', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, _container(puzzle), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.firstPlayTooltip), findsOneWidget);
    expect(_cue(tester), isTrue);
    await _leave(tester);
  });

  testWidgets('sits under the offline notice, clear of the grid', (
    tester,
  ) async {
    phone(tester);
    final bundled = puzzle.copyWith(origin: PuzzleOrigin.bundled);
    await _open(tester, _container(bundled));
    expect(tester.takeException(), isNull);
    expect(find.byType(OfflinePuzzleNotice), findsOneWidget);
    final notice = tester.getRect(find.byType(OfflinePuzzleNotice));
    final tip = tester.getRect(find.byType(FirstPlayTooltip));
    final grid = tester.getRect(_board);
    expect(tip.top, greaterThanOrEqualTo(notice.bottom));
    expect(tip.bottom, lessThanOrEqualTo(grid.top));
    await _leave(tester);
  });

  testWidgets('a pan that draws nothing does not burn the flag', (
    tester,
  ) async {
    phone(tester);
    await _open(tester, _container(puzzle));
    // Start on an empty cell that is not waypoint 1: rejected, no path.
    final cell = tester.getSize(_board).width / 3;
    await tester.dragFrom(
      tester.getTopLeft(_board) + Offset(cell * 2.5, cell * 2.5),
      Offset(0, -cell),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(_cue(tester), isTrue);
    expect(StorageService.hasSeenFirstPlayHint, isFalse);
    await _drag(tester);
    expect(_cue(tester), isFalse);
    expect(StorageService.hasSeenFirstPlayHint, isTrue);
    await _leave(tester);
  });

  testWidgets('daily source: ring and tooltip on first open, gone after a '
      'drag', (tester) async {
    phone(tester);
    final today = AppDateUtils.todayUtc();
    final daily = PuzzleSource.daily(today);
    final dp = smallTestPuzzle.copyWith(puzzleDate: today);
    final c = ProviderContainer(
      overrides: [
        puzzleForDateProvider(today).overrideWith((ref) async => dp),
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
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: PuzzleScreen(source: daily)),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_cue(tester), isTrue);
    expect(find.text(AppStrings.firstPlayTooltip), findsOneWidget);
    await _drag(tester);
    expect(_cue(tester), isFalse);
    expect(StorageService.hasSeenFirstPlayHint, isTrue);
    await _leave(tester);
  });
}

class _NoAttempts extends PuzzleRepository {
  _NoAttempts()
    : super(invoker: (fn, body) async => const EdgeResponse(500, {}));

  @override
  Future<SubmissionResult?> getOwnAttempt(String userId, String date) async =>
      null;
}
