import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/app.dart';
import 'package:vaultify/core/crypto/cipher.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/settings/settings_store.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/core/vault/vault_repository.dart';
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
}

/// Widget test settings: kept in memory instead of `settings.json`.
class FakeSettingsStore extends Fake implements SettingsStore {
  Settings saved = const Settings();

  @override
  Future<Settings> load() async => saved;

  @override
  Future<void> save(Settings settings) async => saved = settings;
}

/// Widget tests: pumps the whole app with fakes; [mobile] picks the layout.
Future<void> pumpVaultify(
  WidgetTester tester, {
  required FakeVaultRepository repo,
  FakeSettingsStore? store,
  bool mobile = false,
  DateTime Function()? clock,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDirectoryProvider.overrideWithValue(Directory.systemTemp),
      vaultRepositoryProvider.overrideWithValue(repo),
      settingsStoreProvider.overrideWithValue(store ?? FakeSettingsStore()),
      mobileLayoutProvider.overrideWithValue(mobile),
      if (clock != null) clockProvider.overrideWithValue(clock),
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
