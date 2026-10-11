/// Wrong-attempt delays: failed-unlock counter and wait end time. Saved in
/// settings so restarting the app doesn't reset them.
class LockoutState {
  const LockoutState({this.failedAttempts = 0, this.lockedUntil});

  static const LockoutState initial = LockoutState();

  /// Wrong-attempt delays: free tries before the first wait.
  static const int freeAttempts = 5;

  /// Wrong-attempt delays: 30 s after the 5th failure, then 1 min, 5 min,
  /// and 15 min for every failure after that.
  static const List<Duration> delays = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  final int failedAttempts;
  final DateTime? lockedUntil;

  /// Wrong-attempt delays: the wait that follows the [failures]th failure,
  /// or null when no wait is needed yet.
  static Duration? delayAfter(int failures) {
    if (failures < freeAttempts) return null;
    final step = failures - freeAttempts;
    return delays[step < delays.length ? step : delays.length - 1];
  }

  /// Wrong-attempt delays: record a failed unlock at [now] and start the
  /// wait if one is due.
  LockoutState recordFailure(DateTime now) {
    final failures = failedAttempts + 1;
    final delay = delayAfter(failures);
    return LockoutState(
      failedAttempts: failures,
      lockedUntil: delay == null ? null : now.toUtc().add(delay),
    );
  }

  /// Wrong-attempt delays: a successful unlock clears everything.
  LockoutState recordSuccess() => initial;

  /// Wrong-attempt delays: time left before another try is allowed, or
  /// [Duration.zero]. Capped at the longest delay so moving the device
  /// clock forward and back can't lock someone out for longer.
  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(now.toUtc());
    if (left <= Duration.zero) return Duration.zero;
    return left > delays.last ? delays.last : left;
  }

  bool isLocked(DateTime now) => remaining(now) > Duration.zero;

  /// Wrong-attempt delays: tries left before the first wait (for the
  /// "3 tries left" style message).
  int get attemptsBeforeWait {
    final left = freeAttempts - failedAttempts;
    return left > 0 ? left : 0;
  }

  Map<String, Object?> toJson() => {
        'failedAttempts': failedAttempts,
        'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
      };

  /// Wrong-attempt delays: read from settings. A damaged value keeps the
  /// counter rather than resetting it, so a bad edit can't skip the wait.
  factory LockoutState.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return initial;
    final failures = json['failedAttempts'];
    final until = json['lockedUntil'];
    return LockoutState(
      failedAttempts: failures is int && failures > 0 ? failures : 0,
      lockedUntil: until is String ? DateTime.tryParse(until)?.toUtc() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LockoutState &&
      other.failedAttempts == failedAttempts &&
      other.lockedUntil == lockedUntil;

  @override
  int get hashCode => Object.hash(failedAttempts, lockedUntil);
}
