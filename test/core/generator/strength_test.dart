import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/generator/strength.dart';

// Strength meter tests: bit formula and label thresholds.
void main() {
  test('labels match the bit thresholds', () {
    expect(Strength.fromBits(0), Strength.weak);
    expect(Strength.fromBits(39.9), Strength.weak);
    expect(Strength.fromBits(40), Strength.fair);
    expect(Strength.fromBits(59.9), Strength.fair);
    expect(Strength.fromBits(60), Strength.strong);
    expect(Strength.fromBits(79.9), Strength.strong);
    expect(Strength.fromBits(80), Strength.veryStrong);
    expect(Strength.veryStrong.label, 'Very strong');
  });

  test('bits = length × log2(pool size)', () {
    expect(entropyBits(16, 2), closeTo(16, 1e-9));
    expect(entropyBits(10, 1024), closeTo(100, 1e-9));
    expect(entropyBits(0, 90), 0);
    expect(entropyBits(10, 1), 0);
  });

  test('bar is full at 80 bits', () {
    expect(strengthFill(40), 0.5);
    expect(strengthFill(120), 1.0);
  });

  test('pool estimate for pasted passwords counts each set used', () {
    expect(estimatePoolSize('abc'), 26);
    expect(estimatePoolSize('aB3'), 62);
    expect(estimatePoolSize('aB3!'), 62 + 27);
    expect(estimatePoolSize('aé€'), 26 + 2);
    expect(estimatePoolSize(''), 0);
  });

  test('default 16-character password is very strong', () {
    // 16 × log2(89) ≈ 103.6 bits.
    expect(Strength.fromBits(passwordBits('aB3!aB3!aB3!aB3!')),
        Strength.veryStrong);
    expect(Strength.fromBits(passwordBits('password')), Strength.weak);
  });
}
