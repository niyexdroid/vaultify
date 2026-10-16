import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/generator/generator.dart';
import 'package:vaultify/core/security/lockout.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/vault_file.dart';

// Settings tests: defaults, JSON round trip, invalid values.
void main() {
  windowBoundsTests();
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

// Window size memory tests: saved bounds survive a round trip, and damaged
// or absurd numbers are ignored rather than opening an unusable window.
void windowBoundsTests() {
  group('window size memory', () {
    test('round trips through JSON with a position', () {
      const bounds = WindowBounds(width: 900, height: 700, x: 120, y: -40);
      final read = Settings.fromJson(const Settings(windowBounds: bounds).toJson());
      expect(read.windowBounds, bounds);
    });

    test('is absent until the window has been moved', () {
      const settings = Settings();
      expect(settings.toJson().containsKey('windowBounds'), isFalse);
      expect(Settings.fromJson(settings.toJson()).windowBounds, isNull);
    });

    test('keeps a size with no saved position', () {
      const bounds = WindowBounds(width: 900, height: 700);
      final read =
          Settings.fromJson(const Settings(windowBounds: bounds).toJson());
      expect(read.windowBounds, bounds);
      expect(read.windowBounds!.x, isNull);
    });

    test('ignores a size that is missing, tiny, huge or not a number', () {
      for (final bad in <Object?>[
        null,
        'nonsense',
        {'height': 700.0},
        {'width': 10.0, 'height': 700.0},
        {'width': 900.0, 'height': 5.0},
        {'width': 999999.0, 'height': 700.0},
        {'width': 'wide', 'height': 700.0},
        {'width': double.nan, 'height': 700.0},
        {'width': double.infinity, 'height': 700.0},
      ]) {
        expect(WindowBounds.fromJson(bad), isNull, reason: 'for $bad');
      }
    });

    test('drops an absurd position but keeps the size', () {
      final bounds = WindowBounds.fromJson(
          {'width': 900.0, 'height': 700.0, 'x': 1e9, 'y': 20.0});
      expect(bounds, isNotNull);
      expect(bounds!.width, 900);
      expect(bounds.x, isNull);
      expect(bounds.y, 20);
    });

    test('reads whole numbers from a hand-edited settings file', () {
      final bounds =
          WindowBounds.fromJson({'width': 900, 'height': 700, 'x': 0, 'y': 0});
      expect(bounds, const WindowBounds(width: 900, height: 700, x: 0, y: 0));
    });
  });
}
