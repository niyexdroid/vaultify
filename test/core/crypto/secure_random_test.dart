import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/secure_random.dart';

// Secure randomness tests.
void main() {
  test('randomBytes gives the requested length and varies', () {
    expect(randomBytes(16), hasLength(16));
    expect(randomBytes(16), isNot(equals(randomBytes(16))));
  });

  test('randomHex gives two lowercase hex digits per byte', () {
    final hex = randomHex(16);
    expect(hex, matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
