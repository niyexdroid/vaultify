import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_store.dart';
import '../core/vault/vault_repository.dart';
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
