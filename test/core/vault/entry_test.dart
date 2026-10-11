import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/vault/entry.dart';

// Saved entry tests: creation rules and JSON.
void main() {
  final now = DateTime.utc(2026, 10, 11, 12);

  test('create trims, assigns a 16-byte hex id and UTC dates', () {
    final e = Entry.create(
      name: '  Gmail ',
      username: ' me@example.com ',
      password: 'p',
      now: now.toLocal(),
    );
    expect(e.name, 'Gmail');
    expect(e.username, 'me@example.com');
    expect(e.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(e.created.isUtc, isTrue);
    expect(e.created, now);
    expect(e.updated, now);
  });

  test('names must be 1–64 characters', () {
    expect(Entry.isValidName(''), isFalse);
    expect(Entry.isValidName('   '), isFalse);
    expect(Entry.isValidName('a' * 64), isTrue);
    expect(Entry.isValidName('a' * 65), isFalse);
    expect(() => Entry.create(name: ' ', password: 'p', now: now),
        throwsArgumentError);
  });

  test('round-trips through JSON', () {
    final e = Entry.create(name: 'Bank', password: 'x!9', now: now);
    final back = Entry.fromJson(e.toJson());
    expect(back.toJson(), e.toJson());
  });

  test('missing fields are rejected', () {
    expect(() => Entry.fromJson({'id': 'a'}), throwsFormatException);
    expect(() => Entry.fromJson('nope'), throwsFormatException);
  });

  test('toString never contains the password', () {
    final e = Entry.create(name: 'Bank', password: 'secret-value', now: now);
    expect(e.toString(), isNot(contains('secret-value')));
  });
}
