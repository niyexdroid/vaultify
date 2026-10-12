import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/crypto/kdf.dart';
import 'package:vaultify/core/crypto/secure_random.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/core/vault/vault_repository.dart';
import 'package:vaultify/ui/providers.dart';
import 'package:vaultify/ui/session.dart';
import 'package:vaultify/ui/vault_entries.dart';

// Saved entries tests: a saved password is written to the real encrypted
// vault file and survives a restart (M4); delete, search and sort (M5).
void main() {
  const pin = '12345678';
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vaultify_entries_');
  });
  tearDown(() => dir.delete(recursive: true));

  // A fresh container is like a fresh app start: nothing kept in memory.
  ProviderContainer start() {
    final container = ProviderContainer(overrides: [
      appDirectoryProvider.overrideWithValue(dir),
      vaultRepositoryProvider.overrideWithValue(VaultRepository(
        dir,
        newKdfParams: () =>
            KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1),
      )),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('a saved password survives a restart', () async {
    final first = start();
    await first.read(sessionProvider.future);
    await first.read(sessionProvider.notifier).create(pin, UnlockType.pin);
    await first.read(vaultEntriesProvider.notifier).add(
        name: 'Gmail', username: 'me', password: 'generated-pw');
    expect(first.read(vaultEntriesProvider), hasLength(1));
    first.dispose();

    final second = start();
    expect((await second.read(sessionProvider.future)).phase, Phase.locked);
    expect(second.read(vaultEntriesProvider), isEmpty);
    await second.read(sessionProvider.notifier).unlock(pin);
    final entries = second.read(vaultEntriesProvider);
    expect(entries.single.name, 'Gmail');
    expect(entries.single.username, 'me');
    expect(entries.single.password, 'generated-pw');

    // Locking empties the list again.
    second.read(sessionProvider.notifier).lock();
    expect(second.read(vaultEntriesProvider), isEmpty);
  });

  test('a deleted entry stays deleted after a restart', () async {
    final first = start();
    await first.read(sessionProvider.future);
    await first.read(sessionProvider.notifier).create(pin, UnlockType.pin);
    final entries = first.read(vaultEntriesProvider.notifier);
    await entries.add(name: 'Gmail', username: '', password: 'a');
    await entries.add(name: 'Bank', username: '', password: 'b');
    final gmail =
        first.read(vaultEntriesProvider).firstWhere((e) => e.name == 'Gmail');
    await entries.delete(gmail.id);
    expect(first.read(vaultEntriesProvider).map((e) => e.name), ['Bank']);
    first.dispose();

    final second = start();
    await second.read(sessionProvider.future);
    await second.read(sessionProvider.notifier).unlock(pin);
    expect(second.read(vaultEntriesProvider).map((e) => e.name), ['Bank']);
  });

  test('sort order is remembered after a restart', () async {
    final first = start();
    await first.read(sessionProvider.future);
    await first.read(sessionProvider.notifier).create(pin, UnlockType.pin);
    await first
        .read(sessionProvider.notifier)
        .setSortOrder(SortOrder.newestFirst);
    first.dispose();

    final second = start();
    final session = await second.read(sessionProvider.future);
    expect(session.settings.sortOrder, SortOrder.newestFirst);
  });

  // Saved search and sort: the pure helper behind the Saved screen.
  group('Saved search and sort', () {
    Entry entry(String name, String username, int day) => Entry.create(
        name: name,
        username: username,
        password: 'x',
        now: DateTime.utc(2026, 1, day));
    final list = [
      entry('gmail', 'me@mail.com', 3),
      entry('Bank', 'ada', 1),
      entry('Amazon', '', 2),
    ];
    List<String> names(List<Entry> l) => [for (final e in l) e.name];

    test('A–Z ignores case', () {
      expect(names(searchAndSort(list, '', SortOrder.nameAsc)),
          ['Amazon', 'Bank', 'gmail']);
    });

    test('newest first uses the saved date', () {
      expect(names(searchAndSort(list, '', SortOrder.newestFirst)),
          ['gmail', 'Amazon', 'Bank']);
    });

    test('search matches name or username, ignoring case', () {
      expect(names(searchAndSort(list, 'BAN', SortOrder.nameAsc)), ['Bank']);
      expect(names(searchAndSort(list, 'ada', SortOrder.nameAsc)), ['Bank']);
      expect(
          names(searchAndSort(list, 'mail', SortOrder.nameAsc)), ['gmail']);
      expect(searchAndSort(list, 'zzz', SortOrder.nameAsc), isEmpty);
    });
  });
}
