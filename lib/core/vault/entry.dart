import '../crypto/secure_random.dart';
import '../totp/totp.dart';

/// Saved entry: one saved password, as stored inside the encrypted payload.
class Entry {
  const Entry({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.created,
    required this.updated,
    this.totp,
  });

  /// Saved entry: a new entry with a random 16-byte hex id and UTC dates.
  /// Throws [ArgumentError] if the name is empty or longer than 64.
  factory Entry.create({
    required String name,
    String username = '',
    required String password,
    required DateTime now,
    TotpSecret? totp,
  }) {
    final trimmed = name.trim();
    if (!isValidName(trimmed)) {
      throw ArgumentError.value(trimmed.length, 'name length');
    }
    final utc = now.toUtc();
    return Entry(
      id: randomHex(16),
      name: trimmed,
      username: username.trim(),
      password: password,
      created: utc,
      updated: utc,
      totp: totp,
    );
  }

  static const int maxNameLength = 64;

  /// Saved entry: name rule, 1–64 characters after trimming.
  static bool isValidName(String name) {
    final length = name.trim().runes.length;
    return length >= 1 && length <= maxNameLength;
  }

  final String id;
  final String name;
  final String username;
  final String password;
  final DateTime created;
  final DateTime updated;

  /// TOTP codes: this entry's two-factor secret, or null when it has none.
  final TotpSecret? totp;

  /// TOTP codes: whether this entry shows a live six-digit code.
  bool get hasTotp => totp != null;

  /// Passing [totp] sets the two-factor secret; [clearTotp] removes it.
  Entry copyWith({
    String? name,
    String? username,
    String? password,
    DateTime? updated,
    TotpSecret? totp,
    bool clearTotp = false,
  }) =>
      Entry(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        password: password ?? this.password,
        created: created,
        updated: (updated ?? this.updated).toUtc(),
        totp: clearTotp ? null : (totp ?? this.totp),
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'password': password,
        'created': created.toUtc().toIso8601String(),
        'updated': updated.toUtc().toIso8601String(),
        // TOTP codes: written only when the entry has a secret, so entries
        // saved before this feature keep exactly the shape they had.
        if (totp != null) 'totp': totp!.toJson(),
      };

  /// Saved entry: reads one entry from the decrypted payload. Throws
  /// [FormatException] if a field is missing or the wrong type.
  factory Entry.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('entry is not an object');
    }
    final id = json['id'];
    final name = json['name'];
    final username = json['username'];
    final password = json['password'];
    final created = json['created'];
    final updated = json['updated'];
    if (id is! String ||
        name is! String ||
        username is! String ||
        password is! String ||
        created is! String ||
        updated is! String) {
      throw const FormatException('entry has missing fields');
    }
    // TOTP codes: absent in entries saved before the feature existed.
    final totp = json['totp'];
    return Entry(
      id: id,
      name: name,
      username: username,
      password: password,
      created: DateTime.parse(created).toUtc(),
      updated: DateTime.parse(updated).toUtc(),
      totp: totp == null ? null : TotpSecret.fromJson(totp),
    );
  }

  // Deliberately no toString with field values, so a stray print or error
  // message can never leak a password.
  @override
  String toString() => 'Entry($id)';
}

/// Duplicate names: two names match ignoring case and surrounding spaces.
bool sameEntryName(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Backup import: a name from a file made to fit the 1–64 character rule
/// (trimmed; cut to 64; "Imported" if empty).
String cleanEntryName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Imported';
  final runes = trimmed.runes;
  if (runes.length <= Entry.maxNameLength) return trimmed;
  return String.fromCharCodes(runes.take(Entry.maxNameLength)).trimRight();
}

/// Duplicate names, "Keep both" and backup import: [name] if free,
/// otherwise the first free "Name (2)", "Name (3)"... The base is shortened
/// so the result still fits in 64 characters.
String nextFreeEntryName(String name, bool Function(String) taken) {
  final base = name.trim();
  if (!taken(base)) return base;
  for (var n = 2; ; n++) {
    final suffix = ' ($n)';
    final room = Entry.maxNameLength - suffix.length;
    final runes = base.runes.toList();
    final shortBase = runes.length > room
        ? String.fromCharCodes(runes.take(room)).trimRight()
        : base;
    final candidate = '$shortBase$suffix';
    if (!taken(candidate)) return candidate;
  }
}
