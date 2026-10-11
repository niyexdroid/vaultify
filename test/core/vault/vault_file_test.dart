import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/cipher.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';

// Vault file tests: format version 1 envelope, payload, unlock rules.
void main() {
  final file = VaultFile(
    unlock: UnlockType.pin,
    kdf: KdfParams.fresh(),
    sealed: const Sealed(nonce: [1, 2, 3], cipherText: [4, 5, 6]),
  );

  test('encodes the SPEC format version 1 fields', () {
    final json = jsonDecode(file.encode()) as Map<String, Object?>;
    expect(json['format'], 'vaultify');
    expect(json['version'], 1);
    expect(json['unlock'], 'pin');
    expect(json['cipher'], 'aes-256-gcm');
    expect((json['kdf'] as Map)['alg'], 'argon2id');
    expect((json['kdf'] as Map)['memoryKiB'], 19456);
    expect(json['nonce'], base64.encode([1, 2, 3]));
    expect(json['ciphertext'], base64.encode([4, 5, 6]));
  });

  test('decode reverses encode', () {
    final back = VaultFile.decode(file.encode());
    expect(back.unlock, UnlockType.pin);
    expect(back.kdf.salt, file.kdf.salt);
    expect(back.sealed.nonce, [1, 2, 3]);
    expect(back.sealed.cipherText, [4, 5, 6]);
  });

  test('damaged or foreign files are VaultFormatException', () {
    final good = jsonDecode(file.encode()) as Map<String, Object?>;
    final bad = [
      '',
      '{"format":"vaultify"', // truncated
      'not json',
      jsonEncode({...good, 'format': 'other'}),
      jsonEncode({...good, 'version': 2}),
      jsonEncode({...good, 'unlock': 'face'}),
      jsonEncode({...good, 'nonce': '%%%'}),
      jsonEncode({...good}..remove('kdf')),
    ];
    for (final text in bad) {
      expect(() => VaultFile.decode(text), throwsA(isA<VaultFormatException>()),
          reason: text);
    }
  });

  test('payload round-trips entries', () {
    final entries = [
      Entry.create(name: 'A', password: '1', now: DateTime.utc(2026)),
      Entry.create(name: 'B', username: 'u', password: '2', now: DateTime.utc(2026)),
    ];
    final back = decodePayload(encodePayload(entries));
    expect(back.map((e) => e.toJson()), entries.map((e) => e.toJson()));
    expect(() => decodePayload(utf8.encode('{"x":1}')),
        throwsA(isA<VaultFormatException>()));
  });

  test('PIN must be 6–12 digits; password 10+ characters', () {
    expect(UnlockType.pin.isValidSecret('12345'), isFalse);
    expect(UnlockType.pin.isValidSecret('123456'), isTrue);
    expect(UnlockType.pin.isValidSecret('123456789012'), isTrue);
    expect(UnlockType.pin.isValidSecret('1234567890123'), isFalse);
    expect(UnlockType.pin.isValidSecret('12345a'), isFalse);
    expect(UnlockType.pin.isValidSecret('١٢٣٤٥٦'), isFalse); // non-ASCII digits
    expect(UnlockType.password.isValidSecret('123456789'), isFalse);
    expect(UnlockType.password.isValidSecret('correct ho'), isTrue);
  });
}
