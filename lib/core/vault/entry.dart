import '../crypto/secure_random.dart';

/// Saved entry: one saved password, as stored inside the encrypted payload.
class Entry {
  const Entry({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.created,
    required this.updated,
  });

  /// Saved entry: a new entry with a random 16-byte hex id and UTC dates.
  /// Throws [ArgumentError] if the name is empty or longer than 64.
  factory Entry.create({
    required String name,
    String username = '',
    required String password,
    required DateTime now,
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

  Entry copyWith({
    String? name,
    String? username,
    String? password,
    DateTime? updated,
  }) =>
      Entry(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        password: password ?? this.password,
        created: created,
        updated: (updated ?? this.updated).toUtc(),
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'password': password,
        'created': created.toUtc().toIso8601String(),
        'updated': updated.toUtc().toIso8601String(),
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
    return Entry(
      id: id,
      name: name,
      username: username,
      password: password,
      created: DateTime.parse(created).toUtc(),
      updated: DateTime.parse(updated).toUtc(),
    );
  }

  // Deliberately no toString with field values, so a stray print or error
  // message can never leak a password.
  @override
  String toString() => 'Entry($id)';
}
