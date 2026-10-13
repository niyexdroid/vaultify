import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/clipboard_guard.dart';
import '../core/settings/settings_store.dart';
import '../core/vault/backup.dart';
import '../core/vault/vault_repository.dart';
import '../platform/backup_files.dart';
import '../platform/biometrics.dart';
import '../platform/sensitive_clipboard.dart';
import '../platform/window.dart';

/// App data folder: the private support folder from path_provider. Set in
/// main.dart (it needs an async lookup); tests point it at a temp folder.
final appDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('appDirectoryProvider must be overridden'),
);

/// Vault repository: the one vault for this device.
final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => VaultRepository(ref.watch(appDirectoryProvider)),
);

/// Settings store: `settings.json` next to the vault.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(appDirectoryProvider)),
);

/// Clock: current time, swappable so tests can control wrong-attempt waits.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Mobile layout: number pad for PINs, bottom bar navigation. True on
/// Android and iOS; tests override it to check both layouts.
final mobileLayoutProvider = Provider<bool>((ref) => !isDesktop);

/// Biometric unlock: fingerprint / face check and the secure key slot.
/// Mobile only; desktop gets a stand-in that is never available.
final biometricsProvider = Provider<Biometrics>(
  (ref) => isDesktop ? const NoBiometrics() : DeviceBiometrics(),
);

/// Biometric unlock: whether this phone has a fingerprint or face set up
/// (Options shows the switch greyed out when not).
final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricsProvider).isAvailable(),
);

/// Clipboard clearing: one guard for the whole app, so a countdown keeps
/// running across tabs and after locking. Uses Flutter's Clipboard.
final clipboardGuardProvider = Provider<ClipboardGuard>((ref) {
  final guard = ClipboardGuard(
    write: (text) => Clipboard.setData(ClipboardData(text: text)),
    writeSecret: copySensitive,
    read: () async =>
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(guard.dispose);
  return guard;
});

/// Backup export/import: encrypts and decrypts backup files. Tests swap in
/// a stand-in that skips Argon2.
final backupCodecProvider = Provider<BackupCodec>((ref) => const BackupCodec());

/// Backup export/import: the system Save / Open windows.
final backupFilesProvider = Provider<BackupFiles>(
  (ref) => const SystemBackupFiles(),
);

/// Backup export/import (mobile): background lock pause. Opening the system
/// Save / Open window sends Vaultify to the background, which would
/// otherwise lock the vault mid-export. Only Vaultify's own windows pause
/// it; the idle auto-lock still applies when the user comes back.
final backgroundLockPauseProvider = Provider<BackgroundLockPause>(
  (ref) => BackgroundLockPause(),
);

class BackgroundLockPause {
  int _depth = 0;

  /// Whether a Save / Open window is open right now.
  bool get active => _depth > 0;

  /// Runs [action] (which opens a system window) with background lock off.
  Future<T> during<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
    }
  }
}
