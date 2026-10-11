import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/cipher.dart';

// Vault encryption tests: AES-256-GCM round trip, wrong key, tampering.
void main() {
  final key = SecretKeyData(List<int>.generate(32, (i) => i));
  final otherKey = SecretKeyData(List<int>.generate(32, (i) => 255 - i));
  final plain = utf8.encode('{"entries":[]}');

  test('encrypt then decrypt returns the original bytes', () async {
    final sealed = await encrypt(plain, key);
    expect(sealed.nonce, hasLength(12));
    expect(sealed.cipherText, hasLength(plain.length + 16)); // + GCM tag
    expect(await decrypt(sealed, key), plain);
  });

  test('every encryption uses a fresh nonce', () async {
    final a = await encrypt(plain, key);
    final b = await encrypt(plain, key);
    expect(a.nonce, isNot(equals(b.nonce)));
    expect(a.cipherText, isNot(equals(b.cipherText)));
  });

  test('the wrong key fails', () async {
    final sealed = await encrypt(plain, key);
    expect(decrypt(sealed, otherKey),
        throwsA(isA<DecryptionFailedException>()));
  });

  test('a flipped bit in the ciphertext, tag or nonce fails', () async {
    final sealed = await encrypt(plain, key);
    List<int> flip(List<int> bytes, int i) => [...bytes]..[i] ^= 1;

    for (final i in [0, sealed.cipherText.length - 1]) {
      final tampered =
          Sealed(nonce: sealed.nonce, cipherText: flip(sealed.cipherText, i));
      expect(decrypt(tampered, key),
          throwsA(isA<DecryptionFailedException>()));
    }
    final badNonce =
        Sealed(nonce: flip(sealed.nonce, 0), cipherText: sealed.cipherText);
    expect(decrypt(badNonce, key), throwsA(isA<DecryptionFailedException>()));
  });

  test('truncated data fails instead of crashing', () async {
    expect(decrypt(const Sealed(nonce: [1, 2, 3], cipherText: []), key),
        throwsA(isA<DecryptionFailedException>()));
  });
}
