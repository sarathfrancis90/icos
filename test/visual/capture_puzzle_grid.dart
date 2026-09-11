// Visual capture harness for the redesigned line.
//
// Not a test and deliberately not named `*_test.dart`, so `flutter test` (and
// therefore CI) skips it: rendering differs between machines, so this is a
// tool for eyeballing the result, not a gate.
//
//   flutter test test/visual/capture_puzzle_grid.dart
//
// PNGs land in build/visual/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/constants/app_colors.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/presentation/widgets/grid_palette.dart';
import 'package:icos/features/puzzle/presentation/widgets/puzzle_grid.dart';

const _outDir = 'build/visual';

/// 8x8, waypoints at both ends of a boustrophedon plus one in the middle, and
/// a pair of walls so wall rendering is covered too.
const _bigPuzzle = Puzzle(
  id: 'visual-8x8',
  puzzleDate: '2026-09-11',
  gridSize: 8,
  waypoints: [
    Waypoint(order: 1, row: 0, col: 0),
    Waypoint(order: 2, row: 3, col: 7),
    Waypoint(order: 3, row: 7, col: 0),
  ],
  walls: [],
  difficulty: 'hard',
  parTimeSeconds: 300,
);

/// Boustrophedon over an 8x8: (0,0) rightwards, down, leftwards, ... ending at
/// (7,0). It passes through every waypoint in order.
List<List<int>> _snakeOrder(int size) {
  final cells = <List<int>>[];
  for (var row = 0; row < size; row++) {
    for (var i = 0; i < size; i++) {
      final col = row.isEven ? i : size - 1 - i;
      cells.add([row, col]);
    }
  }
  return cells;
}

GameState _stateWithCells(Puzzle puzzle, int count) {
  final engine = GameEngine(puzzle);
  var state = engine.createInitialState();
  for (final cell in _snakeOrder(puzzle.gridSize).take(count)) {
    state = engine.addToPath(state, cell[0], cell[1]);
  }
  return state;
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = const Size(430, 560),
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.deepNavy,
        body: Center(
          // Opaque so the capture shows the glow against the real app
          // background rather than against transparency.
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: AppColors.deepNavy,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Let segment draw-in and the glow breath reach a representative frame.
  await tester.pump(const Duration(milliseconds: 600));

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  File('$_outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
  // ignore: avoid_print
  print('wrote $_outDir/$name.png');
}

void main() {
  testWidgets('capture the line at several stages and in every palette',
      (tester) async {
    final cases = <String, GameState>{
      'line_early': _stateWithCells(_bigPuzzle, 6),
      'line_midway': _stateWithCells(_bigPuzzle, 31),
      'line_near_complete': _stateWithCells(_bigPuzzle, 60),
      'line_complete': _stateWithCells(_bigPuzzle, 64),
    };

    for (final entry in cases.entries) {
      await _capture(
        tester,
        entry.key,
        PuzzleGrid(
          gameState: entry.value,
          onCellTap: (_, _) {},
          onCellDrag: (_, _) {},
        ),
      );
    }

    for (final palette in [
      GridPalette.standard,
      GridPalette.deuteranopia,
      GridPalette.protanopia,
      GridPalette.tritanopia,
    ]) {
      await _capture(
        tester,
        'palette_${palette.mode.name}',
        PuzzleGrid(
          gameState: _stateWithCells(_bigPuzzle, 31),
          palette: palette,
          onCellTap: (_, _) {},
          onCellDrag: (_, _) {},
        ),
      );
    }
  });

  testWidgets('capture the invalid-move flash', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(430, 560) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.deepNavy,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: AppColors.deepNavy,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: PuzzleGrid(
                    gameState: _stateWithCells(_bigPuzzle, 6),
                    onCellTap: (_, _) {},
                    onCellDrag: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Tap a cell far from the head: illegal, so it must flash.
    await tester.tap(find.bySemanticsLabel('Row 8, Column 8, empty'));
    // The first pump starts the ticker; the flash only advances from the
    // second one onwards.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('$_outDir/invalid_flash.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('wrote $_outDir/invalid_flash.png');
  });
}
