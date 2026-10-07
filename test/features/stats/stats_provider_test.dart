import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/app_error.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/stats/data/stats_repository.dart';
import 'package:icos/features/stats/domain/models/streak.dart';
import 'package:icos/features/stats/presentation/stats_screen.dart';
import 'package:icos/features/stats/providers/stats_provider.dart';

import '../../helpers/storage_test_helpers.dart';
import '../../helpers/test_helpers.dart';

class _FakeRepo extends StatsRepository {
  _FakeRepo({this.fail = false, String? lastSolveDate})
    : lastSolveDate = lastSolveDate ?? AppDateUtils.todayUtc();
  bool fail;
  String lastSolveDate;

  @override
  Future<Result<Streak, AppError>> getStreak(String userId) async => fail
      ? const Result.failure(AppError.network('down'))
      : Result.success(
          Streak(
            userId: userId,
            currentStreak: 40,
            longestStreak: 41,
            freezeCount: 0,
            lastSolveDate: lastSolveDate,
          ),
        );

  @override
  Future<Result<int, AppError>> getTotalSolved(String userId) async => fail
      ? const Result.failure(AppError.network('down'))
      : const Result.success(55);

  @override
  Future<Result<int, AppError>> getAverageTime(String userId) async => fail
      ? const Result.failure(AppError.network('down'))
      : const Result.success(90);

  @override
  Future<Result<List<SolveHistory>, AppError>> getSolveHistory(
    String userId, {
    int limit = 30,
  }) async => fail
      ? const Result.failure(AppError.network('down'))
      : const Result.success([
          SolveHistory(
            date: '2026-10-04',
            timeSeconds: 70,
            hintsUsed: 0,
            undosUsed: 0,
            completed: true,
          ),
        ]);
}

void main() {
  setUpTestEnvironment();
  late Directory dir;

  setUp(() async {
    dir = (await initTestStorage())!;
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('loadStatsOverview', () {
    test('success returns fresh data and updates the cache', () async {
      final o = await loadStatsOverview(_FakeRepo(), 'test-user');
      expect(o.currentStreak, 40);
      expect(o.fromCache, isFalse);
      expect(
        StorageService.getStatsCache('overview', userId: 'test-user'),
        isNotNull,
      );
    });

    test('failure with a cached copy returns it flagged as cached', () async {
      await loadStatsOverview(_FakeRepo(), 'test-user');
      final o = await loadStatsOverview(_FakeRepo(fail: true), 'test-user');
      expect(o.currentStreak, 40);
      expect(o.totalSolved, 55);
      expect(o.fromCache, isTrue);
    });

    test('a streak whose last solve is two days ago shows 0', () async {
      final o = await loadStatsOverview(
        _FakeRepo(lastSolveDate: AppDateUtils.dateNDaysAgo(2)),
        'test-user',
      );
      expect(o.currentStreak, 0);
      expect(o.longestStreak, 41);
    });

    test('a cached streak that has gone stale is served as 0', () async {
      await loadStatsOverview(_FakeRepo(), 'test-user');
      final realClock = AppDateUtils.clock;
      addTearDown(() => AppDateUtils.clock = realClock);
      AppDateUtils.clock = () => DateTime.now().add(const Duration(days: 2));
      final o = await loadStatsOverview(_FakeRepo(fail: true), 'test-user');
      expect(o.fromCache, isTrue);
      expect(o.currentStreak, 0);
      expect(cachedCurrentStreak('test-user'), 0);
    });

    test('cachedCurrentStreak returns the live cached streak', () async {
      await loadStatsOverview(_FakeRepo(), 'test-user');
      expect(cachedCurrentStreak('test-user'), 40);
    });

    test('a cache without the last solve date is treated as unknown', () async {
      await StorageService.saveStatsCache('overview', const {
        'currentStreak': 9,
        'longestStreak': 9,
        'totalSolved': 20,
        'averageTimeSeconds': 60,
        'freezeCount': 1,
        'lastFreezeUsedAt': null,
      }, userId: 'test-user');
      expect(cachedCurrentStreak('test-user'), isNull);
      await expectLater(
        loadStatsOverview(_FakeRepo(fail: true), 'test-user'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('failure without a cache throws instead of showing zeros', () async {
      await expectLater(
        loadStatsOverview(_FakeRepo(fail: true), 'test-user'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('cache is per user', () async {
      await loadStatsOverview(_FakeRepo(), 'test-user');
      await expectLater(
        loadStatsOverview(_FakeRepo(fail: true), 'someone-else'),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('loadSolveHistory', () {
    test('falls back to cache, throws without one', () async {
      await expectLater(
        loadSolveHistory(_FakeRepo(fail: true), 'test-user'),
        throwsA(isA<NetworkError>()),
      );
      await loadSolveHistory(_FakeRepo(), 'test-user');
      final h = await loadSolveHistory(_FakeRepo(fail: true), 'test-user');
      expect(h.single.date, '2026-10-04');
    });
  });

  group('StatsScreen', () {
    Widget screen(_FakeRepo repo) => buildTestWidget(
      const Scaffold(body: StatsScreen()),
      overrides: [
        statsOverviewProvider.overrideWith(
          (ref) => loadStatsOverview(repo, 'test-user'),
        ),
        solveHistoryProvider.overrideWith(
          (ref) => loadSolveHistory(repo, 'test-user'),
        ),
      ],
    );

    testWidgets('offline with cache shows saved stats note', (tester) async {
      final repo = _FakeRepo();
      await tester.runAsync(() => loadStatsOverview(repo, 'test-user'));
      repo.fail = true;
      await tester.pumpWidget(screen(repo));
      await tester.pumpAndSettle();
      expect(find.text('Showing saved stats'), findsOneWidget);
      expect(find.text('40'), findsWidgets);
    });

    testWidgets('failure without cache shows error and Retry recovers', (
      tester,
    ) async {
      final repo = _FakeRepo(fail: true);
      await tester.pumpWidget(screen(repo));
      await tester.pumpAndSettle();
      expect(
        find.text('Failed to load stats. Pull down to retry.'),
        findsOneWidget,
      );
      expect(find.text('Showing saved stats'), findsNothing);

      repo.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('Failed to load stats. Pull down to retry.'),
        findsNothing,
      );
      expect(find.text('Showing saved stats'), findsNothing);
    });

    testWidgets('error state supports pull to refresh', (tester) async {
      final repo = _FakeRepo(fail: true);
      await tester.pumpWidget(screen(repo));
      await tester.pumpAndSettle();
      repo.fail = false;
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(
        find.text('Failed to load stats. Pull down to retry.'),
        findsNothing,
      );
    });
  });
}
