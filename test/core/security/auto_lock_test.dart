import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/security/auto_lock.dart';

// Auto-lock tests: idle time and the "never" choice.
void main() {
  final start = DateTime.utc(2026, 10, 12, 9);

  test('locks once idle for the chosen minutes', () {
    final t = IdleTracker(start);
    expect(t.isDue(start.add(const Duration(minutes: 4, seconds: 59)), 5),
        isFalse);
    expect(t.isDue(start.add(const Duration(minutes: 5)), 5), isTrue);
  });

  test('activity restarts the idle time', () {
    final t = IdleTracker(start);
    t.touch(start.add(const Duration(minutes: 4)));
    expect(t.isDue(start.add(const Duration(minutes: 6)), 5), isFalse);
    expect(t.isDue(start.add(const Duration(minutes: 9)), 5), isTrue);
  });

  test('0 minutes means never', () {
    final t = IdleTracker(start);
    expect(t.isDue(start.add(const Duration(days: 3)), 0), isFalse);
  });

  test('a clock moved backwards counts as no idle time', () {
    final t = IdleTracker(start);
    final earlier = start.subtract(const Duration(hours: 1));
    expect(t.idleFor(earlier), Duration.zero);
    expect(t.isDue(earlier, 1), isFalse);
  });
}
