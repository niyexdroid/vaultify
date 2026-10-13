import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/cipher.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/crypto/secure_random.dart';
import 'package:vaultify/core/vault/backup.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';

// Backup export/import tests: file format, backup password, encryption
// round trip, wrong password, tampering, and the merge rules.
void main() {
  const password = 'correct horse battery';
  final now = DateTime.utc(2026, 10, 12, 9, 30);

  // Cheap Argon2id settings keep these tests fast; one test checks the
  // real export settings.
  KdfParams cheapParams() =>
      KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1);
  final codec = BackupCodec(newKdfParams: cheapParams);

  Entry entry(String name, {String user = '', String pw = 'pw'}) =>
      Entry.create(name: name, username: user, password: pw, now: now);

  group('backup file', () {
    test('export then import gives back the same entries', () async {
      final entries = [
        entry('Gmail', user: 'me', pw: 'hunter2-long'),
        entry('Bank'),
      ];
      final text = await codec.seal(entries, password, now: now);
      final file = BackupFile.decode(text);
      expect(file.exported, now);

      final back = await codec.open(file, password);
      expect(back.map((e) => e.toJson()), entries.map((e) => e.toJson()));
    });

    test('the file holds no readable passwords or names', () async {
      final text = await codec.seal(
        [entry('MyBankName', pw: 'SuperSecret123')],
        password,
        now: now,
      );
      expect(text, isNot(contains('SuperSecret123')));
      expect(text, isNot(contains('MyBankName')));
      expect(jsonDecode(text)['format'], 'vaultify-backup');
    });

    test('wrong password fails', () async {
      final file = BackupFile.decode(
        await codec.seal([entry('Gmail')], password, now: now),
      );
      await expectLater(
        codec.open(file, 'wrong password!!'),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('a tampered file fails', () async {
      final json = jsonDecode(
        await codec.seal([entry('Gmail')], password, now: now),
      ) as Map<String, Object?>;
      final bytes = base64.decode(json['ciphertext'] as String);
      bytes[0] ^= 1;
      json['ciphertext'] = base64.encode(bytes);
      final file = BackupFile.decode(jsonEncode(json));
      await expectLater(
        codec.open(file, password),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('each export uses a fresh salt and nonce', () async {
      final a = jsonDecode(await codec.seal([], password, now: now));
      final b = jsonDecode(await codec.seal([], password, now: now));
      expect(a['kdf']['salt'], isNot(b['kdf']['salt']));
      expect(a['nonce'], isNot(b['nonce']));
    });

    test('real export settings are Argon2id 64 MiB, 3 passes', () {
      final p = BackupCodec.strongKdfParams();
      expect(p.memoryKiB, 65536);
      expect(p.iterations, 3);
      expect(p.salt, hasLength(16));
    });

    test('backup password needs 12 or more characters', () async {
      expect(isValidBackupPassword('12345678901'), isFalse);
      expect(isValidBackupPassword('123456789012'), isTrue);
      await expectLater(codec.seal([], 'short', now: now), throwsArgumentError);
    });

    test('a vault file, junk or a newer version is not a backup', () async {
      final vault = VaultFile(
        unlock: UnlockType.pin,
        kdf: cheapParams(),
        sealed: const Sealed(nonce: [1], cipherText: [2]),
      ).encode();
      expect(
        () => BackupFile.decode(vault),
        throwsA(isA<VaultFormatException>()),
      );
      expect(
        () => BackupFile.decode('not json'),
        throwsA(isA<VaultFormatException>()),
      );

      final json = jsonDecode(await codec.seal([], password, now: now));
      json['version'] = 2;
      expect(
        () => BackupFile.decode(jsonEncode(json)),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('refuses Argon2 settings big enough to hang the app', () async {
      final json = jsonDecode(await codec.seal([], password, now: now));
      json['kdf']['memoryKiB'] = BackupFile.maxMemoryKiB + 1;
      expect(
        () => BackupFile.decode(jsonEncode(json)),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('file name has the date and .vaultify', () {
      expect(
        backupFileName(DateTime(2026, 3, 5)),
        'vaultify-backup-2026-03-05.vaultify',
      );
    });
  });

  group('merge', () {
    test('adds new entries after the existing ones', () {
      final mine = [entry('Gmail')];
      final r = mergeEntries(mine, [entry('Bank'), entry('Shop')]);
      expect(r.entries.map((e) => e.name), ['Gmail', 'Bank', 'Shop']);
      expect((r.added, r.skipped, r.renamed), (2, 0, 0));
    });

    test('skips exact duplicates (name ignoring case, user, password)', () {
      final mine = [entry('Gmail', user: 'me', pw: 'a')];
      final r = mergeEntries(mine, [entry('gmail', user: 'me', pw: 'a')]);
      expect(r.entries, hasLength(1));
      expect((r.added, r.skipped, r.renamed), (0, 1, 0));
    });

    test('same name, different password is kept as "Name (2)"', () {
      final mine = [entry('Gmail', pw: 'old')];
      final r = mergeEntries(mine, [entry('Gmail', pw: 'new')]);
      expect(r.entries.map((e) => e.name), ['Gmail', 'Gmail (2)']);
      expect(r.entries.first.password, 'old');
      expect((r.added, r.skipped, r.renamed), (1, 0, 1));
    });

    test('importing the same backup twice adds nothing the second time', () {
      final backup = [entry('Gmail'), entry('Bank')];
      final once = mergeEntries([], backup);
      final twice = mergeEntries(once.entries, backup);
      expect(twice.entries, hasLength(2));
      expect(twice.skipped, 2);
    });

    test('a clashing id gets a new one; dates come across', () {
      final mine = [entry('Gmail')];
      final clash = Entry(
        id: mine.first.id,
        name: 'Bank',
        username: '',
        password: 'x',
        created: DateTime.utc(2020),
        updated: DateTime.utc(2021),
      );
      final r = mergeEntries(mine, [clash]);
      expect(r.entries.last.id, isNot(mine.first.id));
      expect(r.entries.last.created, DateTime.utc(2020));
      expect(r.entries.last.updated, DateTime.utc(2021));
    });

    test('bad names from a file are made to fit', () {
      expect(cleanEntryName('   '), 'Imported');
      expect(cleanEntryName('  Gmail '), 'Gmail');
      expect(cleanEntryName('x' * 80), 'x' * Entry.maxNameLength);
    });
  });
}
