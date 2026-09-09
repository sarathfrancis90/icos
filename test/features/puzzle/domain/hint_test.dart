import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/game_engine.dart';
import 'package:icos/features/puzzle/domain/models/game_state.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';

void main() {
  // 3x3, unique solution: row snake (0,0)->(0,1)->(0,2)->(1,2)->(1,1)->...
  const unique = Puzzle(
    id: 'unique',
    puzzleDate: '2026-09-09',
    gridSize: 3,
    waypoints: [
      Waypoint(order: 1, row: 0, col: 0),
      Waypoint(order: 2, row: 0, col: 2),
      Waypoint(order: 3, row: 1, col: 1),
      Waypoint(order: 4, row: 2, col: 2),
    ],
    walls: [],
    difficulty: 'easy',
    parTimeSeconds: 30,
  );

  // 3x3 corner-to-corner: two solutions (row snake and column snake).
  const twoSolutions = Puzzle(
    id: 'two',
    puzzleDate: '2026-09-09',
    gridSize: 3,
    waypoints: [
      Waypoint(order: 1, row: 0, col: 0),
      Waypoint(order: 2, row: 2, col: 2),
    ],
    walls: [],
    difficulty: 'easy',
    parTimeSeconds: 30,
  );

  // Ring with centre wall, corner to opposite corner: unsolvable.
  const unsolvable = Puzzle(
    id: 'unsolvable',
    puzzleDate: '2026-09-09',
    gridSize: 3,
    waypoints: [
      Waypoint(order: 1, row: 0, col: 0),
      Waypoint(order: 2, row: 2, col: 2),
    ],
    walls: [Wall(row: 1, col: 1)],
    difficulty: 'easy',
    parTimeSeconds: 30,
  );

  const rowSnake = [
    GridPosition(row: 0, col: 0),
    GridPosition(row: 0, col: 1),
    GridPosition(row: 0, col: 2),
    GridPosition(row: 1, col: 2),
    GridPosition(row: 1, col: 1),
    GridPosition(row: 1, col: 0),
    GridPosition(row: 2, col: 0),
    GridPosition(row: 2, col: 1),
    GridPosition(row: 2, col: 2),
  ];

  group('solvePuzzle', () {
    test('returns the unique solution', () {
      expect(solvePuzzle(unique), rowSnake);
    });

    test('returns null for unsolvable puzzles', () {
      expect(solvePuzzle(unsolvable), isNull);
    });

    test('is cached and immutable', () {
      final a = solvePuzzle(unique)!;
      final b = solvePuzzle(unique)!;
      expect(identical(a, b), isTrue);
      expect(() => a.add(const GridPosition(row: 0, col: 0)), throwsUnsupportedError);
    });

    test('cache distinguishes puzzles that share an id', () {
      const p1 = Puzzle(
        id: 'shared',
        puzzleDate: '2026-09-09',
        gridSize: 3,
        waypoints: [
          Waypoint(order: 1, row: 0, col: 0),
          Waypoint(order: 2, row: 0, col: 2),
          Waypoint(order: 3, row: 1, col: 1),
          Waypoint(order: 4, row: 2, col: 2),
        ],
        walls: [],
        difficulty: 'easy',
        parTimeSeconds: 30,
      );
      const p2 = Puzzle(
        id: 'shared',
        puzzleDate: '2026-09-09',
        gridSize: 3,
        waypoints: [
          Waypoint(order: 1, row: 0, col: 0),
          Waypoint(order: 2, row: 1, col: 0),
          Waypoint(order: 3, row: 1, col: 1),
          Waypoint(order: 4, row: 2, col: 2),
        ],
        walls: [],
        difficulty: 'easy',
        parTimeSeconds: 30,
      );
      expect(solvePuzzle(p1)!.first, const GridPosition(row: 0, col: 0));
      expect(solvePuzzle(p1)![1], const GridPosition(row: 0, col: 1));
      expect(solvePuzzle(p2)![1], const GridPosition(row: 1, col: 0));
    });
  });

  group('computeHint', () {
    test('empty path yields the first waypoint', () {
      expect(
        computeHint(unique, const []),
        const HintResult.nextCell(GridPosition(row: 0, col: 0)),
      );
    });

    test('prefix of the solution yields the next cell', () {
      for (var i = 1; i < rowSnake.length; i++) {
        final result = computeHint(unique, rowSnake.sublist(0, i));
        expect(result.type, HintType.nextCell);
        expect(result.cell, rowSnake[i], reason: 'after $i cells');
      }
    });

    test('complete path yields none', () {
      expect(computeHint(unique, rowSnake), const HintResult.none());
    });

    test('divergent path yields the first wrong cell', () {
      final result = computeHint(unique, const [
        GridPosition(row: 0, col: 0),
        GridPosition(row: 1, col: 0),
        GridPosition(row: 2, col: 0),
      ]);
      expect(result.type, HintType.wrongCell);
      expect(result.cell, const GridPosition(row: 1, col: 0));
    });

    test('wrong cell is the first divergence, not the last move', () {
      final result = computeHint(unique, const [
        GridPosition(row: 0, col: 0),
        GridPosition(row: 0, col: 1),
        GridPosition(row: 1, col: 1),
        GridPosition(row: 1, col: 0),
      ]);
      expect(result, const HintResult.wrongCell(GridPosition(row: 1, col: 1)));
    });

    test('non-unique puzzle: follows an alternative valid line', () {
      // Column snake is a valid solution, so the hint continues it.
      final result = computeHint(twoSolutions, const [
        GridPosition(row: 0, col: 0),
        GridPosition(row: 1, col: 0),
      ]);
      expect(result, const HintResult.nextCell(GridPosition(row: 2, col: 0)));
    });

    test('unsolvable puzzle yields none', () {
      expect(computeHint(unsolvable, const []), const HintResult.none());
    });

    test('accepts a precomputed solution', () {
      final result = computeHint(
        unique,
        rowSnake.sublist(0, 3),
        solution: rowSnake,
      );
      expect(result, const HintResult.nextCell(GridPosition(row: 1, col: 2)));
    });
  });

  group('GameEngine hints', () {
    late GameEngine engine;
    late GameState state;

    setUp(() {
      engine = GameEngine(unique);
      state = engine.createInitialState();
    });

    test('getHint on empty path returns first waypoint', () {
      expect(engine.getHint(state), const GridPosition(row: 0, col: 0));
    });

    test('useHint highlights the next cell and increments hintsUsed', () {
      state = engine.addToPath(state, 0, 0);
      final hinted = engine.useHint(state);
      expect(hinted.hintCell, const GridPosition(row: 0, col: 1));
      expect(hinted.hintsUsed, 1);
    });

    test('getHintResult reports wrong cell; useHint leaves state unchanged', () {
      state = engine.addToPath(state, 0, 0);
      state = engine.addToPath(state, 1, 0);
      final result = engine.getHintResult(state);
      expect(result.type, HintType.wrongCell);
      expect(result.cell, const GridPosition(row: 1, col: 0));
      expect(engine.getHint(state), isNull);
      final unchanged = engine.useHint(state);
      expect(unchanged, state);
    });

    test('solved puzzle gives no hint', () {
      for (final p in rowSnake) {
        state = engine.addToPath(state, p.row, p.col);
      }
      expect(engine.isSolved(state), isTrue);
      expect(engine.getHintResult(state), const HintResult.none());
    });
  });

  group('HintResult', () {
    test('equality and toString', () {
      expect(
        const HintResult.nextCell(GridPosition(row: 1, col: 2)),
        const HintResult.nextCell(GridPosition(row: 1, col: 2)),
      );
      expect(
        const HintResult.nextCell(GridPosition(row: 1, col: 2)),
        isNot(const HintResult.wrongCell(GridPosition(row: 1, col: 2))),
      );
      expect(const HintResult.none().toString(), contains('none'));
    });
  });
}
