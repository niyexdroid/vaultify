import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/generator/generator.dart';

// Password generator tests: sets, guarantees, length limits, custom chars.
void main() {
  const none = GeneratorOptions(
    uppercase: false,
    lowercase: false,
    numbers: false,
    symbols: false,
  );

  bool onlyFrom(String password, String chars) =>
      password.split('').every(chars.contains);
  bool anyFrom(String password, String chars) =>
      password.split('').any(chars.contains);

  test('defaults: all four sets on, custom off, length 16', () {
    const o = GeneratorOptions();
    expect([o.uppercase, o.lowercase, o.numbers, o.symbols], everyElement(true));
    expect(o.custom, isFalse);
    expect(generatePassword(o), hasLength(16));
  });

  test('each set alone gives only its characters', () {
    final cases = {
      none.copyWith(uppercase: true): CharSets.uppercase,
      none.copyWith(lowercase: true): CharSets.lowercase,
      none.copyWith(numbers: true): CharSets.numbers,
      none.copyWith(symbols: true): CharSets.symbols,
    };
    cases.forEach((options, chars) {
      for (var i = 0; i < 50; i++) {
        expect(onlyFrom(generatePassword(options), chars), isTrue);
      }
    });
  });

  test('every selected set appears, even at length 4', () {
    const options = GeneratorOptions(length: 4);
    for (var i = 0; i < 500; i++) {
      final p = generatePassword(options);
      expect(p, hasLength(4));
      expect(anyFrom(p, CharSets.uppercase), isTrue, reason: 'upper');
      expect(anyFrom(p, CharSets.lowercase), isTrue, reason: 'lower');
      expect(anyFrom(p, CharSets.numbers), isTrue, reason: 'numbers');
      expect(anyFrom(p, CharSets.symbols), isTrue, reason: 'symbols');
    }
  });

  test('every selected set appears at many lengths, with custom too', () {
    const options = GeneratorOptions(custom: true, customChars: 'éß');
    for (var length = 5; length <= 40; length++) {
      for (var i = 0; i < 20; i++) {
        final p = generatePassword(options.copyWith(length: length));
        expect(p.runes.length, length);
        for (final set in options.selectedSets) {
          expect(set.any(p.contains), isTrue);
        }
      }
    }
  });

  test('guaranteed characters are not always at the start', () {
    // With only numbers + a 1-char custom set, the custom char must move.
    const options = GeneratorOptions(
      uppercase: false,
      lowercase: false,
      symbols: false,
      custom: true,
      customChars: 'x',
      length: 10,
    );
    final positions = <int>{};
    for (var i = 0; i < 200; i++) {
      positions.add(generatePassword(options).indexOf('x'));
    }
    expect(positions.length, greaterThan(3));
  });

  test('no set selected throws', () {
    expect(() => generatePassword(none),
        throwsA(isA<NoCharacterSetException>()));
    // Ticking Custom with nothing typed still counts as no set.
    expect(() => generatePassword(none.copyWith(custom: true)),
        throwsA(isA<NoCharacterSetException>()));
  });

  test('length is held to 4–128', () {
    expect(generatePassword(const GeneratorOptions(length: 1)), hasLength(4));
    expect(generatePassword(const GeneratorOptions(length: 128)),
        hasLength(128));
    expect(generatePassword(const GeneratorOptions(length: 500)),
        hasLength(128));
  });

  test('custom characters: duplicates ignored, capped at 256', () {
    expect(uniqueCustomChars('aabbca'), ['a', 'b', 'c']);
    final many = String.fromCharCodes(List.generate(400, (i) => 0x100 + i));
    expect(uniqueCustomChars(many), hasLength(256));
  });

  test('custom only gives only custom characters', () {
    final options = none.copyWith(custom: true, customChars: 'ab🔑');
    for (var i = 0; i < 50; i++) {
      final p = generatePassword(options);
      expect(p.runes.every((r) => 'ab🔑'.runes.contains(r)), isTrue);
    }
  });

  test('pool merges overlapping sets without double counting', () {
    final options = none.copyWith(numbers: true, custom: true, customChars: '12z');
    expect(options.pool.length, 11);
  });

  test('options round-trip through JSON and survive bad values', () {
    const options = GeneratorOptions(
      symbols: false,
      custom: true,
      customChars: '€',
      length: 30,
    );
    final back = GeneratorOptions.fromJson(options.toJson());
    expect(back.toJson(), options.toJson());

    final damaged = GeneratorOptions.fromJson({'length': 'big', 'upper': 1});
    expect(damaged.toJson(), const GeneratorOptions().toJson());
  });
}
