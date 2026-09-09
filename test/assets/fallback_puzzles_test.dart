import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/models/puzzle.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

/// Locates the project root (directory containing pubspec.yaml) regardless of
/// the working directory `flutter test` was launched from.
Directory projectRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('pubspec.yaml not found above ${Directory.current}');
    }
    dir = parent;
  }
  return dir;
}

void main() {
  final file = File('${projectRoot().path}/assets/puzzles/fallback_puzzles.json');

  group('assets/puzzles/fallback_puzzles.json', () {
    late List<Puzzle> puzzles;

    setUpAll(() {
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
      final raw = jsonDecode(file.readAsStringSync());
      final list = raw is List
          ? raw
          : (raw as Map<String, dynamic>)['puzzles'] as List<dynamic>;
      puzzles = [
        for (final item in list) Puzzle.fromJson(item as Map<String, dynamic>),
      ];
    });

    test('contains 7 puzzles with distinct ids and dates', () {
      expect(puzzles.length, 7);
      expect(puzzles.map((p) => p.id).toSet().length, 7);
      expect(puzzles.map((p) => p.puzzleDate).toSet().length, 7);
    });

    test('every puzzle is well-formed', () {
      for (final p in puzzles) {
        final orders = p.waypoints.map((w) => w.order).toList();
        expect(orders, List.generate(orders.length, (i) => i + 1),
            reason: '${p.id}: waypoint orders must be 1..N');
        final walls = wallIndices(p);
        for (final w in p.waypoints) {
          expect(w.row, inInclusiveRange(0, p.gridSize - 1), reason: p.id);
          expect(w.col, inInclusiveRange(0, p.gridSize - 1), reason: p.id);
          expect(walls.contains(w.row * p.gridSize + w.col), isFalse,
              reason: '${p.id}: waypoint on wall');
        }
        expect(waypointIndices(p).toSet().length, p.waypoints.length,
            reason: '${p.id}: duplicate waypoint cells');
      }
    });

    test('every puzzle is feasible', () {
      for (final p in puzzles) {
        expect(isPuzzleFeasible(p), isTrue, reason: '${p.id} is infeasible');
      }
    });

    test('every puzzle has exactly one solution that validates', () {
      final failures = <String>[];
      for (final p in puzzles) {
        final res = solvePuzzleModel(p, limit: 2);
        if (!res.isUnique) {
          failures.add(
            '${p.id}: count=${res.count} exhausted=${res.exhausted} '
            'nodes=${res.nodes}',
          );
          continue;
        }
        final solution = positionsFromIndices(p.gridSize, res.solutions.single);
        final v = validatePuzzlePath(p, solution);
        if (!v.ok) failures.add('${p.id}: solution invalid (${v.reason})');
        final hint = computeHintSmoke(p);
        if (hint != solution.first) {
          failures.add('${p.id}: first hint $hint != ${solution.first}');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });
}

/// Sanity check that the solver-backed model helpers agree on the start cell.
dynamic computeHintSmoke(Puzzle p) {
  final sol = solvePuzzleModel(p, limit: 1);
  if (sol.count == 0) return null;
  return positionsFromIndices(p.gridSize, sol.solutions.first).first;
}
