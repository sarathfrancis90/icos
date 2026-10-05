import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/storage_service.dart';

import '../../helpers/storage_test_helpers.dart';

const _date = '2026-09-09';

void main() {
  late Directory dir;

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('per-user scoping', () {
    setUp(() async {
      dir = await initTestStorage(userId: 'user-a');
    });

    test('results, game state, nonces and solve count belong to one user',
        () async {
      await StorageService.saveSubmissionResult(_date, {'status': 'pending'});
      await StorageService.saveGameState(_date, {'path': <int>[]});
      await StorageService.saveSessionNonce(_date, 'nonce-a');
      await StorageService.incrementSolveCount();
      await StorageService.savePracticeStats({'count': 3});

      await StorageService.setActiveUser('user-b');

      expect(StorageService.getSubmissionResult(_date), isNull);
      expect(StorageService.getGameState(_date), isNull);
      expect(StorageService.getSessionNonce(_date), isNull);
      expect(StorageService.solveCount, 0);
      expect(StorageService.practiceStats, isEmpty);
      expect(StorageService.submissionResultDates(), isEmpty);

      // Nothing was destroyed: signing back in as A restores it.
      await StorageService.setActiveUser('user-a');
      expect(StorageService.getSubmissionResult(_date), {'status': 'pending'});
      expect(StorageService.getGameState(_date), isNotNull);
      expect(StorageService.getSessionNonce(_date), 'nonce-a');
      expect(StorageService.solveCount, 1);
      expect(StorageService.practiceStats['count'], 3);
    });

    test('device settings stay global across users', () async {
      await StorageService.setThemeMode('light');
      await StorageService.setHasSeenOnboarding(true);
      await StorageService.setHasSeenNotificationPrompt(true);

      await StorageService.setActiveUser('user-b');

      expect(StorageService.themeMode, 'light');
      expect(StorageService.hasSeenOnboarding, isTrue);
      expect(StorageService.hasSeenNotificationPrompt, isTrue);
    });

    test('guest linking keeps the same user id so nothing moves', () async {
      await StorageService.saveSubmissionResult(_date, {'status': 'pending'});
      await StorageService.addToSyncQueue({'type': 'submit_score'});

      // linkIdentity / updateUser fire userUpdated with the same id.
      await StorageService.setActiveUser('user-a');

      expect(StorageService.getSubmissionResult(_date), {'status': 'pending'});
      final items = StorageService.getSyncQueueItems();
      expect(items, hasLength(1));
      expect(items.single.value['user_id'], 'user-a');
    });

    test('signing in to another account leaves the guest records under the '
        'guest id', () async {
      await StorageService.saveSubmissionResult(_date, {'status': 'pending'});
      await StorageService.addToSyncQueue({'type': 'submit_score'});

      await StorageService.setActiveUser('existing-account');

      expect(StorageService.getSubmissionResult(_date), isNull);
      expect(StorageService.syncQueueLength, 0);
      // The guest's entry is still in the box, stamped with the guest id.
      final all = StorageService.getSyncQueueItems();
      expect(all.single.value['user_id'], 'user-a');
    });

    test('sync-queue entries record the user they were created under',
        () async {
      await StorageService.addToSyncQueue({'type': 'submit_score'});
      await StorageService.setActiveUser('user-b');
      await StorageService.addToSyncQueue({'type': 'start_puzzle'});

      final items = StorageService.getSyncQueueItems();
      expect(items.map((e) => e.value['user_id']), ['user-a', 'user-b']);
      expect(StorageService.syncQueueLength, 1);
    });

    test('other users\' queue entries are purged after 7 days, own are kept',
        () async {
      await StorageService.addToSyncQueue({'type': 'submit_score'});
      await StorageService.setActiveUser('user-b');
      await StorageService.addToSyncQueue({'type': 'submit_score'});

      final now = DateTime.now();
      // Inside the window: nothing is removed.
      await StorageService.purgeStaleForeignSyncEntries(
        now: now.add(const Duration(days: 6)),
      );
      expect(StorageService.getSyncQueueItems(), hasLength(2));

      await StorageService.purgeStaleForeignSyncEntries(
        now: now.add(const Duration(days: 8)),
      );
      final left = StorageService.getSyncQueueItems();
      expect(left, hasLength(1));
      expect(left.single.value['user_id'], 'user-b');
    });
  });

  group('upgrade from un-scoped storage', () {
    final legacy = <String, Object>{
      'submit_result_$_date': '{"status":"pending"}',
      'game_state_$_date': '{"path":[]}',
      'session_nonce_$_date': 'legacy-nonce',
      'solve_count': 4,
      'practice_stats': '{"count":2}',
      'theme_mode': 'light',
    };

    setUp(() async {
      dir = await initTestStorage(userId: null, prefs: legacy);
      await StorageService.addToSyncQueue({'type': 'submit_score'});
    });

    test('are adopted once by the first signed-in user', () async {
      await StorageService.setActiveUser('user-a');

      expect(StorageService.getSubmissionResult(_date), {'status': 'pending'});
      expect(StorageService.getGameState(_date), {'path': <Object>[]});
      expect(StorageService.getSessionNonce(_date), 'legacy-nonce');
      expect(StorageService.solveCount, 4);
      expect(StorageService.practiceStats['count'], 2);
      expect(StorageService.themeMode, 'light');
      expect(StorageService.syncQueueLength, 1);
      expect(
        StorageService.prefs.getKeys().where(
          (k) => k.startsWith('submit_result_') || k == 'solve_count',
        ),
        isEmpty,
        reason: 'legacy keys are moved, not copied',
      );
    });

    test('are not handed to a second user, and adoption is idempotent',
        () async {
      await StorageService.setActiveUser('user-a');
      await StorageService.setActiveUser('user-b');
      expect(StorageService.getSubmissionResult(_date), isNull);
      expect(StorageService.solveCount, 0);
      expect(StorageService.syncQueueLength, 0);

      await StorageService.setActiveUser('user-a');
      await StorageService.setActiveUser('user-a');
      expect(StorageService.getSubmissionResult(_date), {'status': 'pending'});
      expect(StorageService.solveCount, 4);
      expect(StorageService.syncQueueLength, 1);
    });

    test('wait for a user: no session yet means nothing is adopted', () async {
      await StorageService.setActiveUser(null);
      expect(StorageService.prefs.containsKey('solve_count'), isTrue);
      expect(StorageService.prefs.getBool('local_scope_migrated_v1'), isNot(true));

      await StorageService.setActiveUser('user-a');
      expect(StorageService.solveCount, 4);
    });
  });

  group('records made before any session existed', () {
    setUp(() async {
      dir = await initTestStorage(userId: null);
    });

    test('are adopted by the first user that appears', () async {
      await StorageService.saveSubmissionResult(_date, {'status': 'pending'});
      await StorageService.addToSyncQueue({'type': 'submit_score'});
      expect(StorageService.getSyncQueueItems().single.value['user_id'], isNull);

      await StorageService.setActiveUser('guest-1');

      expect(StorageService.getSubmissionResult(_date), {'status': 'pending'});
      expect(
        StorageService.getSyncQueueItems().single.value['user_id'],
        'guest-1',
      );
    });
  });

  group('adoption edge cases', () {
    test('an interrupted adoption that is re-run completes without loss or '
        'duplication', () async {
      // Halfway state: the first key was copied under user-a but its legacy
      // original was not yet removed; the second was not touched.
      dir = await initTestStorage(
        userId: null,
        prefs: {
          'submit_result_$_date': '{"status":"pending"}',
          'u.user-a.submit_result_$_date': '{"status":"pending"}',
          'game_state_$_date': '{"path":[]}',
          'solve_count': 4,
        },
      );

      await StorageService.setActiveUser('user-a');
      await StorageService.setActiveUser('user-a');

      expect(StorageService.getSubmissionResult(_date), {'status': 'pending'});
      expect(StorageService.getGameState(_date), {'path': <Object>[]});
      expect(StorageService.solveCount, 4);
      expect(
        StorageService.prefs.getKeys().where((k) => !k.startsWith('u.user-a.')
            && k != 'local_scope_migrated_v1'),
        isEmpty,
      );
    });

    test('when both a legacy and a scoped key exist, scoped wins and the '
        'legacy one is removed', () async {
      dir = await initTestStorage(
        userId: null,
        prefs: {
          'submit_result_$_date': '{"status":"legacy"}',
          'u.user-a.submit_result_$_date': '{"status":"scoped"}',
        },
      );

      await StorageService.setActiveUser('user-a');

      expect(StorageService.getSubmissionResult(_date), {'status': 'scoped'});
      expect(
        StorageService.prefs.containsKey('submit_result_$_date'),
        isFalse,
      );
    });

    test('a user change while adoption runs does not split the records',
        () async {
      dir = await initTestStorage(
        userId: null,
        prefs: {
          'submit_result_$_date': '{"status":"pending"}',
          'game_state_$_date': '{"path":[]}',
          'session_nonce_$_date': 'n',
          'solve_count': 4,
        },
      );

      final first = StorageService.setActiveUser('user-a');
      final second = StorageService.setActiveUser('user-b');
      await Future.wait([first, second]);

      await StorageService.setActiveUser('user-a');
      expect(StorageService.getSubmissionResult(_date), isNotNull);
      expect(StorageService.getGameState(_date), isNotNull);
      expect(StorageService.getSessionNonce(_date), 'n');
      expect(StorageService.solveCount, 4);
      await StorageService.setActiveUser('user-b');
      expect(StorageService.getSubmissionResult(_date), isNull);
      expect(StorageService.getSessionNonce(_date), isNull);
    });
  });

  group('explicit owner', () {
    setUp(() async {
      dir = await initTestStorage(userId: 'user-a');
    });

    test('a write pinned to a user lands under that user, not the active one',
        () async {
      await StorageService.setActiveUser('user-b');
      await StorageService.saveSubmissionResult(
        _date,
        {'status': 'pending'},
        userId: 'user-a',
      );

      expect(StorageService.getSubmissionResult(_date), isNull);
      expect(
        StorageService.getSubmissionResult(_date, userId: 'user-a'),
        {'status': 'pending'},
      );
    });

    test('clearUserData removes that user\'s records and queue entries only',
        () async {
      await StorageService.saveSubmissionResult(_date, {'status': 'x'});
      await StorageService.saveGameState(_date, {'path': <int>[]});
      await StorageService.saveSessionNonce(_date, 'n');
      await StorageService.incrementSolveCount();
      await StorageService.addToSyncQueue({'type': 'submit_score'});
      await StorageService.setActiveUser('user-b');
      await StorageService.saveSubmissionResult(_date, {'status': 'b'});
      await StorageService.addToSyncQueue({'type': 'submit_score'});
      await StorageService.setThemeMode('light');

      await StorageService.clearUserData('user-a');

      expect(
        StorageService.prefs.getKeys().where((k) => k.startsWith('u.user-a.')),
        isEmpty,
      );
      expect(
        StorageService.getSyncQueueItems().map((e) => e.value['user_id']),
        ['user-b'],
      );
      expect(StorageService.getSubmissionResult(_date), {'status': 'b'});
      expect(StorageService.themeMode, 'light');
    });
  });
}
