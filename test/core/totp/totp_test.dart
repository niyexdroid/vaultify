import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/totp/base32.dart';
import 'package:vaultify/core/totp/otpauth.dart';
import 'package:vaultify/core/totp/totp.dart';

// TOTP codes: the RFC 6238 test secret, as a base32 setup key. It is the
// ASCII text "12345678901234567890".
const String _sha1Key = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

// TOTP codes: the RFC 6238 seeds are that text repeated to 20, 32 and 64
// bytes, one per hash. Taken as raw bytes so the vectors don't lean on
// Vaultify's own base32 code.
List<int> _seed(int bytes) =>
    utf8.encode('1234567890' * (bytes ~/ 10 + 1)).sublist(0, bytes);

DateTime at(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

void main() {
  group('base32', () {
    test('decodes the RFC 4648 secret to its ASCII bytes', () {
      expect(utf8.decode(decodeBase32(_sha1Key)), '12345678901234567890');
    });

    test('accepts lower case, spaces and missing padding', () {
      expect(decodeBase32('gezd gnbv gy3t qojq'),
          decodeBase32('GEZDGNBVGY3TQOJQ'));
    });

    test('rejects characters that are not base32', () {
      expect(() => decodeBase32('ABCD1EFG'), throwsFormatException);
      expect(() => decodeBase32('!!!!'), throwsFormatException);
      expect(() => decodeBase32(''), throwsFormatException);
    });

    test('rejects a key cut short mid-byte', () {
      expect(() => decodeBase32('A'), throwsFormatException);
      expect(() => decodeBase32('ABC'), throwsFormatException);
    });

    test('round-trips bytes through base32', () {
      final bytes = [0, 1, 2, 250, 251, 252, 253, 254, 255];
      expect(decodeBase32(base32Encode(bytes)), bytes);
    });
  });

  // TOTP codes: the published RFC 6238 vectors are the check that a code
  // Vaultify shows is the same one any other authenticator shows.
  group('codes match the RFC 6238 vectors', () {
    Future<void> check(
      List<int> key,
      TotpAlgorithm algorithm,
      int seconds,
      String expected,
    ) async {
      final secret =
          TotpSecret(key: key, digits: 8, algorithm: algorithm);
      expect(await totpCode(secret, at(seconds)), expected);
    }

    test('SHA-1', () async {
      final key = _seed(20);
      await check(key, TotpAlgorithm.sha1, 59, '94287082');
      await check(key, TotpAlgorithm.sha1, 1111111109, '07081804');
      await check(key, TotpAlgorithm.sha1, 1111111111, '14050471');
      await check(key, TotpAlgorithm.sha1, 1234567890, '89005924');
      await check(key, TotpAlgorithm.sha1, 2000000000, '69279037');
      await check(key, TotpAlgorithm.sha1, 20000000000, '65353130');
    });

    test('SHA-256', () async {
      final key = _seed(32);
      await check(key, TotpAlgorithm.sha256, 59, '46119246');
      await check(key, TotpAlgorithm.sha256, 1111111109, '68084774');
      await check(key, TotpAlgorithm.sha256, 2000000000, '90698825');
    });

    test('SHA-512', () async {
      final key = _seed(64);
      await check(key, TotpAlgorithm.sha512, 59, '90693936');
      await check(key, TotpAlgorithm.sha512, 1111111109, '25091201');
      await check(key, TotpAlgorithm.sha512, 2000000000, '38618901');
    });

    test('the base32 setup key decodes to the SHA-1 seed', () {
      expect(decodeBase32(_sha1Key), _seed(20));
    });
  });

  group('codes', () {
    final secret = TotpSecret(key: decodeBase32(_sha1Key));

    test('are six digits by default, keeping leading zeros', () async {
      final code = await totpCode(secret, at(1111111109));
      expect(code, '081804');
      expect(code.length, 6);
    });

    test('stay the same for the whole 30 second step', () async {
      final start = await totpCode(secret, at(1111111080));
      expect(await totpCode(secret, at(1111111109)), start);
      expect(await totpCode(secret, at(1111111110)), isNot(start));
    });

    test('do not depend on the time zone of the clock', () async {
      final utc = await totpCode(secret, at(1234567890));
      expect(await totpCode(secret, at(1234567890).toLocal()), utc);
    });

    test('refuse a key or settings Vaultify cannot use', () {
      expect(() => TotpSecret(key: const []), throwsFormatException);
      expect(() => TotpSecret(key: const [1, 2], digits: 9),
          throwsFormatException);
      expect(() => TotpSecret(key: const [1, 2], digits: 5),
          throwsFormatException);
      expect(() => TotpSecret(key: const [1, 2], period: 0),
          throwsFormatException);
      expect(() => TotpSecret(key: const [1, 2], period: 300),
          throwsFormatException);
    });

    test('never put the key in toString', () {
      expect(TotpSecret(key: decodeBase32(_sha1Key)).toString(),
          isNot(contains('GEZD')));
    });
  });

  group('countdown', () {
    final secret = TotpSecret(key: decodeBase32(_sha1Key));

    test('counts whole seconds down to the next step', () {
      expect(totpSecondsLeft(secret, at(1111111080)), 30);
      expect(totpSecondsLeft(secret, at(1111111081)), 29);
      expect(totpSecondsLeft(secret, at(1111111109)), 1);
      expect(totpSecondsLeft(secret, at(1111111110)), 30);
    });

    test('fraction left runs from 1 down towards 0', () {
      expect(totpFractionLeft(secret, at(1111111080)), 1.0);
      expect(totpFractionLeft(secret, at(1111111095)), 0.5);
      expect(totpFractionLeft(secret, at(1111111109)), closeTo(1 / 30, 0.001));
    });
  });

  group('stored secret', () {
    test('round-trips through JSON', () {
      final secret = TotpSecret(
        key: decodeBase32(_sha1Key),
        digits: 8,
        period: 60,
        algorithm: TotpAlgorithm.sha256,
        issuer: 'GitHub',
        account: 'ada@example.com',
      );
      final copy = TotpSecret.fromJson(jsonDecode(jsonEncode(secret.toJson())));
      expect(copy.key, secret.key);
      expect(copy.digits, 8);
      expect(copy.period, 60);
      expect(copy.algorithm, TotpAlgorithm.sha256);
      expect(copy.issuer, 'GitHub');
      expect(copy.account, 'ada@example.com');
      expect(copy.label, 'GitHub · ada@example.com');
    });

    test('fills in defaults for a secret stored without settings', () {
      final copy = TotpSecret.fromJson({'key': _sha1Key});
      expect(copy.digits, 6);
      expect(copy.period, 30);
      expect(copy.algorithm, TotpAlgorithm.sha1);
      expect(copy.label, '');
    });

    test('refuses a secret with no key', () {
      expect(() => TotpSecret.fromJson({'digits': 6}), throwsFormatException);
      expect(() => TotpSecret.fromJson('nope'), throwsFormatException);
    });
  });

  group('adding a secret', () {
    test('reads a plain setup key', () {
      final secret = parseTotpInput(' gezd gnbv gy3t qojq ');
      expect(secret.key, decodeBase32('GEZDGNBVGY3TQOJQ'));
      expect(secret.digits, 6);
      expect(secret.label, '');
    });

    test('reads an otpauth link with labels and settings', () {
      final secret = parseTotpInput(
          'otpauth://totp/GitHub:ada@example.com?secret=$_sha1Key'
          '&issuer=GitHub&digits=8&period=60&algorithm=SHA256');
      expect(secret.key, decodeBase32(_sha1Key));
      expect(secret.digits, 8);
      expect(secret.period, 60);
      expect(secret.algorithm, TotpAlgorithm.sha256);
      expect(secret.issuer, 'GitHub');
      expect(secret.account, 'ada@example.com');
    });

    test('takes the issuer from the label when the field is missing', () {
      final secret = parseTotpInput(
          'otpauth://totp/Example%3Aada%40example.com?secret=$_sha1Key');
      expect(secret.issuer, 'Example');
      expect(secret.account, 'ada@example.com');
    });

    test('accepts a link with only an account name', () {
      final secret = parseTotpInput('otpauth://totp/ada?secret=$_sha1Key');
      expect(secret.issuer, '');
      expect(secret.account, 'ada');
      expect(secret.label, 'ada');
    });

    test('says what is wrong in plain words', () {
      String why(String input) {
        try {
          parseTotpInput(input);
        } on TotpInputException catch (e) {
          return e.message;
        }
        return 'no error';
      }

      expect(why(''), contains('Paste'));
      expect(why('not a key! 189'), contains('setup key'));
      expect(why('otpauth://hotp/x?secret=$_sha1Key'), contains('HOTP'));
      expect(why('otpauth://totp/x'), contains('no secret'));
      expect(why('otpauth://totp/x?secret=!!!'), contains("couldn't be read"));
      expect(why('otpauth://totp/x?secret=$_sha1Key&digits=10'),
          contains('6 to 8'));
      expect(why('otpauth://totp/x?secret=$_sha1Key&period=5'),
          contains('10 to 120'));
    });

    test('ignores settings it cannot read and uses the defaults', () {
      final secret = parseTotpInput(
          'otpauth://totp/x?secret=$_sha1Key&digits=abc&period=');
      expect(secret.digits, 6);
      expect(secret.period, 30);
    });
  });
}
