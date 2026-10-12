import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/generator/generator.dart';
import 'package:vaultify/core/security/lockout.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/vault_file.dart';

// Settings tests: defaults, JSON round trip, invalid values.
void main() {
  test('defaults match SPEC', () {
    const s = Settings();
    expect(s.unlockType, isNull);
    expect(s.autoLockMinutes, 5);
    expect(s.backgroundLockSeconds, 0);
    expect(s.clipboardClearSeconds, 30);
    expect(s.sortOrder, SortOrder.nameAsc);
    expect(s.lockout, LockoutState.initial);
    expect(s.biometricEnabled, isFalse);
    expect(s.biometricOffered, isFalse);
    expect(s.biometricFailures, 0);
  });

  test('biometric fields round-trip; bad values fall back', () {
    final s = const Settings().copyWith(
      biometricEnabled: true,
      biometricOffered: true,
      biometricFailures: 3,
    );
    expect(Settings.fromJson(s.toJson()).toJson(), s.toJson());
    final bad = Settings.fromJson({
      'biometricEnabled': 'yes',
      'biometricOffered': 1,
      'biometricFailures': -2,
    });
    expect(bad.biometricEnabled, isFalse);
    expect(bad.biometricOffered, isFalse);
    expect(bad.biometricFailures, 0);
  });

  test('round-trips through JSON', () {
    final s = const Settings().copyWith(
      unlockType: UnlockType.password,
      autoLockMinutes: 15,
      backgroundLockSeconds: 60,
      clipboardClearSeconds: 0,
      generator: const GeneratorOptions(length: 24, symbols: false),
      lockout: LockoutState(
          failedAttempts: 5, lockedUntil: DateTime.utc(2026, 10, 11)),
      sortOrder: SortOrder.newestFirst,
    );
    final back = Settings.fromJson(s.toJson());
    expect(back.toJson(), s.toJson());
  });

  test('values outside the allowed choices fall back to defaults', () {
    final s = Settings.fromJson({
      'unlockType': 'face',
      'autoLockMinutes': 7,
      'clipboardClearSeconds': '30',
      'sortOrder': 'random',
    });
    expect(s.toJson(), const Settings().toJson());
    expect(Settings.fromJson([1, 2]).toJson(), const Settings().toJson());
  });
}
