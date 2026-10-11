import 'dart:math';

import 'generator.dart';

/// Strength meter: the four labels and their bit thresholds from SPEC.md.
enum Strength {
  weak,
  fair,
  strong,
  veryStrong;

  /// Strength meter: under 40 weak, 40–59 fair, 60–79 strong, 80+ very strong.
  static Strength fromBits(double bits) {
    if (bits < 40) return weak;
    if (bits < 60) return fair;
    if (bits < 80) return strong;
    return veryStrong;
  }

  /// Strength meter: sentence-case label shown beside the bar.
  String get label => switch (this) {
        weak => 'Weak',
        fair => 'Fair',
        strong => 'Strong',
        veryStrong => 'Very strong',
      };
}

/// Strength meter: bits = length × log2(pool size).
double entropyBits(int length, int poolSize) {
  if (length <= 0 || poolSize <= 1) return 0;
  return length * log(poolSize) / ln2;
}

/// Strength meter: how full the bar is, 0.0–1.0 (full at 80 bits).
double strengthFill(double bits) => (bits / 80).clamp(0.0, 1.0);

/// Strength meter: estimates the pool of a typed or pasted password from the
/// kinds of characters in it. Each standard set used adds its full size;
/// characters outside them each add one.
int estimatePoolSize(String password) {
  var hasUpper = false, hasLower = false, hasNumber = false, hasSymbol = false;
  final others = <int>{};
  for (final rune in password.runes) {
    final ch = String.fromCharCode(rune);
    if (CharSets.uppercase.contains(ch)) {
      hasUpper = true;
    } else if (CharSets.lowercase.contains(ch)) {
      hasLower = true;
    } else if (CharSets.numbers.contains(ch)) {
      hasNumber = true;
    } else if (CharSets.symbols.contains(ch)) {
      hasSymbol = true;
    } else {
      others.add(rune);
    }
  }
  return (hasUpper ? CharSets.uppercase.length : 0) +
      (hasLower ? CharSets.lowercase.length : 0) +
      (hasNumber ? CharSets.numbers.length : 0) +
      (hasSymbol ? CharSets.symbols.length : 0) +
      others.length;
}

/// Strength meter: bits for whatever is in the password box (generated or
/// pasted), counting whole characters rather than UTF-16 units.
double passwordBits(String password) =>
    entropyBits(password.runes.length, estimatePoolSize(password));
