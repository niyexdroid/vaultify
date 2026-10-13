import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_random.dart';

/// Key derivation: Argon2id settings stored in the vault file header, so a
/// later version can strengthen them and migrate old vaults on unlock.
class KdfParams {
  const KdfParams({
    required this.salt,
    this.memoryKiB = defaultMemoryKiB,
    this.iterations = defaultIterations,
    this.parallelism = defaultParallelism,
  });

  /// Key derivation: fresh parameters with a new random 16-byte salt.
  /// Used when a vault is created and whenever the PIN or password changes.
  factory KdfParams.fresh() => KdfParams(salt: randomBytes(saltLength));

  // Key derivation: values fixed by SPEC.md "Security requirements".
  static const String algorithm = 'argon2id';
  static const int defaultMemoryKiB = 19456; // 19 MiB
  static const int defaultIterations = 2;
  static const int defaultParallelism = 1;
  static const int saltLength = 16;
  static const int keyLength = 32; // AES-256

  final List<int> salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object> toJson() => {
        'alg': algorithm,
        'salt': base64.encode(salt),
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
      };

  /// Key derivation: reads the "kdf" block of a vault header. Throws
  /// [FormatException] for anything missing, unknown or out of range.
  factory KdfParams.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('kdf block missing');
    }
    if (json['alg'] != algorithm) {
      throw const FormatException('unsupported kdf');
    }
    final salt = json['salt'];
    final memory = json['memoryKiB'];
    final iterations = json['iterations'];
    final parallelism = json['parallelism'];
    if (salt is! String ||
        memory is! int ||
        iterations is! int ||
        parallelism is! int ||
        memory < 8 ||
        iterations < 1 ||
        parallelism < 1) {
      throw const FormatException('bad kdf parameters');
    }
    return KdfParams(
      salt: base64.decode(salt),
      memoryKiB: memory,
      iterations: iterations,
      parallelism: parallelism,
    );
  }
}

/// Key derivation: stretches the PIN or master password into the 32-byte
/// vault key with Argon2id. The secret itself is never stored anywhere.
Future<SecretKey> deriveKey(String secret, KdfParams params) async {
  final argon2id = Argon2id(
    parallelism: params.parallelism,
    memory: params.memoryKiB,
    iterations: params.iterations,
    hashLength: KdfParams.keyLength,
  );
  // Key derivation: zero the secret's byte copy as soon as the key exists.
  final input = SecretKeyData(utf8.encode(secret));
  try {
    return await argon2id.deriveKey(secretKey: input, nonce: params.salt);
  } finally {
    input.destroy();
  }
}

/// Change PIN or password: whether two keys hold the same bytes. Compares
/// every byte (no early exit) so timing doesn't reveal how much matched.
Future<bool> keysMatch(SecretKey a, SecretKey b) async {
  final x = await a.extractBytes();
  final y = await b.extractBytes();
  if (x.length != y.length) return false;
  var diff = 0;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

/// Lock and backup: zero a key's bytes once it is no longer needed, where
/// the key type allows it.
void destroyKey(SecretKey key) {
  if (key is SecretKeyData) key.destroy();
}
