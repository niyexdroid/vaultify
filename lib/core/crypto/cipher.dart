import 'package:cryptography/cryptography.dart';

import 'secure_random.dart';

/// Vault encryption: thrown when decryption fails its GCM check. This is how
/// a wrong PIN is detected, and it is also what a tampered file produces;
/// by design the two cannot be told apart.
class DecryptionFailedException implements Exception {
  const DecryptionFailedException();

  @override
  String toString() => 'DecryptionFailedException';
}

/// Vault encryption: the output of [encrypt]. [cipherText] has the 16-byte
/// GCM tag appended, matching the "ciphertext" field of the vault file.
class Sealed {
  const Sealed({required this.nonce, required this.cipherText});

  final List<int> nonce;
  final List<int> cipherText;
}

// Vault encryption: AES-256-GCM, 12-byte nonce, 16-byte tag.
const int nonceLength = 12;
const int _macLength = 16;
final AesGcm _aesGcm = AesGcm.with256bits(nonceLength: nonceLength);

/// Vault encryption: encrypts [plainText] with a fresh random nonce. A new
/// nonce on every save means the same key never reuses one.
Future<Sealed> encrypt(List<int> plainText, SecretKey key) async {
  final nonce = randomBytes(nonceLength);
  final box = await _aesGcm.encrypt(plainText, secretKey: key, nonce: nonce);
  return Sealed(
    nonce: nonce,
    cipherText: [...box.cipherText, ...box.mac.bytes],
  );
}

/// Vault encryption: decrypts and verifies [sealed]. Throws
/// [DecryptionFailedException] for a wrong key or altered data.
Future<List<int>> decrypt(Sealed sealed, SecretKey key) async {
  final data = sealed.cipherText;
  if (sealed.nonce.length != nonceLength || data.length < _macLength) {
    throw const DecryptionFailedException();
  }
  final split = data.length - _macLength;
  final box = SecretBox(
    data.sublist(0, split),
    nonce: sealed.nonce,
    mac: Mac(data.sublist(split)),
  );
  try {
    return await _aesGcm.decrypt(box, secretKey: key);
  } on SecretBoxAuthenticationError {
    throw const DecryptionFailedException();
  }
}
