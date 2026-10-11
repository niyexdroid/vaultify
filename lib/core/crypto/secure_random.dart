import 'dart:math';
import 'dart:typed_data';

/// Secure randomness: the one shared source for salts, nonces, entry ids and
/// generated passwords. Always the OS cryptographic generator, never a seeded
/// `Random()`.
final Random secureRandom = Random.secure();

/// Secure randomness: [length] random bytes from [secureRandom].
Uint8List randomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = secureRandom.nextInt(256);
  }
  return bytes;
}

/// Secure randomness: [byteLength] random bytes as lowercase hex (entry ids).
String randomHex(int byteLength) => randomBytes(byteLength)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();
