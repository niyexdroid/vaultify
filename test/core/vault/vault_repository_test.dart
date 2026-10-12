import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/cipher.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/crypto/secure_random.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/core/vault/vault_repository.dart';

// Vault repository tests: create, unlock, wrong PIN, tampering, safe saving,
// backup restore, PIN change and duplicate names.
void main() {
  const pin = '12345678';
  late Directory dir;

  // Cheap Argon2id settings keep these tests fast; kdf_test covers the
  // real parameters.
  KdfParams cheapParams() =>
      KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1);

  VaultRepository repo({void Function(SaveStep)? onSaveStep}) =>
      VaultRepository(dir, newKdfParams: cheapParams, onSaveStep: onSaveStep);

  Entry entry(String name, [String password = 'pw']) =>
      Entry.create(name: name, password: password, now: DateTime.utc(2026));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vaultify_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('create, lock, then unlock with the right PIN shows the entries',
      () async {
    final r = repo();
    expect(await r.exists(), isFalse);
    await r.create(pin, UnlockType.pin);
    await r.add(entry('Gmail', 'hunter2-long'));
    r.lock();
    expect(r.isUnlocked, isFalse);
    expect(r.entries, isEmpty);

    final reopened = repo();
    expect(await reopened.readUnlockType(), UnlockType.pin);
    await reopened.unlock(pin);
    expect(reopened.entries.single.name, 'Gmail');
    expect(reopened.entries.single.password, 'hunter2-long');
  });

  test('wrong PIN fails and shows nothing', () async {
    await repo().create(pin, UnlockType.pin);
    final r = repo();
    await expectLater(
        r.unlock('87654321'), throwsA(isA<DecryptionFailedException>()));
    expect(r.isUnlocked, isFalse);
    expect(r.entries, isEmpty);
  });

  test('a tampered file fails to open', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    await r.add(entry('Gmail'));
    r.lock();

    final json = jsonDecode(await r.vaultFile.readAsString())
        as Map<String, Object?>;
    final bytes = base64.decode(json['ciphertext'] as String);
    bytes[bytes.length ~/ 2] ^= 0x01;
    json['ciphertext'] = base64.encode(bytes);
    await r.vaultFile.writeAsString(jsonEncode(json));

    await expectLater(
        repo().unlock(pin), throwsA(isA<DecryptionFailedException>()));
  });

  test('a changed salt in the header also fails (header is bound to key)',
      () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    final json = jsonDecode(await r.vaultFile.readAsString())
        as Map<String, Object?>;
    (json['kdf'] as Map)['salt'] = base64.encode(randomBytes(16));
    await r.vaultFile.writeAsString(jsonEncode(json));
    await expectLater(
        repo().unlock(pin), throwsA(isA<DecryptionFailedException>()));
  });

  test('the vault file on disk contains no names or passwords', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    await r.add(Entry.create(
        name: 'MyBankName',
        username: 'someone@example.com',
        password: 'VerySecretPw',
        now: DateTime.utc(2026)));
    final text = await r.vaultFile.readAsString();
    for (final secret in ['MyBankName', 'someone@example', 'VerySecretPw']) {
      expect(text, isNot(contains(secret)));
    }
  });

  group('a crash mid-save leaves a readable vault', () {
    for (final step in SaveStep.values) {
      test('killed before "${step.name}"', () async {
        final setup = repo();
        await setup.create(pin, UnlockType.pin);
        await setup.add(entry('Old'));
        setup.lock();

        // Unlock with a repo whose next save "crashes" at [step].
        var armed = false;
        final r = repo(onSaveStep: (s) {
          if (armed && s == step) throw const FileSystemException('killed');
        });
        await r.unlock(pin);
        armed = true;
        await expectLater(r.add(entry('New')), throwsA(isA<FileSystemException>()));

        // "Restart": the vault opens and holds either the old or new list.
        final after = repo();
        await after.unlock(pin);
        final names = after.entries.map((e) => e.name).toList();
        expect(names, anyOf(equals(['Old']), equals(['Old', 'New'])));

        // And the next save still works, despite any leftover temp file.
        await after.add(entry('Later'));
        after.lock();
        final again = repo();
        await again.unlock(pin);
        expect(again.entries.map((e) => e.name), contains('Later'));
      });
    }

    test('a half-written temp file is ignored', () async {
      final r = repo();
      await r.create(pin, UnlockType.pin);
      await r.add(entry('Kept'));
      r.lock();
      await r.tempFile.writeAsString('{"format":"vaultify","ver');
      final after = repo();
      await after.unlock(pin);
      expect(after.entries.single.name, 'Kept');
    });
  });

  test('every save copies the previous file to .bak', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    expect(await r.backupExists(), isFalse); // nothing older than the first
    final first = await r.vaultFile.readAsString();
    await r.add(entry('A'));
    expect(await r.backupFile.readAsString(), first);
  });

  test('a damaged vault reports VaultFormatException and restores from .bak',
      () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    await r.add(entry('A'));
    await r.add(entry('B')); // .bak now holds the vault with just "A"
    r.lock();
    await r.vaultFile.writeAsString('{"format":"vaul'); // truncated

    final broken = repo();
    await expectLater(
        broken.unlock(pin), throwsA(isA<VaultFormatException>()));
    expect(await broken.backupExists(), isTrue);

    await broken.restoreFromBackup();
    await broken.unlock(pin);
    expect(broken.entries.map((e) => e.name), ['A']);
  });

  test('a missing vault file is VaultFormatException', () async {
    await expectLater(repo().unlock(pin), throwsA(isA<VaultFormatException>()));
  });

  test('changing the PIN re-encrypts; the old PIN stops working', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    await r.add(entry('Gmail'));
    final oldSalt =
        VaultFile.decode(await r.vaultFile.readAsString()).kdf.salt;

    await r.changeSecret('a long master password', UnlockType.password);
    final file = VaultFile.decode(await r.vaultFile.readAsString());
    expect(file.unlock, UnlockType.password);
    expect(file.kdf.salt, isNot(equals(oldSalt)));
    r.lock();

    await expectLater(
        repo().unlock(pin), throwsA(isA<DecryptionFailedException>()));
    final after = repo();
    await after.unlock('a long master password');
    expect(after.entries.single.name, 'Gmail');
  });

  test('checkSecret accepts the current PIN only, and follows a change',
      () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    expect(await r.checkSecret(pin), isTrue);
    expect(await r.checkSecret('87654321'), isFalse);

    await r.changeSecret('11223344', UnlockType.pin);
    expect(await r.checkSecret('11223344'), isTrue);
    expect(await r.checkSecret(pin), isFalse);

    r.lock();
    await expectLater(r.checkSecret(pin), throwsStateError);
  });

  test('biometric unlock: the exported key opens the vault without the PIN',
      () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    await r.add(entry('Gmail'));
    final key = await r.exportKey();
    expect(key, hasLength(32));
    r.lock();
    await expectLater(r.exportKey(), throwsStateError);

    final other = repo();
    await other.unlockWithKey(key);
    expect(other.isUnlocked, isTrue);
    expect(other.entries.single.name, 'Gmail');
    expect(other.unlockType, UnlockType.pin);
  });

  test('biometric unlock: a wrong or outdated key fails', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    final oldKey = await r.exportKey();
    await r.changeSecret('11223344', UnlockType.pin);
    r.lock();

    await expectLater(repo().unlockWithKey(oldKey),
        throwsA(isA<DecryptionFailedException>()));
    await expectLater(repo().unlockWithKey(List.filled(32, 7)),
        throwsA(isA<DecryptionFailedException>()));
    expect(r.isUnlocked, isFalse);
  });

  test('setup rejects invalid secrets and never overwrites a vault', () async {
    await expectLater(
        repo().create('123', UnlockType.pin), throwsArgumentError);
    await repo().create(pin, UnlockType.pin);
    await expectLater(repo().create(pin, UnlockType.pin), throwsStateError);
  });

  test('delete removes the entry and saves', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    await r.add(entry('A'));
    await r.add(entry('B'));
    await r.delete(r.entries.first.id);
    r.lock();
    final after = repo();
    await after.unlock(pin);
    expect(after.entries.map((e) => e.name), ['B']);
  });

  test('editing is refused while locked', () async {
    final r = repo();
    await r.create(pin, UnlockType.pin);
    r.lock();
    await expectLater(r.add(entry('A')), throwsStateError);
  });

  group('duplicate names', () {
    test('Keep both adds (2), (3)... ignoring case', () async {
      final r = repo();
      await r.create(pin, UnlockType.pin);
      expect(r.nextFreeName('Gmail'), 'Gmail');
      await r.add(entry('Gmail'));
      expect(r.nameExists('gmail '), isTrue);
      expect(r.nextFreeName('GMAIL'), 'GMAIL (2)');
      await r.add(entry('Gmail (2)'));
      expect(r.nextFreeName('Gmail'), 'Gmail (3)');
    });

    test('Keep both still fits in 64 characters', () async {
      final r = repo();
      await r.create(pin, UnlockType.pin);
      final long = 'x' * 64;
      await r.add(entry(long));
      final next = r.nextFreeName(long);
      expect(next.length, lessThanOrEqualTo(64));
      expect(next, endsWith(' (2)'));
    });

    test('Replace keeps id and created date, updates the password', () async {
      final r = repo();
      await r.create(pin, UnlockType.pin);
      await r.add(entry('Gmail', 'old'));
      final original = r.entries.single;
      await r.replaceByName(Entry.create(
          name: 'gmail', password: 'new', now: DateTime.utc(2027)));
      final replaced = r.entries.single;
      expect(replaced.id, original.id);
      expect(replaced.created, original.created);
      expect(replaced.password, 'new');
      expect(replaced.updated, DateTime.utc(2027));
    });
  });
}
