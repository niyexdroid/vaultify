import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/vault/entry.dart';
import 'providers.dart';
import 'session.dart';

/// Saved entries: the open vault's entries for the UI. Rebuilds on unlock
/// and lock (empty while locked); every change is saved to disk first.
final vaultEntriesProvider =
    NotifierProvider<VaultEntries, List<Entry>>(VaultEntries.new);

class VaultEntries extends Notifier<List<Entry>> {
  @override
  List<Entry> build() {
    ref.watch(sessionProvider.select((s) => s.value?.phase));
    return ref.read(vaultRepositoryProvider).entries;
  }

  /// Duplicate names: whether [name] is already used (ignoring case).
  bool nameExists(String name) =>
      ref.read(vaultRepositoryProvider).nameExists(name);

  /// Save to vault: adds a new entry. With [keepBoth] a used name gets
  /// " (2)", " (3)"... instead.
  Future<void> add({
    required String name,
    required String username,
    required String password,
    bool keepBoth = false,
  }) async {
    final repo = ref.read(vaultRepositoryProvider);
    await repo.add(Entry.create(
      name: keepBoth ? repo.nextFreeName(name) : name,
      username: username,
      password: password,
      now: ref.read(clockProvider)(),
    ));
    state = repo.entries;
  }

  /// Duplicate names, "Replace": overwrites the entry with the same name.
  Future<void> replace({
    required String name,
    required String username,
    required String password,
  }) async {
    final repo = ref.read(vaultRepositoryProvider);
    await repo.replaceByName(Entry.create(
      name: name,
      username: username,
      password: password,
      now: ref.read(clockProvider)(),
    ));
    state = repo.entries;
  }
}
