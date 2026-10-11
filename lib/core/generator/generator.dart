import '../crypto/secure_random.dart';

/// Password generator: the character sets from SPEC.md "Generator".
abstract final class CharSets {
  static const String uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String numbers = '0123456789';
  // Kept to six symbols that most sites accept in passwords.
  static const String symbols = '!@#\$&%';
}

/// Password generator: thrown when no character type is selected (the UI
/// shows "Pick at least one character type").
class NoCharacterSetException implements Exception {
  const NoCharacterSetException();

  @override
  String toString() => 'NoCharacterSetException';
}

/// Password generator: options chosen on the Generator screen; also stored
/// in settings as the default generator settings.
class GeneratorOptions {
  const GeneratorOptions({
    this.uppercase = true,
    this.lowercase = true,
    this.numbers = true,
    this.symbols = true,
    this.custom = false,
    this.customChars = '',
    this.length = defaultLength,
  });

  // Password generator: length limits (slider 4–64, typed up to 128).
  static const int minLength = 4;
  static const int sliderMaxLength = 64;
  static const int maxLength = 128;
  static const int defaultLength = 16;
  static const int maxCustomChars = 256;

  final bool uppercase;
  final bool lowercase;
  final bool numbers;
  final bool symbols;
  final bool custom;
  final String customChars;
  final int length;

  GeneratorOptions copyWith({
    bool? uppercase,
    bool? lowercase,
    bool? numbers,
    bool? symbols,
    bool? custom,
    String? customChars,
    int? length,
  }) =>
      GeneratorOptions(
        uppercase: uppercase ?? this.uppercase,
        lowercase: lowercase ?? this.lowercase,
        numbers: numbers ?? this.numbers,
        symbols: symbols ?? this.symbols,
        custom: custom ?? this.custom,
        customChars: customChars ?? this.customChars,
        length: length ?? this.length,
      );

  /// Password generator: [length] kept within 4–128.
  int get clampedLength => length.clamp(minLength, maxLength);

  /// Password generator: the selected sets, each as a list of single
  /// characters. Custom characters lose duplicates and are capped at 256;
  /// an empty custom field counts as not selected.
  List<List<String>> get selectedSets {
    final sets = <List<String>>[
      if (uppercase) CharSets.uppercase.split(''),
      if (lowercase) CharSets.lowercase.split(''),
      if (numbers) CharSets.numbers.split(''),
      if (symbols) CharSets.symbols.split(''),
    ];
    if (custom) {
      final chars = uniqueCustomChars(customChars);
      if (chars.isNotEmpty) sets.add(chars);
    }
    return sets;
  }

  /// Password generator: every distinct character that can appear.
  Set<String> get pool => {for (final set in selectedSets) ...set};

  Map<String, Object> toJson() => {
        'uppercase': uppercase,
        'lowercase': lowercase,
        'numbers': numbers,
        'symbols': symbols,
        'custom': custom,
        'customChars': customChars,
        'length': length,
      };

  /// Password generator: reads saved defaults, falling back field by field
  /// so a damaged settings file never stops the app.
  factory GeneratorOptions.fromJson(Object? json) {
    const d = GeneratorOptions();
    if (json is! Map<String, Object?>) return d;
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final customChars = json['customChars'];
    final length = json['length'];
    return GeneratorOptions(
      uppercase: flag('uppercase', d.uppercase),
      lowercase: flag('lowercase', d.lowercase),
      numbers: flag('numbers', d.numbers),
      symbols: flag('symbols', d.symbols),
      custom: flag('custom', d.custom),
      customChars: customChars is String ? customChars : d.customChars,
      length: length is int ? length.clamp(minLength, maxLength) : d.length,
    );
  }
}

/// Password generator: custom characters with duplicates removed (first
/// occurrence kept), capped at 256. Works on whole characters (runes), so
/// emoji and other non-ASCII input stay intact.
List<String> uniqueCustomChars(String input) {
  final seen = <String>{};
  for (final rune in input.runes) {
    if (seen.length >= GeneratorOptions.maxCustomChars) break;
    seen.add(String.fromCharCode(rune));
  }
  return seen.toList();
}

/// Password generator: builds a password from [options].
///
/// Every selected set appears at least once, the rest is drawn from the
/// combined pool, then the whole thing is shuffled. If there are more sets
/// than characters (5 sets at length 4) a random choice of sets is
/// guaranteed. Throws [NoCharacterSetException] if nothing is selected.
String generatePassword(GeneratorOptions options) {
  final rng = secureRandom;
  final sets = options.selectedSets;
  if (sets.isEmpty) throw const NoCharacterSetException();
  final length = options.clampedLength;
  final pool = options.pool.toList();

  // Password generator: one guaranteed character from each selected set.
  final guaranteed = [...sets]..shuffle(rng);
  final chars = <String>[
    for (final set in guaranteed.take(length)) set[rng.nextInt(set.length)],
  ];

  // Password generator: fill the remaining length from the whole pool.
  while (chars.length < length) {
    chars.add(pool[rng.nextInt(pool.length)]);
  }

  // Password generator: secure shuffle so guaranteed characters aren't
  // always at the start.
  chars.shuffle(rng);
  return chars.join();
}
