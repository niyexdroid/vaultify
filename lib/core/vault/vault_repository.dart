import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../crypto/cipher.dart';
import '../crypto/kdf.dart';
import '../totp/totp.dart';
import 'backup.dart';
import 'entry.dart';
import 'vault_file.dart';

/// Safe saving: the steps of a save, in order. Tests use this with
/// [VaultRepository.onSaveStep] to simulate a crash between steps.
enum SaveStep { writeTemp, backup, replace }

/// Vault repository: owns `vault.vfy` and, while unlocked, the vault key and
/// decrypted entries in memory. [lock] drops both.
///
/// Errors callers handle:
/// * [DecryptionFailedException]: wrong PIN or password (or tampered file).
/// * [VaultFormatException]: the file is damaged; offer [restoreFromBackup].
class VaultRepository {
  VaultRepository(
    this.directory, {
    KdfParams Function()? newKdfParams,
    this.onSaveStep,
  }) : _newKdfParams = newKdfParams ?? KdfParams.fresh;

  /// Folder holding the vault (the app support folder in the real app).
  final Directory directory;

  /// Test hook: called before each [SaveStep]. Throwing from it simulates
  /// the app being killed at that point of a save.
  final void Function(SaveStep step)? onSaveStep;

  /// Key derivation: makes params for new vaults and secret changes. Tests
  /// swap in cheaper settings; the app always uses [KdfParams.fresh].
  final KdfParams Function() _newKdfParams;

  static const String fileName = 'vault.vfy';

  File get vaultFile => File(_path(fileName));
  File get backupFile => File(_path('$fileName.bak'));
  File get tempFile => File(_path('$fileName.tmp'));

  String _path(String name) =>
      '${directory.path}${Platform.pathSeparator}$name';

  // Unlocked state: present only between unlock/create and lock.
  SecretKey? _key;
  KdfParams? _kdf;
  UnlockType? _unlockType;
  List<Entry> _entries = const [];

  bool get isUnlocked => _key != null;

  /// Saved entries (read-only view). Empty while locked.
  List<Entry> get entries => List.unmodifiable(_entries);

  /// Unlock secret type of the open vault.
  UnlockType? get unlockType => _unlockType;

  /// First launch check: true once a vault has been created.
  Future<bool> exists() => vaultFile.exists();

  Future<bool> backupExists() => backupFile.exists();

  /// Unlock screen: which secret to ask for, read from the plain header
  /// without needing the key.
  Future<UnlockType> readUnlockType() async =>
      VaultFile.decode(await vaultFile.readAsString()).unlock;

  /// First-launch setup: creates an empty vault protected by [secret] and
  /// leaves it unlocked. Refuses to overwrite an existing vault.
  Future<void> create(String secret, UnlockType type) async {
    if (!type.isValidSecret(secret)) {
      throw ArgumentError('secret does not meet the ${type.name} rules');
    }
    if (await exists()) {
      throw StateError('a vault already exists');
    }
    await directory.create(recursive: true);
    final kdf = _newKdfParams();
    final key = await deriveKey(secret, kdf);
    await _write(entries: const [], key: key, kdf: kdf, type: type);
    _setUnlocked(key, kdf, type, const []);
  }

  /// Unlock: derives the key from [secret] and decrypts the vault.
  /// Throws [DecryptionFailedException] for a wrong secret and
  /// [VaultFormatException] if the file is damaged.
  Future<void> unlock(String secret) async {
    final file = VaultFile.decode(await _readVault(vaultFile));
    final key = await deriveKey(secret, file.kdf);
    try {
      final entries = decodePayload(await decrypt(file.sealed, key));
      _setUnlocked(key, file.kdf, file.unlock, entries);
    } catch (_) {
      _destroy(key);
      rethrow;
    }
  }

  /// Biometric unlock: opens the vault with a key kept in secure storage
  /// instead of deriving it from the PIN. Throws
  /// [DecryptionFailedException] if the key no longer fits (e.g. the PIN
  /// changed) and [VaultFormatException] if the file is damaged.
  Future<void> unlockWithKey(List<int> keyBytes) async {
    final file = VaultFile.decode(await _readVault(vaultFile));
    final key = SecretKeyData(List<int>.of(keyBytes));
    try {
      final entries = decodePayload(await decrypt(file.sealed, key));
      _setUnlocked(key, file.kdf, file.unlock, entries);
    } catch (_) {
      _destroy(key);
      rethrow;
    }
  }

  /// Biometric unlock: a copy of the open vault's key, to keep in secure
  /// storage when fingerprint or face unlock is turned on.
  Future<List<int>> exportKey() async {
    _requireUnlocked();
    return List<int>.of(await _key!.extractBytes());
  }

  /// Lock: drops the key and decrypted entries from memory.
  void lock() {
    final key = _key;
    if (key != null) _destroy(key);
    _key = null;
    _kdf = null;
    _unlockType = null;
    _entries = const [];
  }

  /// Saved entries: adds [entry] and saves immediately.
  Future<void> add(Entry entry) =>
      _commit([..._entries, entry]);

  /// Saved entries: deletes the entry with [id] and saves immediately.
  Future<void> delete(String id) =>
      _commit([for (final e in _entries) if (e.id != id) e]);

  /// TOTP codes: puts [secret] on the entry with [id], or removes its
  /// two-factor secret when [secret] is null. Saves immediately. Does
  /// nothing if no entry has that id.
  Future<void> setTotp(String id, TotpSecret? secret) async {
    _requireUnlocked();
    if (!_entries.any((e) => e.id == id)) return;
    await _commit([
      for (final e in _entries)
        if (e.id == id)
          e.copyWith(totp: secret, clearTotp: secret == null)
        else
          e,
    ]);
  }

  /// Duplicate names: whether a saved entry already uses [name]
  /// (ignoring case and surrounding spaces).
  bool nameExists(String name) =>
      _entries.any((e) => _sameName(e.name, name));

  /// Duplicate names, "Keep both": the first free "Name (2)", "Name (3)"...
  /// Shortens the base so the result still fits in 64 characters.
  String nextFreeName(String name) => nextFreeEntryName(name, nameExists);

  /// Backup import: merges [incoming] into the vault (see [mergeEntries])
  /// and saves once if anything was added.
  Future<MergeResult> importEntries(List<Entry> incoming) async {
    _requireUnlocked();
    final result = mergeEntries(_entries, incoming);
    if (result.added > 0) await _commit(result.entries);
    return result;
  }

  /// Duplicate names, "Replace": overwrites the username and password of
  /// every entry named like [entry] (keeping the first one's id and
  /// created date), or adds it if there is none. Saves immediately.
  Future<void> replaceByName(Entry entry) async {
    final index = _entries.indexWhere((e) => _sameName(e.name, entry.name));
    if (index < 0) return add(entry);
    final replaced = _entries[index].copyWith(
      name: entry.name,
      username: entry.username,
      password: entry.password,
      updated: entry.updated,
    );
    await _commit([
      for (var i = 0; i < _entries.length; i++)
        if (i == index)
          replaced
        else if (!_sameName(_entries[i].name, entry.name))
          _entries[i],
    ]);
  }

  /// Change PIN or password: whether [secret] is the open vault's current
  /// PIN or password (derives it with the vault's salt and compares keys).
  Future<bool> checkSecret(String secret) async {
    _requireUnlocked();
    final candidate = await deriveKey(secret, _kdf!);
    try {
      return await keysMatch(candidate, _key!);
    } finally {
      _destroy(candidate);
    }
  }

  /// Change PIN or password: re-derives the key with a new salt and
  /// re-encrypts, so the old secret stops working.
  Future<void> changeSecret(String newSecret, UnlockType type) async {
    _requireUnlocked();
    if (!type.isValidSecret(newSecret)) {
      throw ArgumentError('secret does not meet the ${type.name} rules');
    }
    final kdf = _newKdfParams();
    final key = await deriveKey(newSecret, kdf);
    try {
      await _write(entries: _entries, key: key, kdf: kdf, type: type);
    } catch (_) {
      _destroy(key);
      rethrow;
    }
    final old = _key!;
    _setUnlocked(key, kdf, type, _entries);
    _destroy(old);
  }

  /// Damaged vault: replaces `vault.vfy` with the last good save from
  /// `vault.vfy.bak`, after checking the backup itself parses.
  Future<void> restoreFromBackup() async {
    VaultFile.decode(await _readVault(backupFile));
    await backupFile.copy(tempFile.path);
    await tempFile.rename(vaultFile.path);
  }

  // Saved entries: save the new list first, then update memory, so memory
  // never shows something that isn't on disk.
  Future<void> _commit(List<Entry> entries) async {
    _requireUnlocked();
    await _write(
      entries: entries,
      key: _key!,
      kdf: _kdf!,
      type: _unlockType!,
    );
    _entries = entries;
  }

  /// Safe saving: write `vault.vfy.tmp` and flush, copy the old vault to
  /// `.bak`, then rename the temp file over `vault.vfy`. Killed at any
  /// point, `vault.vfy` is either the old or the new complete file.
  Future<void> _write({
    required List<Entry> entries,
    required SecretKey key,
    required KdfParams kdf,
    required UnlockType type,
  }) async {
    final sealed = await encrypt(encodePayload(entries), key);
    final text = VaultFile(unlock: type, kdf: kdf, sealed: sealed).encode();

    onSaveStep?.call(SaveStep.writeTemp);
    await tempFile.writeAsString(text, flush: true);

    onSaveStep?.call(SaveStep.backup);
    if (await vaultFile.exists()) {
      await vaultFile.copy(backupFile.path);
    }

    onSaveStep?.call(SaveStep.replace);
    await tempFile.rename(vaultFile.path);
  }

  // Unlock: a missing or unreadable file is reported as damaged.
  Future<String> _readVault(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException {
      throw const VaultFormatException('vault file missing or unreadable');
    }
  }

  void _setUnlocked(
    SecretKey key,
    KdfParams kdf,
    UnlockType type,
    List<Entry> entries,
  ) {
    _key = key;
    _kdf = kdf;
    _unlockType = type;
    _entries = entries;
  }

  void _requireUnlocked() {
    if (!isUnlocked) throw StateError('vault is locked');
  }

  // Lock: zero the key bytes where the key type allows it.
  static void _destroy(SecretKey key) => destroyKey(key);

  static bool _sameName(String a, String b) => sameEntryName(a, b);
}
