import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'base32.dart';

/// TOTP codes: the hash an authenticator uses. Almost everything is SHA-1;
/// the others appear in some `otpauth://` links.
enum TotpAlgorithm {
  sha1,
  sha256,
  sha512;

  /// TOTP codes: reads "SHA1" / "sha256"... ; null for anything else.
  static TotpAlgorithm? fromName(Object? name) {
    if (name is! String) return null;
    final wanted = name.toLowerCase().replaceAll('-', '');
    for (final algorithm in values) {
      if (algorithm.name == wanted) return algorithm;
    }
    return null;
  }

  /// TOTP codes: the label used in `otpauth://` links.
  String get label => name.toUpperCase();

  MacAlgorithm get _hmac => switch (this) {
        sha1 => Hmac.sha1(),
        sha256 => Hmac.sha256(),
        sha512 => Hmac.sha512(),
      };
}

/// TOTP codes: one entry's two-factor secret and its settings, as stored
/// inside the encrypted payload. [issuer] and [account] are only labels
/// from the link, kept so the entry can show which account it belongs to.
class TotpSecret {
  TotpSecret({
    required List<int> key,
    this.digits = defaultDigits,
    this.period = defaultPeriod,
    this.algorithm = TotpAlgorithm.sha1,
    this.issuer = '',
    this.account = '',
  }) : key = List<int>.unmodifiable(key) {
    if (this.key.isEmpty) {
      throw const FormatException('two-factor key is empty');
    }
    if (digits < minDigits || digits > maxDigits) {
      throw FormatException('$digits digits is not supported');
    }
    if (period < minPeriod || period > maxPeriod) {
      throw FormatException('a $period second step is not supported');
    }
  }

  static const int defaultDigits = 6;
  static const int defaultPeriod = 30;
  static const int minDigits = 6;
  static const int maxDigits = 8;
  static const int minPeriod = 10;
  static const int maxPeriod = 120;

  /// The shared secret's bytes. Secret: never logged or written in plain.
  final List<int> key;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;
  final String issuer;
  final String account;

  /// TOTP codes: the account line shown under the code, like
  /// "GitHub · ada@example.com", or empty when the link carried no labels.
  String get label => switch ((issuer.isEmpty, account.isEmpty)) {
        (true, true) => '',
        (true, false) => account,
        (false, true) => issuer,
        (false, false) => '$issuer · $account',
      };

  Map<String, Object> toJson() => {
        'key': base32Encode(key),
        'digits': digits,
        'period': period,
        'algorithm': algorithm.name,
        'issuer': issuer,
        'account': account,
      };

  /// TOTP codes: reads a stored secret. Throws [FormatException] if the
  /// key is missing or the settings are out of range.
  factory TotpSecret.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('two-factor secret is not an object');
    }
    final key = json['key'];
    if (key is! String) {
      throw const FormatException('two-factor secret has no key');
    }
    final digits = json['digits'];
    final period = json['period'];
    final issuer = json['issuer'];
    final account = json['account'];
    return TotpSecret(
      key: decodeBase32(key),
      digits: digits is int ? digits : defaultDigits,
      period: period is int ? period : defaultPeriod,
      algorithm: TotpAlgorithm.fromName(json['algorithm']) ??
          TotpAlgorithm.sha1,
      issuer: issuer is String ? issuer : '',
      account: account is String ? account : '',
    );
  }

  // Deliberately no toString with the key, so a stray print or error
  // message can never leak the secret.
  @override
  String toString() => 'TotpSecret(${algorithm.name}, $digits digits)';
}

/// TOTP codes: the live code at [now], zero-padded to its digit count.
Future<String> totpCode(TotpSecret secret, DateTime now) async {
  final counter = totpStep(secret, now);
  final message = Uint8List(8);
  var left = counter;
  for (var i = 7; i >= 0; i--) {
    message[i] = left & 0xFF;
    left >>= 8;
  }
  final mac = await secret.algorithm._hmac
      .calculateMac(message, secretKey: SecretKey(secret.key));
  final bytes = mac.bytes;

  // RFC 4226 dynamic truncation: the last nibble picks where to read the
  // 31-bit number from, which is then cut to the digit count.
  final offset = bytes[bytes.length - 1] & 0x0F;
  final binary = ((bytes[offset] & 0x7F) << 24) |
      ((bytes[offset + 1] & 0xFF) << 16) |
      ((bytes[offset + 2] & 0xFF) << 8) |
      (bytes[offset + 3] & 0xFF);
  final modulus = _pow10(secret.digits);
  return (binary % modulus).toString().padLeft(secret.digits, '0');
}

/// TOTP countdown: whole seconds this code stays valid (1...period).
int totpSecondsLeft(TotpSecret secret, DateTime now) {
  final seconds = now.toUtc().millisecondsSinceEpoch / 1000;
  final used = seconds % secret.period;
  final left = (secret.period - used).ceil();
  return left < 1 ? 1 : left;
}

/// TOTP countdown: how much of the step is still left, 1.0 → 0.0, for the
/// progress ring beside the code.
double totpFractionLeft(TotpSecret secret, DateTime now) {
  final seconds = now.toUtc().millisecondsSinceEpoch / 1000;
  return 1 - (seconds % secret.period) / secret.period;
}

/// TOTP codes: the time step number — seconds since 1970 divided by the
/// step length. The code only changes when this number changes, which is
/// how the screen knows when to work out a new one.
int totpStep(TotpSecret secret, DateTime now) =>
    now.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ secret.period;

int _pow10(int digits) {
  var result = 1;
  for (var i = 0; i < digits; i++) {
    result *= 10;
  }
  return result;
}

/// TOTP secret: bytes → base32, for storing the key and for showing it as
/// a setup key. Pads to a whole number of base32 characters with "=".
String base32Encode(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | (byte & 0xFF);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(alphabet[(buffer >> bits) & 0x1F]);
    }
  }
  if (bits > 0) out.write(alphabet[(buffer << (5 - bits)) & 0x1F]);
  while (out.length % 8 != 0) {
    out.write('=');
  }
  return out.toString();
}
