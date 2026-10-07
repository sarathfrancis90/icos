import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/auth_session_provider.dart';
import 'package:icos/core/services/notification_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/core/utils/date_utils.dart';
import 'package:icos/features/home/presentation/home_screen.dart';
import 'package:icos/features/puzzle/providers/daily_puzzle_provider.dart';
import 'package:icos/features/puzzle/providers/puzzle_result_provider.dart';
import 'package:icos/features/stats/domain/models/streak.dart';
import 'package:icos/features/stats/providers/stats_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/services/notification_service_test.dart'
    show FakeNotificationBackend;
import '../../../helpers/storage_test_helpers.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late FakeNotificationBackend backend;

  setUp(() {
    backend = FakeNotificationBackend();
    NotificationService.backendOverride = backend;
    NotificationService.locationOverride = tz.UTC;
    NotificationService.clockOverride = () => DateTime.utc(2026, 1, 15, 6);
  });
  tearDown(() {
    NotificationService.backendOverride = null;
    NotificationService.locationOverride = null;
    NotificationService.clockOverride = null;
  });

  Future<void> loadHome(
    WidgetTester tester, {
    required bool remindersOn,
  }) async {
    SharedPreferences.setMockInitialValues({
      'notif_daily_enabled': remindersOn,
    });
    await tester.pumpWidget(
      buildTestWidget(
        const HomeScreen(),
        overrides: [
          dailyPuzzleProvider.overrideWith((ref) async => testPuzzle),
          todayResultProvider.overrideWith((ref) async => null),
          streakProvider.overrideWith(
            (ref) async => Streak(
              userId: 'u',
              currentStreak: 7,
              longestStreak: 7,
              freezeCount: 1,
              lastSolveDate: AppDateUtils.todayUtc(),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reminders off: Home schedules nothing and cancels the pending '
      'streak reminder', (tester) async {
    await loadHome(tester, remindersOn: false);
    expect(backend.scheduled, isEmpty);
    expect(backend.cancelled, contains(NotificationService.streakReminderId));
  });

  testWidgets('reminders on: unsolved Home with a streak arms the reminder', (
    tester,
  ) async {
    await loadHome(tester, remindersOn: true);
    expect(backend.scheduled, hasLength(1));
    expect(
      backend.scheduled.single['id'],
      NotificationService.streakReminderId,
    );
    expect(
      backend.scheduled.single['body'],
      "Today's puzzle closes in 4 hours.",
    );
  });

  testWidgets('streak unreachable offline: uses the saved stats streak',
      (tester) async {
    await tester.runAsync(() async {
      await initTestStorage(userId: 'u1');
      await StorageService.saveStatsCache('overview', {
        'currentStreak': 9,
        'longestStreak': 9,
        'totalSolved': 20,
        'averageTimeSeconds': 60,
        'freezeCount': 1,
        'lastFreezeUsedAt': null,
        'lastSolveDate': AppDateUtils.dateNDaysAgo(1),
      }, userId: 'u1');
    });
    SharedPreferences.setMockInitialValues({'notif_daily_enabled': true});
    await tester.pumpWidget(
      buildTestWidget(
        const HomeScreen(),
        overrides: [
          dailyPuzzleProvider.overrideWith((ref) async => testPuzzle),
          todayResultProvider.overrideWith((ref) async => null),
          streakProvider.overrideWith((ref) async => throw Exception('offline')),
          authSessionProvider.overrideWithValue(
            const FakeAuthSessionInfo(userId: 'u1'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.scheduled, isNotEmpty);
    expect(
      backend.scheduled.every((e) => e['id'] == NotificationService.streakReminderId),
      isTrue,
    );
  });

  testWidgets('a lapsed stored streak does not arm the reminder', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notif_daily_enabled': true});
    await tester.pumpWidget(
      buildTestWidget(
        const HomeScreen(),
        overrides: [
          dailyPuzzleProvider.overrideWith((ref) async => testPuzzle),
          todayResultProvider.overrideWith((ref) async => null),
          streakProvider.overrideWith(
            (ref) async => Streak(
              userId: 'u',
              currentStreak: 7,
              longestStreak: 7,
              freezeCount: 1,
              lastSolveDate: AppDateUtils.dateNDaysAgo(3),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.scheduled, isEmpty);
    expect(backend.cancelled, contains(NotificationService.streakReminderId));
  });
}
