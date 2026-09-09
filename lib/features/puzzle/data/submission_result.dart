/// Lifecycle of a completed solve as seen by the client.
enum SubmissionStatus {
  /// Queued locally, not yet acknowledged by the server.
  pending,

  /// Server accepted with a valid HMAC signature.
  verified,

  /// Server accepted without a (valid) signature.
  unverified,

  /// Server permanently rejected the submission (validation error).
  rejected,

  /// Never sent (practice or archive date outside the server window).
  localOnly;

  static SubmissionStatus parse(String? value) {
    for (final s in SubmissionStatus.values) {
      if (s.name == value) return s;
    }
    return SubmissionStatus.pending;
  }
}

/// Streak values returned by `submit-score`.
class StreakSnapshot {
  const StreakSnapshot({
    required this.currentStreak,
    required this.longestStreak,
    required this.freezeCount,
    this.lastSolveDate,
  });

  factory StreakSnapshot.fromJson(Map<String, dynamic> json) => StreakSnapshot(
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
        freezeCount: (json['freeze_count'] as num?)?.toInt() ?? 0,
        lastSolveDate: json['last_solve_date'] as String?,
      );

  final int currentStreak;
  final int longestStreak;
  final int freezeCount;
  final String? lastSolveDate;

  Map<String, dynamic> toJson() => {
        'current_streak': currentStreak,
        'longest_streak': longestStreak,
        'freeze_count': freezeCount,
        'last_solve_date': lastSolveDate,
      };
}

/// A completed solve for one date, persisted locally so Home / the puzzle
/// screen can show it without a network round-trip.
class SubmissionResult {
  const SubmissionResult({
    required this.date,
    required this.status,
    required this.timeSeconds,
    required this.hintsUsed,
    required this.undosUsed,
    required this.path,
    required this.completedAt,
    this.isArchive = false,
    this.streak,
    this.rankHint,
    this.reason,
  });

  factory SubmissionResult.fromJson(Map<String, dynamic> json) {
    final rawPath = (json['path'] as List<dynamic>?) ?? const [];
    return SubmissionResult(
      date: json['date'] as String,
      status: SubmissionStatus.parse(json['status'] as String?),
      timeSeconds: (json['time_seconds'] as num?)?.toInt() ?? 0,
      hintsUsed: (json['hints_used'] as num?)?.toInt() ?? 0,
      undosUsed: (json['undos_used'] as num?)?.toInt() ?? 0,
      path: [
        for (final cell in rawPath)
          [
            ((cell as List<dynamic>)[0] as num).toInt(),
            (cell[1] as num).toInt(),
          ],
      ],
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isArchive: json['is_archive'] as bool? ?? false,
      streak: json['streak'] is Map<String, dynamic>
          ? StreakSnapshot.fromJson(json['streak'] as Map<String, dynamic>)
          : null,
      rankHint: (json['rank_hint'] as num?)?.toInt(),
      reason: json['reason'] as String?,
    );
  }

  final String date;
  final SubmissionStatus status;
  final int timeSeconds;
  final int hintsUsed;
  final int undosUsed;

  /// `[[row, col], ...]`
  final List<List<int>> path;
  final DateTime completedAt;
  final bool isArchive;
  final StreakSnapshot? streak;
  final int? rankHint;

  /// Server reason / error code for [SubmissionStatus.rejected].
  final String? reason;

  bool get isRejected => status == SubmissionStatus.rejected;
  bool get isPending => status == SubmissionStatus.pending;
  bool get isAccepted =>
      status == SubmissionStatus.verified ||
      status == SubmissionStatus.unverified;

  SubmissionResult copyWith({
    SubmissionStatus? status,
    bool? isArchive,
    StreakSnapshot? streak,
    int? rankHint,
    String? reason,
  }) =>
      SubmissionResult(
        date: date,
        status: status ?? this.status,
        timeSeconds: timeSeconds,
        hintsUsed: hintsUsed,
        undosUsed: undosUsed,
        path: path,
        completedAt: completedAt,
        isArchive: isArchive ?? this.isArchive,
        streak: streak ?? this.streak,
        rankHint: rankHint ?? this.rankHint,
        reason: reason ?? this.reason,
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'status': status.name,
        'time_seconds': timeSeconds,
        'hints_used': hintsUsed,
        'undos_used': undosUsed,
        'path': path,
        'completed_at': completedAt.toUtc().toIso8601String(),
        'is_archive': isArchive,
        if (streak != null) 'streak': streak!.toJson(),
        if (rankHint != null) 'rank_hint': rankHint,
        if (reason != null) 'reason': reason,
      };
}
