import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/kdf.dart';

// Key derivation tests: Argon2id parameters, determinism and salt handling.
void main() {
  // Cheap settings so most tests run fast; one test uses the real ones.
  KdfParams cheap(List<int> salt) =>
      KdfParams(salt: salt, memoryKiB: 64, iterations: 1);

  test('fresh params use the SPEC values and a random 16-byte salt', () {
    final a = KdfParams.fresh();
    final b = KdfParams.fresh();
    expect(a.memoryKiB, 19456);
    expect(a.iterations, 2);
    expect(a.parallelism, 1);
    expect(a.salt, hasLength(16));
    expect(a.salt, isNot(equals(b.salt)));
  });

  test('same secret and salt give the same 32-byte key', () async {
    final salt = List<int>.generate(16, (i) => i);
    final k1 = await (await deriveKey('12345678', cheap(salt))).extractBytes();
    final k2 = await (await deriveKey('12345678', cheap(salt))).extractBytes();
    expect(k1, hasLength(32));
    expect(k1, equals(k2));
  });

  test('a different secret or salt gives a different key', () async {
    final salt = List<int>.generate(16, (i) => i);
    final otherSalt = List<int>.generate(16, (i) => 100 + i);
    final base = await (await deriveKey('12345678', cheap(salt))).extractBytes();
    final wrongPin =
        await (await deriveKey('12345679', cheap(salt))).extractBytes();
    final newSalt =
        await (await deriveKey('12345678', cheap(otherSalt))).extractBytes();
    expect(wrongPin, isNot(equals(base)));
    expect(newSalt, isNot(equals(base)));
  });

  test('real SPEC parameters derive a key', () async {
    final key = await deriveKey('correct horse', KdfParams.fresh());
    expect(await key.extractBytes(), hasLength(32));
  });

  test('params round-trip through JSON', () {
    final params = KdfParams.fresh();
    final back = KdfParams.fromJson(params.toJson());
    expect(back.salt, params.salt);
    expect(back.memoryKiB, params.memoryKiB);
    expect(back.iterations, params.iterations);
    expect(back.parallelism, params.parallelism);
  });

  test('unknown algorithm or bad values are rejected', () {
    final json = KdfParams.fresh().toJson();
    expect(() => KdfParams.fromJson({...json, 'alg': 'scrypt'}),
        throwsFormatException);
    expect(() => KdfParams.fromJson({...json, 'iterations': 0}),
        throwsFormatException);
    expect(() => KdfParams.fromJson(null), throwsFormatException);
  });

  test('keysMatch: same key bytes match, different ones do not', () async {
    final salt = List<int>.generate(16, (i) => i);
    final a = await deriveKey('12345678', cheap(salt));
    final b = await deriveKey('12345678', cheap(salt));
    final c = await deriveKey('87654321', cheap(salt));
    expect(await keysMatch(a, b), isTrue);
    expect(await keysMatch(a, c), isFalse);
    expect(await keysMatch(a, SecretKeyData(const [1, 2, 3])), isFalse);
  });
}
