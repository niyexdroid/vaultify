import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/security/biometric_policy.dart';

// Biometric unlock rules: stored record format, 5 failed scans, 7 days
// since the PIN was typed, and a clock set back.
void main() {
  final pinAt = DateTime.utc(2026, 10, 12, 9);
  final key = List<int>.generate(32, (i) => i);
  BiometricRecord record() => BiometricRecord(key: key, secretEnteredAt: pinAt);

  group('record', () {
    test('round-trips through its stored text', () {
      final back = BiometricRecord.decode(record().encode())!;
      expect(back.key, key);
      expect(back.secretEnteredAt, pinAt);
    });

    test('missing or damaged text gives null', () {
      expect(BiometricRecord.decode(null), isNull);
      expect(BiometricRecord.decode('not json'), isNull);
      expect(BiometricRecord.decode('{"v":2}'), isNull);
      expect(BiometricRecord.decode('{"v":1,"key":"AAAA","secretEnteredAt":'
          '"2026-10-12T09:00:00.000Z"}'), isNull); // key too short
      expect(BiometricRecord.decode('{"v":1,"key":"%%","secretEnteredAt":"x"}'),
          isNull);
    });
  });

  group('allows', () {
    bool allows({int failures = 0, required DateTime now, bool hasRecord = true}) =>
        BiometricPolicy.allows(
          record: hasRecord ? record() : null,
          failures: failures,
          now: now,
        );

    test('within 7 days and under 5 failures', () {
      expect(allows(now: pinAt), isTrue);
      expect(allows(now: pinAt.add(const Duration(days: 6, hours: 23))),
          isTrue);
      expect(allows(failures: 4, now: pinAt), isTrue);
    });

    test('PIN required after 5 failed scans', () {
      expect(allows(failures: 5, now: pinAt), isFalse);
    });

    test('PIN required after 7 days', () {
      expect(allows(now: pinAt.add(const Duration(days: 7))), isFalse);
    });

    test('PIN required with no stored key (e.g. after changing the PIN)', () {
      expect(allows(now: pinAt, hasRecord: false), isFalse);
    });

    test('a clock set back before the last PIN entry needs the PIN', () {
      expect(allows(now: pinAt.subtract(const Duration(minutes: 1))), isFalse);
    });
  });
}
