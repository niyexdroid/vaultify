import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/crypto/secure_random.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/core/vault/vault_repository.dart';
import 'package:vaultify/ui/providers.dart';
import 'package:vaultify/ui/session.dart';
import 'package:vaultify/ui/vault_entries.dart';

// Saved entries tests (Milestone 4 done-check): a saved password is written
// to the real encrypted vault file and is still there after a restart.
void main() {
  const pin = '12345678';
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vaultify_entries_');
  });
  tearDown(() => dir.delete(recursive: true));

  // A fresh container is like a fresh app start: nothing kept in memory.
  ProviderContainer start() {
    final container = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      vaultRepositoryProvider.overrideWithValue(VaultRepository(
        dir,
        newKdfParams: () =>
            KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1),
      )),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('a saved password survives a restart', () async {
    final first = start();
    await first.read(sessionProvider.future);
    await first.read(sessionProvider.notifier).create(pin, UnlockType.pin);
    await first.read(vaultEntriesProvider.notifier).add(
        name: 'Gmail', username: 'me', password: 'generated-pw');
    expect(first.read(vaultEntriesProvider), hasLength(1));
    first.dispose();

    final second = start();
    expect((await second.read(sessionProvider.future)).phase, Phase.locked);
    expect(second.read(vaultEntriesProvider), isEmpty);
    await second.read(sessionProvider.notifier).unlock(pin);
    final entries = second.read(vaultEntriesProvider);
    expect(entries.single.name, 'Gmail');
    expect(entries.single.username, 'me');
    expect(entries.single.password, 'generated-pw');

    // Locking empties the list again.
    second.read(sessionProvider.notifier).lock();
    expect(second.read(vaultEntriesProvider), isEmpty);
  });
}
