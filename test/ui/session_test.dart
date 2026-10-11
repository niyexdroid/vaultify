import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/crypto/secure_random.dart';
import 'package:vaultify/core/settings/settings_store.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/core/vault/vault_repository.dart';
import 'package:vaultify/ui/providers.dart';
import 'package:vaultify/ui/session.dart';

// Session controller tests: lock gate phases, setup, unlock, wrong-attempt
// waits surviving a restart, lock, and damaged-vault restore. Uses real
// files in a temp folder; each new container is an app restart.
void main() {
  const pin = '12345678';
  late Directory dir;
  late DateTime now;

  // Cheap Argon2id settings keep these tests fast.
  KdfParams cheapParams() =>
      KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1);

  // App start: a fresh container over the same folder.
  Future<ProviderContainer> start() async {
    final container = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      vaultRepositoryProvider
          .overrideWithValue(VaultRepository(dir, newKdfParams: cheapParams)),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    return container;
  }

  Session session(ProviderContainer c) => c.read(sessionProvider).requireValue;
  SessionController controller(ProviderContainer c) =>
      c.read(sessionProvider.notifier);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vaultify_session_');
    now = DateTime.utc(2026, 10, 11, 12);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('first launch shows setup; create opens the vault', () async {
    final app = await start();
    expect(session(app).phase, Phase.setup);

    await controller(app).create(pin, UnlockType.pin);
    expect(session(app).phase, Phase.unlocked);
    expect(app.read(vaultRepositoryProvider).isUnlocked, isTrue);

    final saved = await SettingsStore(dir).load();
    expect(saved.unlockType, UnlockType.pin);
  });

  test('create a PIN, restart, unlock with it', () async {
    await controller(await start()).create(pin, UnlockType.pin);

    final app = await start();
    expect(session(app).phase, Phase.locked);
    expect(session(app).unlockType, UnlockType.pin);

    expect(await controller(app).unlock(pin), UnlockOutcome.success);
    expect(session(app).phase, Phase.unlocked);
  });

  test('wrong PIN stays locked and counts the try', () async {
    await controller(await start()).create(pin, UnlockType.pin);
    final app = await start();

    expect(await controller(app).unlock('87654321'), UnlockOutcome.wrong);
    expect(session(app).phase, Phase.locked);
    expect(session(app).lockout.failedAttempts, 1);
    expect(session(app).lockout.attemptsBeforeWait, 4);
    expect(app.read(vaultRepositoryProvider).isUnlocked, isFalse);
  });

  test('5 wrong tries start a 30 s wait that survives a restart', () async {
    await controller(await start()).create(pin, UnlockType.pin);
    var app = await start();
    for (var i = 0; i < 5; i++) {
      expect(await controller(app).unlock('00000000'), UnlockOutcome.wrong);
    }
    expect(session(app).lockout.remaining(now), const Duration(seconds: 30));

    // Restart: still waiting, and even the right PIN is refused.
    app = await start();
    expect(session(app).lockout.isLocked(now), isTrue);
    expect(await controller(app).unlock(pin), UnlockOutcome.waiting);
    expect(app.read(vaultRepositoryProvider).isUnlocked, isFalse);

    // After the wait the right PIN works and clears the counter.
    now = now.add(const Duration(seconds: 31));
    expect(await controller(app).unlock(pin), UnlockOutcome.success);
    expect(session(app).lockout.failedAttempts, 0);
    expect((await SettingsStore(dir).load()).lockout.failedAttempts, 0);
  });

  test('a 6th wrong try after the wait waits 1 min', () async {
    await controller(await start()).create(pin, UnlockType.pin);
    final app = await start();
    for (var i = 0; i < 5; i++) {
      await controller(app).unlock('00000000');
    }
    now = now.add(const Duration(seconds: 31));
    expect(await controller(app).unlock('00000000'), UnlockOutcome.wrong);
    expect(session(app).lockout.remaining(now), const Duration(minutes: 1));
  });

  test('lock drops the key and returns to unlock', () async {
    final app = await start();
    await controller(app).create(pin, UnlockType.pin);
    controller(app).lock();
    expect(session(app).phase, Phase.locked);
    expect(app.read(vaultRepositoryProvider).isUnlocked, isFalse);
  });

  test('master password vault asks for a password after restart', () async {
    await controller(await start()).create('long enough pw', UnlockType.password);
    final app = await start();
    expect(session(app).unlockType, UnlockType.password);
    expect(await controller(app).unlock('long enough pw'), UnlockOutcome.success);
  });

  test('damaged vault offers the backup and restore leads to unlock',
      () async {
    final app = await start();
    await controller(app).create(pin, UnlockType.pin);
    // A second save makes vault.vfy.bak (the first good save).
    await app.read(vaultRepositoryProvider).delete('none');
    await File('${dir.path}/vault.vfy').writeAsString('{ broken');

    final restarted = await start();
    expect(session(restarted).phase, Phase.damaged);
    expect(session(restarted).hasBackup, isTrue);

    await controller(restarted).restoreFromBackup();
    expect(session(restarted).phase, Phase.locked);
    expect(await controller(restarted).unlock(pin), UnlockOutcome.success);
  });

  test('damaged vault with no backup says so', () async {
    await File('${dir.path}/vault.vfy').writeAsString('not a vault');
    final app = await start();
    expect(session(app).phase, Phase.damaged);
    expect(session(app).hasBackup, isFalse);
  });
}
