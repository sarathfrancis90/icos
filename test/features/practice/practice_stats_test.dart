import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/practice/providers/practice_provider.dart';

import '../../helpers/storage_test_helpers.dart';

void main() {
  group('PracticeStats', () {
    test('recordSolve tracks count, total and best per size', () {
      var stats = const PracticeStats();
      stats = stats.recordSolve(size: 5, timeSeconds: 60);
      stats = stats.recordSolve(size: 5, timeSeconds: 40);
      stats = stats.recordSolve(size: 6, timeSeconds: 90);
      stats = stats.recordSolve(size: 5, timeSeconds: 55);

      expect(stats.count, 4);
      expect(stats.totalTimeSeconds, 245);
      expect(stats.averageTimeSeconds, 61);
      expect(stats.bestBySize, {5: 40, 6: 90});
    });

    test('JSON round trip', () {
      const stats = PracticeStats(
        count: 2,
        totalTimeSeconds: 100,
        bestBySize: {5: 30, 7: 70},
      );
      final copy = PracticeStats.fromJson(stats.toJson());
      expect(copy.count, 2);
      expect(copy.totalTimeSeconds, 100);
      expect(copy.bestBySize, {5: 30, 7: 70});
    });

    test('tolerates missing / malformed JSON', () {
      final empty = PracticeStats.fromJson(const {});
      expect(empty.count, 0);
      expect(empty.bestBySize, isEmpty);
      final bad = PracticeStats.fromJson(const {
        'count': 'x',
        'best_by_size': {'nope': 1, '5': 'y'},
      });
      expect(bad.count, 0);
      expect(bad.bestBySize, isEmpty);
    });
  });

  group('PracticeStatsNotifier', () {
    late Directory dir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dir = await initTestStorage();
    });

    tearDown(() => dir.delete(recursive: true));

    test('persists to StorageService and reloads', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(practiceStatsNotifierProvider.notifier)
          .recordSolve(size: 6, timeSeconds: 33);

      expect(StorageService.practiceStats['count'], 1);

      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      final reloaded = fresh.read(practiceStatsNotifierProvider);
      expect(reloaded.count, 1);
      expect(reloaded.bestBySize[6], 33);
    });
  });

  test('newPracticeSeed is a non-negative 31-bit int', () {
    for (var i = 0; i < 100; i++) {
      final seed = newPracticeSeed();
      expect(seed, inInclusiveRange(0, 0x7FFFFFFE));
    }
  });
}
