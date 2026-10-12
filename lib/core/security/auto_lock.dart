/// Auto-lock: remembers when the user last did something (tap, click, key)
/// and says when the idle time from Options has run out.
class IdleTracker {
  IdleTracker(DateTime now) : _lastActivity = now;

  DateTime _lastActivity;

  /// Auto-lock: any input counts as activity and restarts the idle time.
  void touch(DateTime now) => _lastActivity = now;

  /// Auto-lock: how long since the last activity. A clock moved backwards
  /// counts as no idle time rather than a negative one.
  Duration idleFor(DateTime now) {
    final idle = now.difference(_lastActivity);
    return idle.isNegative ? Duration.zero : idle;
  }

  /// Auto-lock: true once idle for [minutes]; 0 means "never".
  bool isDue(DateTime now, int minutes) =>
      minutes > 0 && idleFor(now) >= Duration(minutes: minutes);
}
