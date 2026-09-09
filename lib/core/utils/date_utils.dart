abstract final class AppDateUtils {
  static String todayUtc() {
    final now = DateTime.now().toUtc();
    return formatDate(now);
  }

  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime parseDate(String dateStr) {
    return DateTime.parse(dateStr);
  }

  /// Parses `YYYY-MM-DD` as midnight UTC of that day.
  static DateTime parseDateUtc(String dateStr) {
    final parsed = DateTime.parse(dateStr);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  static String tomorrowUtc() {
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    return formatDate(tomorrow);
  }

  /// Returns the day of week (1 = Monday, 7 = Sunday) for difficulty scaling.
  static int dayOfWeek() {
    return DateTime.now().toUtc().weekday;
  }

  /// Weekday (1 = Monday … 7 = Sunday) of an ISO date string, in UTC.
  static int weekdayOf(String date) => parseDateUtc(date).weekday;

  /// Returns Monday 00:00 UTC of the current week.
  static DateTime weekStart() => weekStartOf(DateTime.now().toUtc());

  /// Monday 00:00:00 UTC of the ISO week containing [date].
  ///
  /// [date] is interpreted in UTC (converted with `toUtc()` when it is a
  /// local time). Sunday 23:59:59 UTC maps to the Monday six days earlier;
  /// Monday 00:00:00 UTC maps to itself.
  static DateTime weekStartOf(DateTime date) {
    final utc = date.isUtc ? date : date.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// ISO date string [days] days before [from] (default: now, UTC).
  ///
  /// `dateNDaysAgo(0)` is today, `dateNDaysAgo(1)` is yesterday.
  static String dateNDaysAgo(int days, {DateTime? from}) {
    final base = (from ?? DateTime.now()).toUtc();
    final day = DateTime.utc(base.year, base.month, base.day);
    return formatDate(day.subtract(Duration(days: days)));
  }

  /// The [count] ISO dates ending just before today (today excluded), newest
  /// first: yesterday, the day before, ...
  static List<String> recentDates(int count, {DateTime? from}) {
    return [for (var i = 1; i <= count; i++) dateNDaysAgo(i, from: from)];
  }

  /// Whether [date] (ISO string) is today or tomorrow in UTC.
  static bool isTodayOrTomorrowUtc(String date, {DateTime? now}) {
    final base = (now ?? DateTime.now()).toUtc();
    return date == dateNDaysAgo(0, from: base) ||
        date == dateNDaysAgo(-1, from: base);
  }

  /// Whole days between [date] (ISO) and today (UTC). Positive for past dates.
  static int daysAgo(String date, {DateTime? now}) {
    final base = (now ?? DateTime.now()).toUtc();
    final today = DateTime.utc(base.year, base.month, base.day);
    return today.difference(parseDateUtc(date)).inDays;
  }

  /// Human-friendly date such as `Tue, 9 Sep`.
  static String formatDateHuman(String date) {
    final d = parseDateUtc(date);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  /// Format seconds into mm:ss display.
  static String formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format seconds into a human-readable string.
  static String formatTimeHuman(int totalSeconds) {
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (seconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${seconds}s';
  }
}
