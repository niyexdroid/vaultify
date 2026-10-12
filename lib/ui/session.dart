import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/cipher.dart';
import '../core/security/lockout.dart';
import '../core/settings/settings.dart';
import '../core/vault/vault_file.dart';
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

/// Session: the lock gate's view of the vault plus the settings it needs.
class Session {
  const Session({
    required this.phase,
    required this.settings,
    this.unlockType,
    this.hasBackup = false,
  });

  final Phase phase;
  final Settings settings;

  /// Which secret the vault uses (null during setup or when damaged).
  final UnlockType? unlockType;

  /// Damaged vault: whether `vault.vfy.bak` exists to restore from.
  final bool hasBackup;

  LockoutState get lockout => settings.lockout;

  Session copyWith({
    Phase? phase,
    Settings? settings,
    UnlockType? unlockType,
    bool? hasBackup,
  }) =>
      Session(
        phase: phase ?? this.phase,
        settings: settings ?? this.settings,
        unlockType: unlockType ?? this.unlockType,
        hasBackup: hasBackup ?? this.hasBackup,
      );
}

/// Session controller: setup, unlock, lock and restore. Wrong-attempt waits
/// are enforced here, not only in the unlock screen.
final sessionProvider =
    AsyncNotifierProvider<SessionController, Session>(SessionController.new);

class SessionController extends AsyncNotifier<Session> {
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

  /// First-launch setup: creates the vault with [secret] and opens it.
  Future<void> create(String secret, UnlockType type) async {
    await ref.read(vaultRepositoryProvider).create(secret, type);
    final settings = _current.settings.copyWith(
      unlockType: type,
      lockout: LockoutState.initial,
    );
    await ref.read(settingsStoreProvider).save(settings);
    state = AsyncData(Session(
      phase: Phase.unlocked,
      settings: settings,
      unlockType: type,
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

    final cleared = session.settings.copyWith(
      lockout: session.lockout.recordSuccess(),
    );
    await store.save(cleared);
    state = AsyncData(session.copyWith(
      phase: Phase.unlocked,
      settings: cleared,
    ));
    return UnlockOutcome.success;
  }

  /// Lock: drops the key and entries from memory and shows unlock.
  void lock() {
    ref.read(vaultRepositoryProvider).lock();
    final session = state.value;
    if (session != null && session.phase == Phase.unlocked) {
      state = AsyncData(session.copyWith(phase: Phase.locked));
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
  /// [secret] (new salt) and remembers the unlock type.
  Future<void> changeSecret(String secret, UnlockType type) async {
    await ref.read(vaultRepositoryProvider).changeSecret(secret, type);
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
