import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric unlock: how a fingerprint or face check ended.
enum BiometricResult {
  /// The person was recognised.
  success,

  /// A scan didn't match (counts toward the 5-failure limit).
  failed,

  /// The person closed the prompt; not counted as a failure.
  cancelled,

  /// The phone itself locked biometrics after too many failed scans.
  lockedOut,

  /// No fingerprint or face is set up, or the hardware is busy or missing.
  unavailable,
}

/// Biometric unlock (Android, iOS): the fingerprint / face check from
/// `local_auth` plus the secure storage slot (Keychain / Keystore) that
/// holds the vault key while biometric unlock is on. Tests swap in a fake.
abstract class Biometrics {
  /// Biometric unlock: true if the phone has a fingerprint or face set up.
  Future<bool> isAvailable();

  /// Biometric unlock: shows the system fingerprint / face prompt.
  Future<BiometricResult> authenticate(String reason);

  /// Biometric unlock: the stored record (vault key + last PIN time), or
  /// null. Only read after [authenticate] succeeds.
  Future<String?> readRecord();

  /// Biometric unlock: whether a record is stored, without reading it
  /// (decides if the unlock screen offers a scan).
  Future<bool> hasRecord();

  Future<void> writeRecord(String record);

  Future<void> deleteRecord();
}

/// Biometric unlock on desktop: not offered (SPEC: mobile only).
class NoBiometrics implements Biometrics {
  const NoBiometrics();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BiometricResult> authenticate(String reason) async =>
      BiometricResult.unavailable;

  @override
  Future<String?> readRecord() async => null;

  @override
  Future<bool> hasRecord() async => false;

  @override
  Future<void> writeRecord(String record) async {}

  @override
  Future<void> deleteRecord() async {}
}

/// Biometric unlock on Android and iOS, using `local_auth` and
/// `flutter_secure_storage`.
class DeviceBiometrics implements Biometrics {
  DeviceBiometrics();

  final _auth = LocalAuthentication();

  // Biometric unlock: the vault key lives only on this device. On iOS it
  // never leaves the Keychain for iCloud or backups, and needs the phone
  // to have been unlocked since it started.
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  static const _recordKey = 'vaultify.biometric.v1';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      // Biometrics only: the phone's own PIN or pattern must not open the
      // vault, since that is a different secret.
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress =>
          BiometricResult.cancelled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricResult.lockedOut,
        _ => BiometricResult.unavailable,
      };
    } on PlatformException {
      return BiometricResult.unavailable;
    }
  }

  @override
  Future<String?> readRecord() async {
    try {
      return await _storage.read(key: _recordKey);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> hasRecord() async {
    try {
      return await _storage.containsKey(key: _recordKey);
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> writeRecord(String record) =>
      _storage.write(key: _recordKey, value: record);

  @override
  Future<void> deleteRecord() async {
    try {
      await _storage.delete(key: _recordKey);
    } on PlatformException {
      // Nothing stored or storage unavailable: nothing to remove.
    }
  }
}
