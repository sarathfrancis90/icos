import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FakeNotificationBackend implements NotificationBackend {
  bool permission = true;
  final scheduled = <Map<String, Object?>>[];
  final cancelled = <int>[];

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
    required AndroidNotificationDetails android,
    required bool repeatsDaily,
    required String payload,
  }) async {
    scheduled.add({'id': id, 'title': title, 'body': body, 'at': at});
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late FakeNotificationBackend backend;
  final now = DateTime.utc(2026, 1, 15, 6);

  Future<void> setEnabled(bool on) async {
    SharedPreferences.setMockInitialValues({'notif_daily_enabled': on});
  }

  setUp(() {
    backend = FakeNotificationBackend();
    NotificationService.backendOverride = backend;
    NotificationService.locationOverride = tz.getLocation('America/New_York');
  });
  tearDown(() {
    NotificationService.backendOverride = null;
    NotificationService.locationOverride = null;
  });

  group('refreshStreakReminder', () {
    test(
      'unsolved + streak + enabled schedules 4h before UTC midnight',
      () async {
        await setEnabled(true);
        await NotificationService.refreshStreakReminder(
          solvedToday: false,
          currentStreak: 5,
          nowUtc: now,
        );
        expect(backend.scheduled, hasLength(1));
        final s = backend.scheduled.single;
        expect(s['id'], NotificationService.streakReminderId);
        expect(s['title'], 'Keep your streak alive');
        expect(s['body'], "Today's puzzle closes in 4 hours.");
        final at = s['at']! as tz.TZDateTime;
        expect(at.toUtc(), DateTime.utc(2026, 1, 15, 20));
        expect(at.hour, 15); // New York, UTC-5
      },
    );

    test(
      'setting off schedules nothing and cancels a pending reminder',
      () async {
        await setEnabled(false);
        await NotificationService.refreshStreakReminder(
          solvedToday: false,
          currentStreak: 5,
          nowUtc: now,
        );
        expect(backend.scheduled, isEmpty);
        expect(
          backend.cancelled,
          contains(NotificationService.streakReminderId),
        );
      },
    );

    test('OS permission off schedules nothing and cancels', () async {
      await setEnabled(true);
      backend.permission = false;
      await NotificationService.refreshStreakReminder(
        solvedToday: false,
        currentStreak: 5,
        nowUtc: now,
      );
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, contains(NotificationService.streakReminderId));
    });

    test('solved today cancels', () async {
      await setEnabled(true);
      await NotificationService.refreshStreakReminder(
        solvedToday: true,
        currentStreak: 5,
        nowUtc: now,
      );
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, contains(NotificationService.streakReminderId));
    });

    test('no streak cancels; unknown streak schedules nothing', () async {
      await setEnabled(true);
      await NotificationService.refreshStreakReminder(
        solvedToday: false,
        currentStreak: 0,
        nowUtc: now,
      );
      expect(backend.cancelled, contains(NotificationService.streakReminderId));
      backend.cancelled.clear();
      await NotificationService.refreshStreakReminder(
        solvedToday: false,
        currentStreak: null,
        nowUtc: now,
      );
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, isEmpty);
    });

    test('fire time already past cancels', () async {
      await setEnabled(true);
      await NotificationService.refreshStreakReminder(
        solvedToday: false,
        currentStreak: 5,
        nowUtc: DateTime.utc(2026, 1, 15, 21),
      );
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, contains(NotificationService.streakReminderId));
    });
  });

  group('daily reminder gate', () {
    test('refreshDailyReminder cancels when the setting is off', () async {
      await setEnabled(false);
      await NotificationService.refreshDailyReminder();
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, contains(NotificationService.dailyReminderId));
    });

    test(
      'refreshDailyReminder cancels when the OS permission is off',
      () async {
        await setEnabled(true);
        backend.permission = false;
        await NotificationService.refreshDailyReminder();
        expect(backend.scheduled, isEmpty);
        expect(
          backend.cancelled,
          contains(NotificationService.dailyReminderId),
        );
      },
    );

    test('refreshDailyReminder schedules when allowed', () async {
      await setEnabled(true);
      await NotificationService.refreshDailyReminder();
      expect(
        backend.scheduled.single['id'],
        NotificationService.dailyReminderId,
      );
    });

    test('scheduleDailyReminder without OS permission stays off', () async {
      await setEnabled(false);
      backend.permission = false;
      await NotificationService.scheduleDailyReminder(
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(backend.scheduled, isEmpty);
      expect(await NotificationService.isEnabled(), isFalse);
    });

    test('scheduleDailyReminder turns the setting on and schedules', () async {
      await setEnabled(false);
      await NotificationService.scheduleDailyReminder(
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(await NotificationService.isEnabled(), isTrue);
      expect(backend.scheduled, hasLength(1));
    });
  });

  group('cancelPendingIfNotAllowed (app resume)', () {
    test('OS permission revoked cancels both pending reminders', () async {
      await setEnabled(true);
      backend.permission = false;
      await NotificationService.cancelPendingIfNotAllowed();
      expect(
        backend.cancelled,
        containsAll([
          NotificationService.dailyReminderId,
          NotificationService.streakReminderId,
        ]),
      );
    });

    test('allowed leaves pending reminders alone', () async {
      await setEnabled(true);
      await NotificationService.cancelPendingIfNotAllowed();
      expect(backend.cancelled, isEmpty);
    });
  });
}
