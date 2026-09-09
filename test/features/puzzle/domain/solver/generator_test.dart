import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

void expectValidGenerated(GeneratedPuzzle p, DifficultyParams params) {
  expect(p.gridSize, params.gridSize);
  expect(p.walls.length, inInclusiveRange(params.minWalls, params.maxWalls));
  expect(isHamiltonianFeasible(p.gridSize, p.walls), isTrue);
  expect(p.referencePath.length, p.openCells);

  // Waypoints are ordered points on the reference path.
  expect(p.waypoints.first, p.referencePath.first);
  expect(p.waypoints.last, p.referencePath.last);
  var last = -1;
  for (final w in p.waypoints) {
    final idx = p.referencePath.indexOf(w);
    expect(idx, greaterThan(last));
    last = idx;
  }
  expect(p.waypoints.length, inInclusiveRange(2, params.maxWaypoints));

  // Reference path validates and is the unique solution.
  final v = validatePath(p.gridSize, p.walls, p.waypoints, p.referencePathCells);
  expect(v.ok, isTrue, reason: v.reason);
  final res = countSolutions(p.gridSize, p.walls, p.waypoints, limit: 2);
  expect(res.isUnique, isTrue, reason: 'count=${res.count} exhausted=${res.exhausted}');
  expect(res.solutions.single, p.referencePath);

  expect(p.difficultyScore, greaterThan(0));
  expect(p.parTimeSeconds, parTimeFor(p.openCells, p.difficulty));
}

void main() {
  group('difficultyParams', () {
    test('match the product table', () {
      expect(difficultyParams(Difficulty.easy).gridSize, 5);
      expect(difficultyParams(Difficulty.medium).gridSize, 6);
      expect(difficultyParams(Difficulty.hard).gridSize, 7);
      expect(difficultyParams(Difficulty.expert).gridSize, 8);
      expect(difficultyParams(Difficulty.easy).maxWalls, 1);
      expect(difficultyParams(Difficulty.medium).minWalls, 2);
      expect(difficultyParams(Difficulty.hard).minimal, isTrue);
      expect(difficultyParams(Difficulty.medium).minimal, isFalse);
      expect(
        [for (final d in Difficulty.values) difficultyParams(d).maxWaypoints],
        [8, 9, 10, 14],
      );
      expect(difficultyParams(Difficulty.expert).maxWalls, 7);
      expect(difficultyParams(Difficulty.easy).padMin, 6);
      expect(difficultyParams(Difficulty.medium).padMax, 6);
    });

    test('parTimeFor uses 2.0/2.4/2.8/3.2', () {
      expect(parTimeFor(25, Difficulty.easy), 50);
      expect(parTimeFor(33, Difficulty.medium), 79);
      expect(parTimeFor(45, Difficulty.hard), 126);
      expect(parTimeFor(58, Difficulty.expert), 186);
    });

    test('Difficulty.parse round-trips', () {
      for (final d in Difficulty.values) {
        expect(Difficulty.parse(d.name), d);
      }
      expect(() => Difficulty.parse('nightmare'), throwsArgumentError);
    });
  });

  group('weekdayDifficulty', () {
    test('Mon/Tue easy, Wed/Thu medium, Fri/Sat hard, Sun expert (UTC)', () {
      expect(weekdayDifficulty('2026-09-07'), Difficulty.easy); // Monday
      expect(weekdayDifficulty('2026-09-08'), Difficulty.easy);
      expect(weekdayDifficulty('2026-09-09'), Difficulty.medium);
      expect(weekdayDifficulty('2026-09-10'), Difficulty.medium);
      expect(weekdayDifficulty('2026-09-11'), Difficulty.hard);
      expect(weekdayDifficulty('2026-09-12'), Difficulty.hard);
      expect(weekdayDifficulty('2026-09-13'), Difficulty.expert); // Sunday
    });
  });

  group('placeWalls', () {
    test('produces feasible layouts of the requested size', () {
      for (var seed = 0; seed < 20; seed++) {
        final walls = placeWalls(7, 5, Rng(seed));
        expect(walls, isNotNull);
        expect(walls!.length, 5);
        expect(isHamiltonianFeasible(7, walls), isTrue);
      }
    });

    test('zero walls returns an empty set', () {
      expect(placeWalls(5, 0, Rng(1)), isEmpty);
    });
  });

  group('chooseWaypoints', () {
    test('returns a unique waypoint set on a known path', () {
      const path = [0, 1, 2, 5, 4, 3, 6, 7, 8];
      final wps = chooseWaypoints(path, 3, const {}, Rng(1));
      expect(wps, isNotNull);
      expect(wps!.first, 0);
      expect(wps.last, 8);
      expect(countSolutions(3, const {}, wps).isUnique, isTrue);
    });

    test('pads to the requested range without breaking uniqueness', () {
      final path = findHamiltonianPath(5, const {}, Rng(3))!;
      final wps = chooseWaypoints(
        path,
        5,
        const {},
        Rng(3),
        maxWaypoints: 8,
        padMin: 6,
        padMax: 7,
      );
      expect(wps, isNotNull);
      expect(wps!.length, inInclusiveRange(6, 8));
      expect(countSolutions(5, const {}, wps).isUnique, isTrue);
    });

    test('minimal pass keeps uniqueness', () {
      final path = findHamiltonianPath(6, {7, 20}, Rng(5))!;
      final wps = chooseWaypoints(
        path,
        6,
        {7, 20},
        Rng(5),
        minimal: true,
        maxWaypoints: 12,
      );
      expect(wps, isNotNull);
      final res = countSolutions(6, {7, 20}, wps!);
      expect(res.isUnique, isTrue);
      // Removing any interior waypoint must break uniqueness.
      for (var i = 1; i < wps.length - 1; i++) {
        final reduced = [...wps]..removeAt(i);
        final r = countSolutions(6, {7, 20}, reduced);
        expect(r.isUnique, isFalse, reason: 'waypoint $i is redundant');
      }
    });

    test('gives up beyond maxWaypoints', () {
      final path = findHamiltonianPath(8, const {}, Rng(8))!;
      final wps = chooseWaypoints(path, 8, const {}, Rng(8), maxWaypoints: 2);
      expect(wps, isNull);
    });
  });

  group('generatePuzzle', () {
    for (final difficulty in Difficulty.values) {
      test('${difficulty.name}: valid, unique and deterministic', () {
        final params = difficultyParams(difficulty);
        final seed = seedFor('2026-09-09', 'test-${difficulty.name}');
        final a = generatePuzzle(difficulty: difficulty, seed: seed);
        final b = generatePuzzle(difficulty: difficulty, seed: seed);
        expectValidGenerated(a, params);
        expect(a.toJson(), b.toJson());

        // Retries use seed + attempt, so compare against an unrelated seed.
        final c = generatePuzzle(
          difficulty: difficulty,
          seed: seedFor('2031-01-01', 'other-${difficulty.name}'),
        );
        expect(c.toJson(), isNot(a.toJson()));

        if (params.padMin != null) {
          expect(
            a.waypoints.length,
            inInclusiveRange(params.padMin!, params.maxWaypoints),
          );
        }
      });
    }

    test('multiple seeds per difficulty all produce unique puzzles', () {
      for (final difficulty in Difficulty.values) {
        for (var i = 0; i < 3; i++) {
          final p = generatePuzzle(
            difficulty: difficulty,
            seed: seedFor('2026-01-0${i + 1}', 'multi'),
          );
          expectValidGenerated(p, difficultyParams(difficulty));
        }
      }
    });

    test('toJson and puzzleFromGenerated agree', () {
      final g = generatePuzzle(difficulty: Difficulty.medium, seed: 77);
      final json = g.toJson();
      expect(json['grid_size'], 6);
      expect(json['difficulty'], 'medium');
      expect(json['difficulty_score'], g.difficultyScore);
      expect((json['waypoints'] as List).length, g.waypoints.length);

      final puzzle = puzzleFromGenerated(g, id: 'p', puzzleDate: '2026-09-09');
      expect(puzzle.gridSize, 6);
      expect(puzzle.difficultyScore, g.difficultyScore);
      expect(puzzle.waypoints.first.order, 1);
      expect(waypointIndices(puzzle), g.waypoints);
      expect(wallIndices(puzzle), g.walls.toSet());
      // Round-trip via JSON (snake_case) keeps difficulty_score.
      final round = Puzzle.fromJson(
        jsonDecode(jsonEncode(puzzle.toJson())) as Map<String, dynamic>,
      );
      expect(round, puzzle);
      expect(puzzle.toJson().containsKey('solution_hash'), isFalse);
      expect(puzzle.toJson()['difficulty_score'], g.difficultyScore);
    });

    test('throws after exhausting attempts', () {
      // A 2x2 grid with 3 walls cannot produce a puzzle of >= 2 cells.
      expect(
        () => generatePuzzle(
          difficulty: Difficulty.expert,
          seed: 1,
          size: 2,
          maxAttempts: 2,
        ),
        throwsA(isA<PuzzleGenerationException>()),
      );
    });
  });

  group('performance', () {
    test('generation timings (JIT)', () {
      final report = StringBuffer('\nGeneration timings (JIT, 5 seeds each):\n');
      final maxByDifficulty = <Difficulty, int>{};
      for (final difficulty in Difficulty.values) {
        final times = <int>[];
        var attempts = 0;
        for (var i = 0; i < 5; i++) {
          final sw = Stopwatch()..start();
          final p = generatePuzzle(
            difficulty: difficulty,
            seed: seedFor('2026-10-${10 + i}', 'perf'),
          );
          sw.stop();
          times.add(sw.elapsedMilliseconds);
          attempts += p.attempts;
        }
        final avg = times.reduce((a, b) => a + b) / times.length;
        final max = times.reduce((a, b) => a > b ? a : b);
        maxByDifficulty[difficulty] = max;
        report.writeln(
          '  ${difficulty.name.padRight(6)} '
          'avg ${avg.toStringAsFixed(0).padLeft(5)} ms  '
          'max ${max.toString().padLeft(5)} ms  '
          'attempts/puzzle ${(attempts / 5).toStringAsFixed(1)}  '
          'samples $times',
        );
      }
      // ignore: avoid_print
      print(report);
      // Generous ceilings to catch pathological regressions without flaking.
      expect(maxByDifficulty[Difficulty.hard], lessThan(4000));
      expect(maxByDifficulty[Difficulty.expert], lessThan(8000));
    });
  });
}
