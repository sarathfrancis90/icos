import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/puzzle/domain/solver/puzzle_core.dart';

/// Cross-implementation parity: the TypeScript core writes
/// `supabase/functions/_shared/fixtures/puzzle_parity.json`; this test checks
/// that the Dart core reaches the same validation verdicts and uniqueness.
///
/// Accepted fixture shapes (tolerant on purpose):
/// ```json
/// {
///   "cases": [
///     { "name": "...", "gridSize": 3, "walls": [[r,c]...] | [{row,col}] | [idx],
///       "waypoints": [[r,c]...] | [{order,row,col}] | [idx],
///       "path": [[r,c]...], "expectOk": true, "reason": "optional" }
///   ],
///   "puzzles": [ { "name": "...", "gridSize": 5, "walls": [...], "waypoints": [...],
///                  "referencePath": [[r,c]...] } ]
/// }
/// ```
/// A bare list is treated as `cases`.
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

T _pick<T>(Map<String, dynamic> m, List<String> keys, [T? fallback]) {
  for (final k in keys) {
    if (m.containsKey(k)) return m[k] as T;
  }
  if (fallback != null) return fallback;
  throw StateError('fixture missing one of $keys: ${m.keys.toList()}');
}

int _index(dynamic cell, int size) {
  if (cell is int) return cell;
  if (cell is List) return (cell[0] as int) * size + (cell[1] as int);
  final m = cell as Map<String, dynamic>;
  return (m['row'] as int) * size + (m['col'] as int);
}

List<int> _indices(dynamic list, int size, {bool sortByOrder = false}) {
  final items = (list as List<dynamic>? ?? const <dynamic>[]).toList();
  if (sortByOrder && items.isNotEmpty && items.first is Map) {
    items.sort(
      (a, b) => ((a as Map)['order'] as int).compareTo((b as Map)['order'] as int),
    );
  }
  return [for (final c in items) _index(c, size)];
}

List<List<int>> _cells(dynamic list, int size) {
  final items = list as List<dynamic>? ?? const <dynamic>[];
  return [
    for (final c in items)
      if (c is List)
        [for (final x in c) x as int]
      else if (c is Map)
        [c['row'] as int, c['col'] as int]
      else
        [(c as int) ~/ size, c % size],
  ];
}

void main() {
  final file = File(
    '${projectRoot().path}/supabase/functions/_shared/fixtures/puzzle_parity.json',
  );

  if (!file.existsSync()) {
    test(
      'parity fixtures',
      () {},
      skip: 'Fixture not present yet: ${file.path} '
          '(written by the TypeScript core). Skipping parity checks.',
    );
    return;
  }

  final raw = jsonDecode(file.readAsStringSync());
  final root = raw is List ? <String, dynamic>{'cases': raw} : raw as Map<String, dynamic>;
  final cases = (root['cases'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
  final puzzles = (root['puzzles'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  group('validatePath parity', () {
    test('fixture has validation cases', () {
      expect(cases, isNotEmpty, reason: 'fixture has no validation cases');
    });
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final name = _pick<String>(c, ['name', 'id'], 'case $i');
      test(name, () {
        final size = _pick<int>(c, ['gridSize', 'grid_size', 'size']);
        final walls = _indices(c['walls'], size);
        final waypoints = _indices(c['waypoints'], size, sortByOrder: true);
        final path = _cells(c['path'], size);
        final expectOk = _pick<bool>(c, ['expectOk', 'expect_ok', 'ok']);
        final verdict = validatePath(size, walls, waypoints, path);
        expect(
          verdict.ok,
          expectOk,
          reason: 'Dart verdict ${verdict.reason} vs expectOk=$expectOk',
        );
        final expectedReason = c['reason'] ?? c['expectReason'];
        if (!expectOk && expectedReason is String) {
          expect(verdict.reason, expectedReason);
        }
      });
    }
  });

  group('uniqueness parity', () {
    for (var i = 0; i < puzzles.length; i++) {
      final p = puzzles[i];
      final name = _pick<String>(p, ['name', 'id'], 'puzzle $i');
      test(name, () {
        final size = _pick<int>(p, ['gridSize', 'grid_size', 'size']);
        final walls = _indices(p['walls'], size);
        final waypoints = _indices(p['waypoints'], size, sortByOrder: true);
        final res = countSolutions(size, walls, waypoints, limit: 2);
        expect(res.isUnique, isTrue,
            reason: 'count=${res.count} exhausted=${res.exhausted}');
        final refRaw = p['referencePath'] ?? p['reference_path'] ?? p['solution'];
        if (refRaw != null) {
          final ref = _indices(refRaw, size);
          expect(res.solutions.single, ref);
          expect(validatePath(size, walls, waypoints, _cells(refRaw, size)).ok, isTrue);
        }
        final expectedCount = p['expectedSolutionCount'];
        if (expectedCount is int) expect(res.count, expectedCount);
        // difficultyScore is a node count and may legitimately differ between
        // implementations (pruning/ordering details); report it, do not assert.
        final score = p['difficultyScore'] ?? p['difficulty_score'];
        if (score is int) {
          final first = countSolutions(size, walls, waypoints, limit: 1);
          // ignore: avoid_print
          print('$name difficultyScore: ts=$score dart=${first.nodes}');
        }
      });
    }
  });
}
