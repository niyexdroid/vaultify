import 'dart:convert';

/// Biometric unlock: what is kept in secure storage (Keychain / Keystore)
/// while fingerprint or face unlock is on: the vault key, and when the PIN
/// or password was last typed (for the 7-day rule).
///
/// The app only reads this after a successful fingerprint or face check.
class BiometricRecord {
  BiometricRecord({required this.key, required DateTime secretEnteredAt})
      : secretEnteredAt = secretEnteredAt.toUtc();

  /// The 32-byte vault key.
  final List<int> key;

  /// When the PIN or password was last typed (UTC).
  final DateTime secretEnteredAt;

  static const int _version = 1;

  /// Biometric unlock: text form for secure storage.
  String encode() => jsonEncode({
        'v': _version,
        'key': base64.encode(key),
        'secretEnteredAt': secretEnteredAt.toIso8601String(),
      });

  /// Biometric unlock: reads [encode]'s output. Missing or damaged text
  /// gives null, which simply means "type the PIN".
  static BiometricRecord? decode(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?> || json['v'] != _version) return null;
      final key = json['key'];
      final at = json['secretEnteredAt'];
      if (key is! String || at is! String) return null;
      final bytes = base64.decode(key);
      if (bytes.length != 32) return null;
      return BiometricRecord(key: bytes, secretEnteredAt: DateTime.parse(at));
    } on FormatException {
      return null;
    }
  }
}

/// Biometric unlock rules from SPEC.md: the PIN or password is still
/// required after 5 failed scans, after changing it, and at least every
/// 7 days.
class BiometricPolicy {
  const BiometricPolicy._();

  /// Biometric unlock: failed scans allowed before the PIN is required.
  static const int maxFailures = 5;

  /// Biometric unlock: the PIN or password must be typed at least this
  /// often.
  static const Duration maxAge = Duration(days: 7);

  /// Biometric unlock: whether a scan may open the vault right now. A
  /// clock set back before the last PIN entry also asks for the PIN, so
  /// changing the date can't stretch the 7 days.
  static bool allows({
    required BiometricRecord? record,
    required int failures,
    required DateTime now,
  }) {
    if (record == null || failures >= maxFailures) return false;
    final age = now.toUtc().difference(record.secretEnteredAt);
    return !age.isNegative && age < maxAge;
  }
}
