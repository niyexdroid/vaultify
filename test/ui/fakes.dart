import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/app.dart';
import 'package:vaultify/core/crypto/cipher.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/settings/settings_store.dart';
import 'package:vaultify/core/totp/totp.dart';
import 'package:vaultify/core/vault/backup.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/core/vault/vault_repository.dart';
import 'package:vaultify/platform/backup_files.dart';
import 'package:vaultify/platform/biometrics.dart';
import 'package:vaultify/ui/providers.dart';

/// Widget test vault: in-memory stand-in for [VaultRepository], so screen
/// tests skip Argon2 and file I/O. Test-only; never used by the app.
class FakeVaultRepository extends Fake implements VaultRepository {
  FakeVaultRepository({this.secret, this.type = UnlockType.pin});

  String? secret;
  UnlockType type;
  bool unlocked = false;
  final List<String> tried = [];

  @override
  Future<bool> exists() async => secret != null;

  @override
  Future<bool> backupExists() async => false;

  @override
  Future<UnlockType> readUnlockType() async => type;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<void> create(String secret, UnlockType type) async {
    this.secret = secret;
    this.type = type;
    unlocked = true;
  }

  @override
  Future<void> unlock(String secret) async {
    tried.add(secret);
    if (secret != this.secret) throw const DecryptionFailedException();
    unlocked = true;
  }

  @override
  void lock() => unlocked = false;

  // Biometric unlock: a stand-in key made from the secret, so changing the
  // PIN makes an old key stop working, like the real vault.
  List<int> get _key => fakeKeyFor(secret!);

  @override
  Future<List<int>> exportKey() async {
    if (!unlocked) throw StateError('vault is locked');
    return _key;
  }

  @override
  Future<void> unlockWithKey(List<int> keyBytes) async {
    if (!_sameBytes(keyBytes, _key)) throw const DecryptionFailedException();
    unlocked = true;
  }

  static bool _sameBytes(List<int> a, List<int> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  // Change PIN or password: plain comparisons instead of Argon2.
  @override
  Future<bool> checkSecret(String secret) async => secret == this.secret;

  @override
  Future<void> changeSecret(String newSecret, UnlockType type) async {
    secret = newSecret;
    this.type = type;
  }

  // Saved entries: kept in a plain list; survives lock/unlock like a file.
  final List<Entry> saved = [];

  @override
  List<Entry> get entries => unlocked ? List.unmodifiable(saved) : const [];

  @override
  Future<void> add(Entry entry) async => saved.add(entry);

  @override
  Future<void> delete(String id) async => saved.removeWhere((e) => e.id == id);

  bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  bool nameExists(String name) => saved.any((e) => _same(e.name, name));

  @override
  String nextFreeName(String name) {
    if (!nameExists(name)) return name.trim();
    for (var n = 2;; n++) {
      final candidate = '${name.trim()} ($n)';
      if (!nameExists(candidate)) return candidate;
    }
  }

  @override
  Future<void> replaceByName(Entry entry) async {
    final i = saved.indexWhere((e) => _same(e.name, entry.name));
    if (i < 0) return add(entry);
    saved[i] = saved[i].copyWith(
        username: entry.username, password: entry.password);
  }

  // TOTP codes: add or remove an entry's two-factor secret.
  @override
  Future<void> setTotp(String id, TotpSecret? secret) async {
    final i = saved.indexWhere((e) => e.id == id);
    if (i < 0) return;
    saved[i] = saved[i].copyWith(totp: secret, clearTotp: secret == null);
  }

  // Backup import: same merge rules as the real vault.
  @override
  Future<MergeResult> importEntries(List<Entry> incoming) async {
    final result = mergeEntries(saved, incoming);
    saved
      ..clear()
      ..addAll(result.entries);
    return result;
  }
}

/// Biometric unlock tests: the key [FakeVaultRepository] uses for [secret].
List<int> fakeKeyFor(String secret) =>
    List.generate(32, (i) => secret.codeUnitAt(i % secret.length));

/// Widget test settings: kept in memory instead of `settings.json`.
class FakeSettingsStore extends Fake implements SettingsStore {
  Settings saved = const Settings();

  @override
  Future<Settings> load() async => saved;

  @override
  Future<void> save(Settings settings) async => saved = settings;
}

/// Widget test biometrics: a fake fingerprint sensor and key slot. Each
/// prompt returns the next queued result (success if none are queued).
class FakeBiometrics implements Biometrics {
  FakeBiometrics({this.available = true});

  bool available;
  String? record;
  final List<BiometricResult> results = [];
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    prompts++;
    return results.isEmpty ? BiometricResult.success : results.removeAt(0);
  }

  @override
  Future<String?> readRecord() async => record;

  @override
  Future<bool> hasRecord() async => record != null;

  @override
  Future<void> writeRecord(String record) async => this.record = record;

  @override
  Future<void> deleteRecord() async => record = null;
}

/// Backup export/import tests: a stand-in for [BackupCodec] that skips
/// Argon2 and AES. The file is still a real [BackupFile] envelope (so the
/// app's own format check runs), but the "nonce" holds the password and
/// the "ciphertext" is the plain payload. Test-only.
class FakeBackupCodec extends Fake implements BackupCodec {
  @override
  Future<String> seal(
    List<Entry> entries,
    String password, {
    required DateTime now,
  }) async =>
      BackupFile(
        exported: now.toUtc(),
        kdf: KdfParams(salt: const [0], memoryKiB: 8, iterations: 1),
        sealed: Sealed(
          nonce: utf8.encode(password),
          cipherText: encodePayload(entries),
        ),
      ).encode();

  @override
  Future<List<Entry>> open(BackupFile file, String password) async {
    if (utf8.decode(file.sealed.nonce) != password) {
      throw const DecryptionFailedException();
    }
    return decodePayload(file.sealed.cipherText);
  }
}

/// Backup export/import tests: fake Save / Open windows. [whileOpen] runs
/// while a window is "on screen" (e.g. to send the app to the background).
class FakeBackupFiles implements BackupFiles {
  String? savedName;
  String? savedText;
  bool cancelSave = false;
  String? toPick;
  Future<void> Function()? whileOpen;

  @override
  Future<bool> save(String fileName, List<int> bytes) async {
    await whileOpen?.call();
    if (cancelSave) return false;
    savedName = fileName;
    savedText = utf8.decode(bytes);
    return true;
  }

  @override
  Future<String?> pickText() async {
    await whileOpen?.call();
    return toPick;
  }
}

/// Widget tests: pumps the whole app with fakes; [mobile] picks the layout.
Future<void> pumpVaultify(
  WidgetTester tester, {
  required FakeVaultRepository repo,
  FakeSettingsStore? store,
  bool mobile = false,
  DateTime Function()? clock,
  Biometrics? biometrics,
  BackupFiles? backupFiles,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDirectoryProvider.overrideWithValue(Directory.systemTemp),
      vaultRepositoryProvider.overrideWithValue(repo),
      settingsStoreProvider.overrideWithValue(store ?? FakeSettingsStore()),
      mobileLayoutProvider.overrideWithValue(mobile),
      if (clock != null) clockProvider.overrideWithValue(clock),
      if (biometrics != null)
        biometricsProvider.overrideWithValue(biometrics),
      backupCodecProvider.overrideWithValue(FakeBackupCodec()),
      if (backupFiles != null)
        backupFilesProvider.overrideWithValue(backupFiles),
    ],
    child: const VaultifyApp(),
  ));
  await tester.pumpAndSettle();
}

/// Widget tests: types on the on-screen number pad.
Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.widgetWithText(TextButton, d));
    await tester.pump();
  }
}
