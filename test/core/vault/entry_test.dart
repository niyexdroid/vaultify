import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/totp/base32.dart';
import 'package:vaultify/core/totp/totp.dart';
import 'package:vaultify/core/vault/entry.dart';

// Saved entry tests: creation rules and JSON.
void main() {
  final now = DateTime.utc(2026, 10, 11, 12);

  test('create trims, assigns a 16-byte hex id and UTC dates', () {
    final e = Entry.create(
      name: '  Gmail ',
      username: ' me@example.com ',
      password: 'p',
      now: now.toLocal(),
    );
    expect(e.name, 'Gmail');
    expect(e.username, 'me@example.com');
    expect(e.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(e.created.isUtc, isTrue);
    expect(e.created, now);
    expect(e.updated, now);
  });

  test('names must be 1–64 characters', () {
    expect(Entry.isValidName(''), isFalse);
    expect(Entry.isValidName('   '), isFalse);
    expect(Entry.isValidName('a' * 64), isTrue);
    expect(Entry.isValidName('a' * 65), isFalse);
    expect(() => Entry.create(name: ' ', password: 'p', now: now),
        throwsArgumentError);
  });

  test('round-trips through JSON', () {
    final e = Entry.create(name: 'Bank', password: 'x!9', now: now);
    final back = Entry.fromJson(e.toJson());
    expect(back.toJson(), e.toJson());
  });

  test('missing fields are rejected', () {
    expect(() => Entry.fromJson({'id': 'a'}), throwsFormatException);
    expect(() => Entry.fromJson('nope'), throwsFormatException);
  });

  test('toString never contains the password', () {
    final e = Entry.create(name: 'Bank', password: 'secret-value', now: now);
    expect(e.toString(), isNot(contains('secret-value')));
  });

  // TOTP codes: the two-factor secret rides along inside the entry.
  group('two-factor secret', () {
    final secret = TotpSecret(
      key: decodeBase32('GEZDGNBVGY3TQOJQ'),
      issuer: 'GitHub',
      account: 'ada@example.com',
    );

    test('a new entry has none', () {
      final e = Entry.create(name: 'Bank', password: 'x', now: now);
      expect(e.hasTotp, isFalse);
      expect(e.toJson().containsKey('totp'), isFalse);
    });

    test('survives a JSON round trip', () {
      final e = Entry.create(
          name: 'GitHub', password: 'x', now: now, totp: secret);
      final back = Entry.fromJson(jsonDecode(jsonEncode(e.toJson())));
      expect(back.hasTotp, isTrue);
      expect(back.totp!.key, secret.key);
      expect(back.totp!.label, 'GitHub · ada@example.com');
    });

    test('an entry saved before the feature reads back with none', () {
      final old = Entry.create(name: 'Bank', password: 'x', now: now).toJson()
        ..remove('totp');
      expect(Entry.fromJson(old).hasTotp, isFalse);
    });

    test('copyWith sets it, clearTotp removes it', () {
      final e = Entry.create(name: 'GitHub', password: 'x', now: now);
      final withCode = e.copyWith(totp: secret);
      expect(withCode.hasTotp, isTrue);
      // Another copy that says nothing about it keeps the secret.
      expect(withCode.copyWith(password: 'y').hasTotp, isTrue);
      expect(withCode.copyWith(clearTotp: true).hasTotp, isFalse);
    });
  });
}
