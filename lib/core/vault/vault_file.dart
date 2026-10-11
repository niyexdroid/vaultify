import 'dart:convert';

import '../crypto/cipher.dart';
import '../crypto/kdf.dart';
import 'entry.dart';

/// Unlock secret: which kind of secret protects the vault.
enum UnlockType {
  pin,
  password;

  // Unlock secret: rules from SPEC.md "Security requirements".
  static const int minPinLength = 6;
  static const int maxPinLength = 12;
  static const int recommendedPinLength = 8;
  static const int minPasswordLength = 10;

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  /// Unlock secret: PIN is 6–12 digits; master password is 10+ characters.
  bool isValidSecret(String secret) => switch (this) {
        pin => _digitsOnly.hasMatch(secret) &&
            secret.length >= minPinLength &&
            secret.length <= maxPinLength,
        password => secret.runes.length >= minPasswordLength,
      };

  /// Unlock secret: reads "pin" / "password"; null for anything else.
  static UnlockType? fromName(Object? name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    return null;
  }
}

/// Vault file: thrown when `vault.vfy` can't be parsed (damaged, truncated
/// or not a Vaultify file). Unlike a wrong PIN, this is when the app offers
/// to restore from `vault.vfy.bak`.
class VaultFormatException implements Exception {
  const VaultFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'VaultFormatException: $reason';
}

/// Vault file: the on-disk JSON envelope, format version 1, as in SPEC.md
/// "Data model and storage". Everything here is safe to store in plain
/// text; the entries are only inside [sealed].
class VaultFile {
  const VaultFile({
    required this.unlock,
    required this.kdf,
    required this.sealed,
  });

  static const String formatName = 'vaultify';
  static const int formatVersion = 1;
  static const String cipherName = 'aes-256-gcm';

  final UnlockType unlock;
  final KdfParams kdf;
  final Sealed sealed;

  /// Vault file: serialises the envelope to the JSON text written to disk.
  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': formatName,
        'version': formatVersion,
        'unlock': unlock.name,
        'kdf': kdf.toJson(),
        'cipher': cipherName,
        'nonce': base64.encode(sealed.nonce),
        'ciphertext': base64.encode(sealed.cipherText),
      });

  /// Vault file: parses the envelope. Throws [VaultFormatException] for
  /// anything that isn't a readable version 1 Vaultify vault.
  static VaultFile decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?> || json['format'] != formatName) {
        throw const VaultFormatException('not a Vaultify vault');
      }
      if (json['version'] != formatVersion) {
        throw const VaultFormatException('unsupported vault version');
      }
      if (json['cipher'] != cipherName) {
        throw const VaultFormatException('unsupported cipher');
      }
      final unlock = UnlockType.fromName(json['unlock']);
      final nonce = json['nonce'];
      final cipherText = json['ciphertext'];
      if (unlock == null || nonce is! String || cipherText is! String) {
        throw const VaultFormatException('missing fields');
      }
      return VaultFile(
        unlock: unlock,
        kdf: KdfParams.fromJson(json['kdf']),
        sealed: Sealed(
          nonce: base64.decode(nonce),
          cipherText: base64.decode(cipherText),
        ),
      );
    } on VaultFormatException {
      rethrow;
    } on FormatException catch (e) {
      throw VaultFormatException(e.message);
    }
  }
}

/// Vault payload: entries → the plaintext bytes that get encrypted.
List<int> encodePayload(List<Entry> entries) => utf8.encode(jsonEncode({
      'entries': [for (final entry in entries) entry.toJson()],
    }));

/// Vault payload: decrypted bytes → entries. Throws [VaultFormatException]
/// if the payload is not the expected shape.
List<Entry> decodePayload(List<int> bytes) {
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, Object?> || json['entries'] is! List) {
      throw const VaultFormatException('payload has no entries');
    }
    return [for (final item in json['entries'] as List) Entry.fromJson(item)];
  } on VaultFormatException {
    rethrow;
  } on FormatException catch (e) {
    throw VaultFormatException(e.message);
  }
}
