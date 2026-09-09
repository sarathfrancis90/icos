import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/storage_service.dart';

import '../../helpers/storage_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await initTestStorage();
  });

  tearDown(() => dir.delete(recursive: true));

  group('puzzle cache', () {
    test('keeps only the newest 60 dates', () async {
      // 70 consecutive dates.
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 70; i++) {
        final d = base.add(Duration(days: i));
        final key =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        await StorageService.cachePuzzle(key, {'id': key});
      }
      expect(StorageService.puzzleCache.length, StorageService.maxCachedPuzzles);
      expect(StorageService.getCachedPuzzle('2026-01-01'), isNull);
      expect(StorageService.getCachedPuzzle('2026-01-10'), isNull);
      expect(StorageService.getCachedPuzzle('2026-01-11'), isNotNull);
      expect(StorageService.getCachedPuzzle('2026-03-11'), isNotNull);
    });

    test('corrupt entries read as null', () async {
      await StorageService.puzzleCache.put('2026-09-09', '{not json');
      expect(StorageService.getCachedPuzzle('2026-09-09'), isNull);
    });
  });

  group('sync queue', () {
    test('preserves insertion order with unique keys', () async {
      for (var i = 0; i < 5; i++) {
        await StorageService.addToSyncQueue({'n': i});
      }
      final items = StorageService.getSyncQueueItems();
      expect(items.map((e) => e.value['n']), [0, 1, 2, 3, 4]);
      expect(items.map((e) => e.key).toSet(), hasLength(5));
      await StorageService.removeSyncQueueItem(items[2].key);
      expect(
        StorageService.getSyncQueueItems().map((e) => e.value['n']),
        [0, 1, 3, 4],
      );
    });
  });

  group('prefs-backed records', () {
    test('session nonce, submission result and practice stats round trip',
        () async {
      await StorageService.saveSessionNonce('2026-09-09', 'n1');
      expect(StorageService.getSessionNonce('2026-09-09'), 'n1');
      expect(StorageService.getSessionNonce('2026-09-08'), isNull);

      await StorageService.saveSubmissionResult('2026-09-09', {'status': 'x'});
      expect(StorageService.getSubmissionResult('2026-09-09'), {'status': 'x'});
      expect(StorageService.submissionResultDates(), contains('2026-09-09'));
      await StorageService.clearSubmissionResult('2026-09-09');
      expect(StorageService.getSubmissionResult('2026-09-09'), isNull);

      await StorageService.savePracticeStats({'count': 2});
      expect(StorageService.practiceStats['count'], 2);

      expect(StorageService.hasRequestedReview, isFalse);
      await StorageService.setHasRequestedReview(true);
      expect(StorageService.hasRequestedReview, isTrue);
    });
  });
}
