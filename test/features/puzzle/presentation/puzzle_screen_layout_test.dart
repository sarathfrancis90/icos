import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_sizes.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/connectivity_service.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/practice/providers/practice_provider.dart';
import 'package:icos/features/puzzle/data/puzzle_source.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/puzzle_screen.dart';
import 'package:icos/features/puzzle/presentation/widgets/game_controls.dart';
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

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

Finder get _board => find
    .descendant(of: find.byType(PuzzleGrid), matching: find.byType(CustomPaint))
    .first;

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

  const sizes = [Size(320, 568), Size(393, 852)];
  for (final size in sizes) {
    for (final notice in [false, true]) {
      for (final tip in [false, true]) {
        final tag =
            '${size.width.toInt()}x${size.height.toInt()} notice=$notice tip=$tip';
        testWidgets('200% text fits: $tag', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await StorageService.setHasSeenFirstPlayHint(!tip);
          final p = notice
              ? puzzle.copyWith(origin: PuzzleOrigin.bundled)
              : puzzle;
          await _open(tester, _container(p), textScale: 2);
          expect(tester.takeException(), isNull);
          final screen = Offset.zero & size;
          bool inside(Rect r) =>
              r.left >= 0 &&
              r.top >= 0 &&
              r.right <= size.width + .01 &&
              r.bottom <= size.height + .01;
          // The controls stay pinned on screen and the HUD is at the top.
          expect(inside(tester.getRect(find.byType(GameControls))), isTrue);
          expect(
            inside(tester.getRect(find.byKey(const Key('puzzle_hud')))),
            isTrue,
          );
          // The board is whole and clear of the controls, either straight
          // away or (the last-resort scroll) after scrolling it into view.
          final controlsTop = tester.getTopLeft(find.byType(GameControls)).dy;
          if (tester.getRect(_board).bottom > controlsTop) {
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -2000),
            );
            await tester.pump(const Duration(milliseconds: 500));
          }
          final board = tester.getRect(_board);
          expect(screen.contains(board.topLeft), isTrue, reason: '$board');
          expect(
            board.bottom,
            lessThanOrEqualTo(controlsTop + .01),
            reason: '$board',
          );
          await _leave(tester);
        });
      }
    }

    testWidgets('1.0 text: grid keeps the full width, ${size.width.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await StorageService.setHasSeenFirstPlayHint(true);
      await _open(tester, _container(puzzle));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(_board).width,
        size.width - AppSizes.gridPadding * 2,
      );
      await _leave(tester);
    });
  }
}
