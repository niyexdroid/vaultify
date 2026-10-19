import 'base32.dart';
import 'totp.dart';

/// Add two-factor code: thrown when pasted text or a scanned QR code isn't
/// a usable TOTP secret. [message] is written for the screen, so it can be
/// shown as is.
class TotpInputException implements Exception {
  const TotpInputException(this.message);

  final String message;

  @override
  String toString() => 'TotpInputException: $message';
}

/// Add two-factor code: reads either an `otpauth://totp/...` link (from a
/// QR code or pasted) or a plain base32 setup key. Throws
/// [TotpInputException] with a message for the screen.
TotpSecret parseTotpInput(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    throw const TotpInputException('Paste a setup key or otpauth:// link.');
  }
  if (text.toLowerCase().startsWith('otpauth')) return _parseLink(text);
  // A plain setup key: everything else comes from the defaults.
  try {
    return TotpSecret(key: decodeBase32(text));
  } on FormatException {
    throw const TotpInputException(
        "That doesn't look like a setup key. Keys are letters A–Z and "
        'digits 2–7.');
  }
}

// Add two-factor code: otpauth://totp/Issuer:account?secret=...&issuer=...
// &digits=6&period=30&algorithm=SHA1
TotpSecret _parseLink(String text) {
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    throw const TotpInputException("That link couldn't be read.");
  }
  if (uri.scheme.toLowerCase() != 'otpauth') {
    throw const TotpInputException(
        'Only otpauth:// links can be added.');
  }
  // Counter-based codes (HOTP) are a different scheme Vaultify doesn't do.
  if (uri.host.toLowerCase() == 'hotp') {
    throw const TotpInputException(
        'That is a counter-based (HOTP) code, which Vaultify does not '
        'support.');
  }
  if (uri.host.toLowerCase() != 'totp') {
    throw const TotpInputException('That link is not a TOTP code.');
  }

  final query = uri.queryParameters;
  final key = query['secret'];
  if (key == null || key.trim().isEmpty) {
    throw const TotpInputException('That link has no secret in it.');
  }

  // Label: the path is "Issuer:account" or just "account"; the issuer
  // query parameter wins when both are there.
  final label = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
  var issuer = query['issuer']?.trim() ?? '';
  var account = label;
  final colon = label.indexOf(':');
  if (colon >= 0) {
    if (issuer.isEmpty) issuer = label.substring(0, colon).trim();
    account = label.substring(colon + 1).trim();
  }

  try {
    return TotpSecret(
      key: decodeBase32(key),
      digits: _number(query['digits'], TotpSecret.defaultDigits),
      period: _number(query['period'], TotpSecret.defaultPeriod),
      algorithm: TotpAlgorithm.fromName(query['algorithm']) ??
          TotpAlgorithm.sha1,
      issuer: issuer,
      account: account,
    );
  } on FormatException catch (e) {
    throw TotpInputException(_sayWhy(e));
  }
}

int _number(String? value, int fallback) {
  if (value == null || value.trim().isEmpty) return fallback;
  return int.tryParse(value.trim()) ?? fallback;
}

// Add two-factor code: turn the core's reason into one screen sentence.
String _sayWhy(FormatException e) {
  final reason = e.message;
  if (reason.contains('digits')) {
    return 'Vaultify supports 6 to 8 digit codes only.';
  }
  if (reason.contains('second step')) {
    return 'Vaultify supports steps of 10 to 120 seconds only.';
  }
  return "That link's secret couldn't be read.";
}
