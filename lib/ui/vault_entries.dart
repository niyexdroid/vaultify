import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/cipher.dart';
import '../core/settings/settings.dart';
import '../core/vault/backup.dart';
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

  /// Backup export: all saved entries encrypted with [password], as the
  /// backup file's text.
  Future<String> exportBackup(String password) => ref
      .read(backupCodecProvider)
      .seal(
        ref.read(vaultRepositoryProvider).entries,
        password,
        now: ref.read(clockProvider)(),
      );

  /// Backup import: decrypts [file] with [password] and merges its entries
  /// into the vault. Throws [DecryptionFailedException] for a wrong
  /// password.
  Future<MergeResult> importBackup(BackupFile file, String password) async {
    final incoming = await ref.read(backupCodecProvider).open(file, password);
    final repo = ref.read(vaultRepositoryProvider);
    final result = await repo.importEntries(incoming);
    state = repo.entries;
    return result;
  }

  /// Saved screen, Delete: removes the entry and saves immediately.
  Future<void> delete(String id) async {
    final repo = ref.read(vaultRepositoryProvider);
    await repo.delete(id);
    state = repo.entries;
  }
}

/// Saved screen search and sort: entries whose name or username contains
/// [query] (ignoring case), A–Z by name or newest saved first.
List<Entry> searchAndSort(
    List<Entry> entries, String query, SortOrder order) {
  final q = query.trim().toLowerCase();
  final found = [
    for (final e in entries)
      if (q.isEmpty ||
          e.name.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q))
        e,
  ];
  int byName(Entry a, Entry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  found.sort(switch (order) {
    SortOrder.nameAsc => byName,
    SortOrder.newestFirst => (a, b) {
        final c = b.updated.compareTo(a.updated);
        return c != 0 ? c : byName(a, b);
      },
  });
  return found;
}
