import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/cipher.dart';
import '../core/security/biometric_policy.dart';
import '../core/security/lockout.dart';
import '../core/settings/settings.dart';
import '../core/vault/vault_file.dart';
import '../platform/biometrics.dart';
import 'providers.dart';

/// Lock gate: which screen the app shows.
enum Phase {
  /// First launch: no vault yet, show setup.
  setup,

  /// Vault exists and is locked, show unlock.
  locked,

  /// Vault is open.
  unlocked,

  /// Vault file can't be read; offer restore from `.bak`.
  damaged,
}

/// Unlock result, so the unlock screen can say "Wrong PIN".
enum UnlockOutcome { success, wrong, waiting, damaged }

/// Biometric unlock result, so the unlock screen can say what happened.
enum BiometricUnlock {
  success,

  /// Scan didn't match; more tries are allowed.
  failed,

  /// Prompt closed; nothing counted.
  cancelled,

  /// PIN or password needed: 5 failed scans, 7 days passed, PIN changed,
  /// or biometrics unavailable.
  secretRequired,

  /// A wrong-attempt wait is running.
  waiting,

  /// Vault file can't be read.
  damaged,
}

/// Session: the lock gate's view of the vault plus the settings it needs.
class Session {
  const Session({
    required this.phase,
    required this.settings,
    this.unlockType,
    this.hasBackup = false,
    this.offerBiometrics = false,
  });

  final Phase phase;
  final Settings settings;

  /// Which secret the vault uses (null during setup or when damaged).
  final UnlockType? unlockType;

  /// Damaged vault: whether `vault.vfy.bak` exists to restore from.
  final bool hasBackup;

  /// Biometric unlock: ask "Unlock with fingerprint or face?" once, after
  /// the first successful PIN entry on a phone that supports it.
  final bool offerBiometrics;

  LockoutState get lockout => settings.lockout;

  Session copyWith({
    Phase? phase,
    Settings? settings,
    UnlockType? unlockType,
    bool? hasBackup,
    bool? offerBiometrics,
  }) =>
      Session(
        phase: phase ?? this.phase,
        settings: settings ?? this.settings,
        unlockType: unlockType ?? this.unlockType,
        hasBackup: hasBackup ?? this.hasBackup,
        offerBiometrics: offerBiometrics ?? this.offerBiometrics,
      );
}

/// Session controller: setup, unlock, lock and restore. Wrong-attempt waits
/// are enforced here, not only in the unlock screen.
final sessionProvider =
    AsyncNotifierProvider<SessionController, Session>(SessionController.new);

class SessionController extends AsyncNotifier<Session> {
  // Biometric unlock: when the PIN or password was last typed this session
  // (the start of the 7-day window for a newly stored key).
  DateTime? _secretEnteredAt;

  // Lock gate: on start, pick setup, unlock or damaged from what's on disk.
  @override
  Future<Session> build() async {
    final repo = ref.read(vaultRepositoryProvider);
    final settings = await ref.read(settingsStoreProvider).load();
    final hasBackup = await repo.backupExists();
    if (!await repo.exists()) {
      // Vault missing but a backup is there: offer it rather than starting
      // over and overwriting the backup on the first save.
      return Session(
        phase: hasBackup ? Phase.damaged : Phase.setup,
        settings: settings,
        hasBackup: hasBackup,
      );
    }
    try {
      return Session(
        phase: Phase.locked,
        settings: settings,
        unlockType: await repo.readUnlockType(),
        hasBackup: hasBackup,
      );
    } on VaultFormatException {
      return Session(
        phase: Phase.damaged,
        settings: settings,
        hasBackup: hasBackup,
      );
    }
  }

  Session get _current => state.requireValue;

  Biometrics get _biometrics => ref.read(biometricsProvider);

  /// First-launch setup: creates the vault with [secret] and opens it.
  Future<void> create(String secret, UnlockType type) async {
    await ref.read(vaultRepositoryProvider).create(secret, type);
    _secretEnteredAt = ref.read(clockProvider)();
    final settings = _current.settings.copyWith(
      unlockType: type,
      lockout: LockoutState.initial,
    );
    await ref.read(settingsStoreProvider).save(settings);
    state = AsyncData(Session(
      phase: Phase.unlocked,
      settings: settings,
      unlockType: type,
      offerBiometrics: await _shouldOfferBiometrics(settings),
    ));
  }

  /// Unlock: tries [secret] unless a wrong-attempt wait is running.
  Future<UnlockOutcome> unlock(String secret) async {
    final now = ref.read(clockProvider)();
    final session = _current;
    if (session.lockout.isLocked(now)) return UnlockOutcome.waiting;

    // Wrong-attempt delays: count the try as failed and save that *before*
    // checking the secret, so killing the app mid-check can't skip a wait.
    // A correct secret then clears the counter.
    final store = ref.read(settingsStoreProvider);
    final failed = session.settings.copyWith(
      lockout: session.lockout.recordFailure(now),
    );
    await store.save(failed);

    try {
      await ref.read(vaultRepositoryProvider).unlock(secret);
    } on DecryptionFailedException {
      state = AsyncData(session.copyWith(settings: failed));
      return UnlockOutcome.wrong;
    } on VaultFormatException {
      // Damaged file isn't a wrong guess: put the counter back.
      await store.save(session.settings);
      state = AsyncData(session.copyWith(phase: Phase.damaged));
      return UnlockOutcome.damaged;
    }

    // Biometric unlock: typing the PIN resets failed scans and restarts
    // the 7 days, so the stored key is refreshed when biometrics are on.
    _secretEnteredAt = now;
    final cleared = session.settings.copyWith(
      lockout: session.lockout.recordSuccess(),
      biometricFailures: 0,
    );
    await store.save(cleared);
    if (cleared.biometricEnabled) await _storeBiometricKey(now);
    state = AsyncData(session.copyWith(
      phase: Phase.unlocked,
      settings: cleared,
      offerBiometrics: await _shouldOfferBiometrics(cleared),
    ));
    return UnlockOutcome.success;
  }

  /// Biometric unlock: whether the unlock screen should offer a scan (on,
  /// fewer than 5 failed scans, a key stored, and the phone supports it).
  Future<bool> biometricsReady() async {
    final s = _current.settings;
    if (!s.biometricEnabled ||
        s.biometricFailures >= BiometricPolicy.maxFailures) {
      return false;
    }
    return await _biometrics.hasRecord() && await _biometrics.isAvailable();
  }

  /// Biometric unlock: fingerprint or face check, then opens the vault with
  /// the stored key. The key is only read after a successful check.
  Future<BiometricUnlock> unlockWithBiometrics(String reason) async {
    final session = _current;
    final now = ref.read(clockProvider)();
    if (session.phase != Phase.locked) return BiometricUnlock.cancelled;
    if (session.lockout.isLocked(now)) return BiometricUnlock.waiting;
    if (!session.settings.biometricEnabled) {
      return BiometricUnlock.secretRequired;
    }

    final result = await _biometrics.authenticate(reason);
    switch (result) {
      case BiometricResult.success:
        break;
      case BiometricResult.cancelled:
        return BiometricUnlock.cancelled;
      case BiometricResult.unavailable:
        return BiometricUnlock.secretRequired;
      case BiometricResult.failed:
      case BiometricResult.lockedOut:
        // Biometric unlock: count failed scans; the phone locking its own
        // sensor counts as reaching the limit.
        final failures = result == BiometricResult.lockedOut
            ? BiometricPolicy.maxFailures
            : session.settings.biometricFailures + 1;
        final settings = session.settings.copyWith(biometricFailures: failures);
        await ref.read(settingsStoreProvider).save(settings);
        state = AsyncData(session.copyWith(settings: settings));
        return failures >= BiometricPolicy.maxFailures
            ? BiometricUnlock.secretRequired
            : BiometricUnlock.failed;
    }

    // Biometric unlock: check the 7-day rule against the stored record
    // itself (settings.json is plain text and could be edited).
    final record = BiometricRecord.decode(await _biometrics.readRecord());
    if (!BiometricPolicy.allows(
      record: record,
      failures: session.settings.biometricFailures,
      now: now,
    )) {
      await _biometrics.deleteRecord();
      return BiometricUnlock.secretRequired;
    }

    try {
      await ref.read(vaultRepositoryProvider).unlockWithKey(record!.key);
    } on DecryptionFailedException {
      // Stored key no longer fits (PIN changed elsewhere): drop it.
      await _biometrics.deleteRecord();
      return BiometricUnlock.secretRequired;
    } on VaultFormatException {
      state = AsyncData(session.copyWith(phase: Phase.damaged));
      return BiometricUnlock.damaged;
    }

    _secretEnteredAt = record.secretEnteredAt;
    var settings = session.settings;
    if (settings.biometricFailures != 0) {
      settings = settings.copyWith(biometricFailures: 0);
      await ref.read(settingsStoreProvider).save(settings);
    }
    state = AsyncData(session.copyWith(
      phase: Phase.unlocked,
      settings: settings,
    ));
    return BiometricUnlock.success;
  }

  /// Biometric unlock, Options switch on: asks for a scan first, then keeps
  /// the vault key in secure storage.
  Future<BiometricResult> enableBiometrics(String reason) async {
    final result = await _biometrics.authenticate(reason);
    if (result != BiometricResult.success) return result;
    await _storeBiometricKey(
        _secretEnteredAt ?? ref.read(clockProvider)());
    await updateSettings((s) => s.copyWith(
          biometricEnabled: true,
          biometricOffered: true,
          biometricFailures: 0,
        ));
    return BiometricResult.success;
  }

  /// Biometric unlock, Options switch off: removes the stored key.
  Future<void> disableBiometrics() async {
    await _biometrics.deleteRecord();
    await updateSettings((s) => s.copyWith(
          biometricEnabled: false,
          biometricOffered: true,
        ));
  }

  /// Biometric unlock offer: "Not now" just remembers it was asked; "Turn
  /// on" also asks for a scan. Returns the scan result when turning on.
  Future<BiometricResult?> answerBiometricOffer({
    required bool turnOn,
    required String reason,
  }) async {
    state = AsyncData(_current.copyWith(offerBiometrics: false));
    if (turnOn) {
      final result = await enableBiometrics(reason);
      if (result == BiometricResult.success) return result;
      await updateSettings((s) => s.copyWith(biometricOffered: true));
      return result;
    }
    await updateSettings((s) => s.copyWith(biometricOffered: true));
    return null;
  }

  // Biometric unlock offer: only on a phone with a fingerprint or face set
  // up, and only once.
  Future<bool> _shouldOfferBiometrics(Settings s) async {
    if (s.biometricOffered || s.biometricEnabled) return false;
    try {
      return await _biometrics.isAvailable();
    } catch (_) {
      return false;
    }
  }

  // Biometric unlock: stores the open vault's key with [secretEnteredAt].
  // A failure only means biometrics won't work until the next PIN entry.
  Future<void> _storeBiometricKey(DateTime secretEnteredAt) async {
    try {
      final key = await ref.read(vaultRepositoryProvider).exportKey();
      await _biometrics.writeRecord(
        BiometricRecord(key: key, secretEnteredAt: secretEnteredAt).encode(),
      );
    } catch (_) {
      await _biometrics.deleteRecord();
    }
  }

  /// Lock: drops the key and entries from memory and shows unlock.
  void lock() {
    ref.read(vaultRepositoryProvider).lock();
    final session = state.value;
    if (session != null && session.phase == Phase.unlocked) {
      state = AsyncData(
          session.copyWith(phase: Phase.locked, offerBiometrics: false));
    }
  }

  /// Saved list sort: remembers A–Z or newest first in `settings.json`.
  Future<void> setSortOrder(SortOrder order) =>
      updateSettings((s) => s.copyWith(sortOrder: order));

  /// Options: applies a settings change (auto-lock, clipboard time,
  /// generator defaults...) and saves it to `settings.json`.
  Future<void> updateSettings(Settings Function(Settings) change) async {
    final session = _current;
    final settings = change(session.settings);
    state = AsyncData(session.copyWith(settings: settings));
    await ref.read(settingsStoreProvider).save(settings);
  }

  /// Change PIN or password, step 1: checks the current secret. A wrong one
  /// counts as a failed unlock (same 5-try limit and waits), and reaching a
  /// wait locks the app, so Options can't be used to guess the PIN.
  Future<UnlockOutcome> checkCurrentSecret(String secret) async {
    final now = ref.read(clockProvider)();
    final session = _current;
    if (session.lockout.isLocked(now)) {
      lock();
      return UnlockOutcome.waiting;
    }
    // Same order as unlock: record the try before checking it.
    final store = ref.read(settingsStoreProvider);
    final failed = session.settings.copyWith(
      lockout: session.lockout.recordFailure(now),
    );
    await store.save(failed);

    if (await ref.read(vaultRepositoryProvider).checkSecret(secret)) {
      final cleared = session.settings.copyWith(
        lockout: session.lockout.recordSuccess(),
      );
      await store.save(cleared);
      state = AsyncData(session.copyWith(settings: cleared));
      return UnlockOutcome.success;
    }
    state = AsyncData(session.copyWith(settings: failed));
    if (failed.lockout.isLocked(now)) {
      lock();
      return UnlockOutcome.waiting;
    }
    return UnlockOutcome.wrong;
  }

  /// Change PIN or password, last step: re-encrypts the vault with
  /// [secret] (new salt) and remembers the unlock type. Biometric unlock
  /// stays on but its stored key is dropped, so the next unlock needs the
  /// new PIN (SPEC: PIN required after changing it).
  Future<void> changeSecret(String secret, UnlockType type) async {
    await ref.read(vaultRepositoryProvider).changeSecret(secret, type);
    await _biometrics.deleteRecord();
    final session = _current;
    final settings = session.settings.copyWith(unlockType: type);
    await ref.read(settingsStoreProvider).save(settings);
    state = AsyncData(session.copyWith(settings: settings, unlockType: type));
  }

  /// Damaged vault: restores `vault.vfy.bak`, then re-checks the files.
  /// Throws [VaultFormatException] if the backup is damaged too.
  Future<void> restoreFromBackup() async {
    await ref.read(vaultRepositoryProvider).restoreFromBackup();
    state = AsyncData(await build());
  }
}
