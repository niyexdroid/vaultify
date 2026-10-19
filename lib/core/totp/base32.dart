/// TOTP secret: base32 (RFC 4648) decoding, the format authenticator apps
/// use for shared secrets. Lower case, spaces and missing "=" padding are
/// all accepted, because people paste keys in every one of those shapes.
library;

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// TOTP secret: decodes a base32 key to its bytes. Throws
/// [FormatException] if a character is not base32 or the length is not a
/// whole number of bytes.
List<int> decodeBase32(String input) {
  final cleaned =
      input.replaceAll(RegExp(r'[\s-]'), '').replaceAll('=', '').toUpperCase();
  if (cleaned.isEmpty) throw const FormatException('empty key');

  var buffer = 0;
  var bits = 0;
  final out = <int>[];
  for (final char in cleaned.split('')) {
    final value = _alphabet.indexOf(char);
    if (value < 0) throw FormatException('not a base32 key', input);
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xFF);
    }
  }
  // Left-over bits must all be zero padding; anything else is a typo or a
  // truncated key, and a half byte would change every code.
  if (bits >= 5 || (buffer & ((1 << bits) - 1)) != 0) {
    throw FormatException('key is cut short', input);
  }
  return out;
}
