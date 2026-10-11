import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/security/lockout.dart';

// Wrong-attempt delays tests: the 5-free-tries then 30s/1m/5m/15m ladder.
void main() {
  final t0 = DateTime.utc(2026, 10, 11, 12);

  LockoutState failTimes(int n) {
    var s = LockoutState.initial;
    for (var i = 0; i < n; i++) {
      s = s.recordFailure(t0);
    }
    return s;
  }

  test('the first 4 failures need no wait', () {
    final s = failTimes(4);
    expect(s.failedAttempts, 4);
    expect(s.isLocked(t0), isFalse);
    expect(s.attemptsBeforeWait, 1);
  });

  test('5 failures → 30 s, then 1 min, 5 min, 15 min, 15 min', () {
    expect(failTimes(5).remaining(t0), const Duration(seconds: 30));
    expect(failTimes(6).remaining(t0), const Duration(minutes: 1));
    expect(failTimes(7).remaining(t0), const Duration(minutes: 5));
    expect(failTimes(8).remaining(t0), const Duration(minutes: 15));
    expect(failTimes(12).remaining(t0), const Duration(minutes: 15));
  });

  test('the wait counts down and ends', () {
    final s = failTimes(5);
    expect(s.remaining(t0.add(const Duration(seconds: 20))),
        const Duration(seconds: 10));
    expect(s.isLocked(t0.add(const Duration(seconds: 30))), isFalse);
  });

  test('success resets everything', () {
    expect(failTimes(6).recordSuccess(), LockoutState.initial);
  });

  test('moving the clock back cannot stretch the wait past 15 min', () {
    final s = failTimes(5);
    expect(s.remaining(t0.subtract(const Duration(days: 1))),
        const Duration(minutes: 15));
  });

  test('survives a save and reload (restart)', () {
    final s = failTimes(5);
    final back = LockoutState.fromJson(s.toJson());
    expect(back, s);
    expect(back.remaining(t0), const Duration(seconds: 30));
  });

  test('damaged values fall back safely', () {
    expect(LockoutState.fromJson(null), LockoutState.initial);
    final s = LockoutState.fromJson({'failedAttempts': -3, 'lockedUntil': 5});
    expect(s.failedAttempts, 0);
    expect(s.lockedUntil, isNull);
  });
}
