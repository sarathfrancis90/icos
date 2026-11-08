import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/legacy_cleanup.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/storage_test_helpers.dart';

/// Reads work; every write throws, like a full or read-only store.
class _ThrowingPrefs implements SharedPreferences {
  _ThrowingPrefs(this._inner);
  final SharedPreferences _inner;

  @override
  bool? getBool(String key) => _inner.getBool(key);
  @override
  Set<String> getKeys() => _inner.getKeys();
  @override
  Future<bool> remove(String key) => throw StateError('disk full');
  @override
  Future<bool> setBool(String key, bool value) =>
      throw StateError('disk full');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('LegacyCleanup', () {
    test('legacy_cleanup_runs_once', () async {
      final prefs = await _prefs({
        'sb-abcdefgh-auth-token': '{"access_token":"x"}',
        'theme_mode': 'dark',
      });
      var cleared = 0;

      final first = await LegacyCleanup.runIfNeeded(
        prefs,
        clearCaches: () async => cleared++,
      );

      expect(first, isTrue);
      expect(prefs.containsKey('sb-abcdefgh-auth-token'), isFalse);
      expect(prefs.getBool(LegacyCleanup.noticeShownKey), isTrue);
      expect(cleared, 1);
      // Device settings survive.
      expect(prefs.getString('theme_mode'), 'dark');

      final second = await LegacyCleanup.runIfNeeded(
        prefs,
        clearCaches: () async => cleared++,
      );
      expect(second, isFalse);
      expect(cleared, 1);
    });

    test('fresh install returns false and sets no notice flag', () async {
      final prefs = await _prefs({});
      var cleared = 0;

      final result = await LegacyCleanup.runIfNeeded(
        prefs,
        clearCaches: () async => cleared++,
      );

      expect(result, isFalse);
      expect(prefs.containsKey(LegacyCleanup.noticeShownKey), isFalse);
      expect(cleared, 0);
    });

    test('new-backend data on a later launch is not mistaken for legacy',
        () async {
      final prefs = await _prefs({});
      expect(await LegacyCleanup.runIfNeeded(prefs), isFalse);

      // The new app has since stored per-user data.
      await prefs.setBool('local_scope_migrated_v1', true);
      await prefs.setInt('u.newUserId123.solve_count', 2);

      expect(await LegacyCleanup.runIfNeeded(prefs), isFalse);
      expect(prefs.getInt('u.newUserId123.solve_count'), 2);
      expect(prefs.containsKey(LegacyCleanup.noticeShownKey), isFalse);
    });

    test('removes supabase.auth.token and every sb- key', () async {
      final prefs = await _prefs({
        'supabase.auth.token': 'legacy',
        'sb-ref-auth-token': 'a',
        'sb-ref-auth-token-code-verifier': 'b',
        'has_seen_onboarding': true,
      });

      expect(await LegacyCleanup.runIfNeeded(prefs), isTrue);

      expect(prefs.containsKey('supabase.auth.token'), isFalse);
      expect(prefs.getKeys().where((k) => k.startsWith('sb-')), isEmpty);
      expect(prefs.getBool('has_seen_onboarding'), isTrue);
    });

    test('pre-migration per-user storage counts as legacy', () async {
      // A 1.0.x install whose Supabase session was already gone: the old
      // user's scoped records and the scope marker are still there.
      final prefs = await _prefs({
        'local_scope_migrated_v1': true,
        'u.0b6f6c1e-1111-4222-8333-944445555666.solve_count': 12,
      });
      var cleared = 0;

      final result = await LegacyCleanup.runIfNeeded(
        prefs,
        clearCaches: () async => cleared++,
      );

      expect(result, isTrue);
      expect(cleared, 1);
      expect(prefs.getBool(LegacyCleanup.noticeShownKey), isTrue);
    });

    test('legacy Hive data alone counts as legacy', () async {
      final prefs = await _prefs({});
      var cleared = 0;

      final result = await LegacyCleanup.runIfNeeded(
        prefs,
        hasLegacyHiveData: () => true,
        clearCaches: () async => cleared++,
      );

      expect(result, isTrue);
      expect(cleared, 1);
      expect(await LegacyCleanup.runIfNeeded(prefs), isFalse);
    });

    test('a failing cache clear still finishes the cleanup', () async {
      final prefs = await _prefs({'sb-x-auth-token': 't'});

      final result = await LegacyCleanup.runIfNeeded(
        prefs,
        clearCaches: () async => throw StateError('disk'),
      );

      expect(result, isTrue);
      expect(prefs.containsKey('sb-x-auth-token'), isFalse);
      expect(await LegacyCleanup.runIfNeeded(prefs), isFalse);
    });

    test('a failing prefs write returns false instead of throwing', () async {
      final prefs = _ThrowingPrefs(await _prefs({'sb-x-auth-token': 't'}));

      final result = await LegacyCleanup.runIfNeeded(prefs);

      expect(result, isFalse);
    });

    test('with StorageService: clears queue, cache and player records, '
        'keeps device settings', () async {
      final dir = await initTestStorage(
        prefs: {
          'sb-ref-auth-token': 't',
          'local_scope_migrated_v1': true,
          'u.old-user.submit_result_2026-11-01': '{}',
          'u.old-user.solve_count': 4,
          'game_state_2026-01-01': '{}',
          'pending_invite_code': 'ABC123',
          'theme_mode': 'light',
          'has_seen_onboarding': true,
        },
        userId: null,
      );
      addTearDown(() => dir.delete(recursive: true));
      await StorageService.cachePuzzle('2026-11-01', {'id': 'p'});
      await StorageService.addToSyncQueue({'date': '2026-11-01'});

      final prefs = StorageService.prefs;
      final result = await LegacyCleanup.runIfNeeded(
        prefs,
        clearCaches: StorageService.clearAllPlayerData,
        hasLegacyHiveData: () => StorageService.hasHiveData,
      );

      expect(result, isTrue);
      expect(StorageService.puzzleCache.isEmpty, isTrue);
      expect(StorageService.syncQueue.isEmpty, isTrue);
      expect(StorageService.hasHiveData, isFalse);
      expect(prefs.getKeys().where((k) => k.startsWith('u.')), isEmpty);
      expect(prefs.containsKey('game_state_2026-01-01'), isFalse);
      expect(prefs.containsKey('sb-ref-auth-token'), isFalse);
      expect(StorageService.pendingInviteCode, isNull);
      expect(prefs.getString('theme_mode'), 'light');
      expect(prefs.getBool('has_seen_onboarding'), isTrue);
    });
  });
}
