import 'package:timezone/timezone.dart' as tz;

/// How long before the 00:00 UTC rollover the streak reminder should fire.
const Duration streakReminderLead = Duration(hours: 4);

/// Fallback fire time (local) used when the ideal time is in quiet hours.
const int _fallbackHour = 21;
const int _fallbackMinute = 30;

/// The next 00:00 UTC strictly after [nowUtc]: the moment today's (UTC)
/// puzzle closes and an unplayed day breaks the streak.
DateTime streakDeadlineUtc(DateTime nowUtc) {
  final n = nowUtc.toUtc();
  return DateTime.utc(n.year, n.month, n.day).add(const Duration(days: 1));
}

/// Whole hours (at least 1) left from [fireAt] to [deadlineUtc], rounded
/// down so the notification never overstates the time left.
int streakReminderHoursLeft(DateTime fireAt, DateTime deadlineUtc) {
  final hours = deadlineUtc.difference(fireAt.toUtc()).inHours;
  return hours < 1 ? 1 : hours;
}

/// Notification body for the streak reminder.
String streakReminderBody(int hours) =>
    "Today's puzzle closes in $hours ${hours == 1 ? 'hour' : 'hours'}.";

/// When to remind the player, in the device's local zone [location], or
/// `null` when no reminder should be scheduled for this UTC day.
///
/// The target is [streakReminderLead] before the next 00:00 UTC. If that falls
/// in quiet hours (22:00-08:00 local) it moves to 21:30 local on the evening
/// before the deadline. A time that is not in the future yields `null`.
tz.TZDateTime? streakReminderFireTime({
  required DateTime nowUtc,
  required tz.Location location,
}) {
  final now = nowUtc.toUtc();
  final deadline = streakDeadlineUtc(now);
  var fire = tz.TZDateTime.from(
    deadline.subtract(streakReminderLead),
    location,
  );

  final minuteOfDay = fire.hour * 60 + fire.minute;
  final quiet = minuteOfDay >= 22 * 60 || minuteOfDay < 8 * 60;
  if (quiet) {
    final deadlineLocal = tz.TZDateTime.from(deadline, location);
    fire = tz.TZDateTime(
      location,
      deadlineLocal.year,
      deadlineLocal.month,
      deadlineLocal.day - 1,
      _fallbackHour,
      _fallbackMinute,
    );
    if (!fire.toUtc().isBefore(deadline)) return null;
  }
  return fire.toUtc().isAfter(now) ? fire : null;
}
