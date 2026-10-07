import 'dart:async';

import 'date_utils.dart';

/// Notices the 00:00 UTC rollover (a new daily puzzle) while the app stays in
/// the foreground, and on demand (e.g. on resume).
///
/// [start] arms a one-shot timer for the next 00:00:01 UTC that calls
/// [check] and re-arms itself. Timers can be suspended while the app is in
/// the background, so call [check] and [start] again on resume.
///
/// [onSettled], if given, runs once at [settleAfter] past 00:00 UTC after a
/// day change noticed before then: the server's nightly streak jobs (freeze
/// at 00:05, stale streaks at 00:10 UTC) have run by that time.
class UtcDayRollover {
  UtcDayRollover({
    required this.onNewDay,
    this.onSettled,
    this.settleAfter = const Duration(minutes: 11),
  }) : _lastKnownDate = AppDateUtils.todayUtc();

  /// Called with the new UTC date (`YYYY-MM-DD`) once per day change.
  final void Function(String today) onNewDay;

  /// Called once the server's post-midnight jobs should have finished.
  final void Function()? onSettled;

  /// Offset from 00:00 UTC at which [onSettled] runs.
  final Duration settleAfter;

  String _lastKnownDate;
  Timer? _timer;
  Timer? _settleTimer;

  /// (Re-)arms the timer for the next rollover.
  void start() {
    _timer?.cancel();
    _timer = Timer(AppDateUtils.untilNextRollover(), () {
      check();
      start();
    });
  }

  /// Calls [onNewDay] if the UTC date changed since the last check. Returns
  /// whether it did.
  bool check() {
    final today = AppDateUtils.todayUtc();
    if (today == _lastKnownDate) return false;
    _lastKnownDate = today;
    onNewDay(today);
    _armSettle();
    return true;
  }

  void _armSettle() {
    final settled = onSettled;
    if (settled == null) return;
    final now = AppDateUtils.nowUtc();
    final at = DateTime.utc(now.year, now.month, now.day).add(settleAfter);
    if (!at.isAfter(now)) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(at.difference(now), settled);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
  }
}
