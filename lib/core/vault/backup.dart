import 'dart:convert';

import '../crypto/cipher.dart';
import '../crypto/kdf.dart';
import '../crypto/secure_random.dart';
import 'entry.dart';
import 'vault_file.dart';

/// Backup export/import: an encrypted copy of the saved entries, protected
/// by its own backup password (not the daily PIN), that the user saves
/// wherever they like and can load into any Vaultify vault.
///
/// File format, version 1 (JSON), same layout as the vault file:
/// ```json
/// { "format": "vaultify-backup", "version": 1, "exported": "<UTC ISO>",
///   "kdf": {...}, "cipher": "aes-256-gcm", "nonce": "...",
///   "ciphertext": "..." }
/// ```
/// The decrypted payload is the same `{ "entries": [...] }` as the vault.
class BackupFile {
  const BackupFile({
    required this.exported,
    required this.kdf,
    required this.sealed,
  });

  static const String formatName = 'vaultify-backup';
  static const int formatVersion = 1;

  /// Backup export: file extension, without the dot.
  static const String extension = 'vaultify';

  /// Backup import: Argon2 limits for files from elsewhere, so a doctored
  /// file can't make the app use gigabytes of memory or run for minutes.
  static const int maxMemoryKiB = 262144; // 256 MiB
  static const int maxIterations = 10;
  static const int maxParallelism = 4;

  final DateTime exported;
  final KdfParams kdf;
  final Sealed sealed;

  /// Backup export: serialises the envelope to the JSON text of the file.
  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': formatName,
    'version': formatVersion,
    'exported': exported.toUtc().toIso8601String(),
    'kdf': kdf.toJson(),
    'cipher': VaultFile.cipherName,
    'nonce': base64.encode(sealed.nonce),
    'ciphertext': base64.encode(sealed.cipherText),
  });

  /// Backup import: parses a backup file. Throws [VaultFormatException] for
  /// anything that isn't a readable version 1 Vaultify backup (including a
  /// vault.vfy picked by mistake).
  static BackupFile decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?> || json['format'] != formatName) {
        throw const VaultFormatException('not a Vaultify backup');
      }
      if (json['version'] != formatVersion) {
        throw const VaultFormatException('unsupported backup version');
      }
      if (json['cipher'] != VaultFile.cipherName) {
        throw const VaultFormatException('unsupported cipher');
      }
      final exported = json['exported'];
      final nonce = json['nonce'];
      final cipherText = json['ciphertext'];
      if (exported is! String || nonce is! String || cipherText is! String) {
        throw const VaultFormatException('missing fields');
      }
      final kdf = KdfParams.fromJson(json['kdf']);
      if (kdf.memoryKiB > maxMemoryKiB ||
          kdf.iterations > maxIterations ||
          kdf.parallelism > maxParallelism) {
        throw const VaultFormatException('kdf settings too large');
      }
      return BackupFile(
        exported: DateTime.parse(exported).toUtc(),
        kdf: kdf,
        sealed: Sealed(
          nonce: base64.decode(nonce),
          cipherText: base64.decode(cipherText),
        ),
      );
    } on VaultFormatException {
      rethrow;
    } on FormatException catch (e) {
      throw VaultFormatException(e.message);
    }
  }
}

/// Backup password: at least 12 characters. Longer than the vault's
/// password rule because the file leaves the device and could be attacked
/// offline, with no wrong-attempt waits.
const int minBackupPasswordLength = 12;

bool isValidBackupPassword(String password) =>
    password.runes.length >= minBackupPasswordLength;

/// Backup export: suggested file name, e.g. `vaultify-backup-2026-10-12.vaultify`.
String backupFileName(DateTime now) {
  final d = now.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'vaultify-backup-${d.year}-${two(d.month)}-${two(d.day)}'
      '.${BackupFile.extension}';
}

/// Backup export/import: turns entries into backup file text and back.
/// Swappable so widget tests can skip Argon2.
class BackupCodec {
  const BackupCodec({KdfParams Function()? newKdfParams})
    : _newKdfParams = newKdfParams ?? strongKdfParams;

  final KdfParams Function() _newKdfParams;

  /// Backup export: Argon2id at 64 MiB and 3 passes (stronger than the
  /// vault's 19 MiB / 2), as exporting is rare and the file travels.
  static KdfParams strongKdfParams() => KdfParams(
    salt: randomBytes(KdfParams.saltLength),
    memoryKiB: 65536,
    iterations: 3,
  );

  /// Backup export: encrypts [entries] with a key stretched from
  /// [password] (fresh salt and nonce every time). Returns the file text.
  Future<String> seal(
    List<Entry> entries,
    String password, {
    required DateTime now,
  }) async {
    if (!isValidBackupPassword(password)) {
      throw ArgumentError('backup password is too short');
    }
    final kdf = _newKdfParams();
    final key = await deriveKey(password, kdf);
    try {
      final sealed = await encrypt(encodePayload(entries), key);
      return BackupFile(
        exported: now.toUtc(),
        kdf: kdf,
        sealed: sealed,
      ).encode();
    } finally {
      destroyKey(key);
    }
  }

  /// Backup import: decrypts [file] with [password]. Throws
  /// [DecryptionFailedException] for a wrong password (or an altered file)
  /// and [VaultFormatException] if the contents aren't a list of entries.
  Future<List<Entry>> open(BackupFile file, String password) async {
    final key = await deriveKey(password, file.kdf);
    try {
      return decodePayload(await decrypt(file.sealed, key));
    } finally {
      destroyKey(key);
    }
  }
}

/// Backup import: what merging a backup did, for the "Imported ..." message.
class MergeResult {
  const MergeResult({
    required this.entries,
    required this.added,
    required this.skipped,
    required this.renamed,
  });

  /// The vault's new entry list (existing entries first, unchanged).
  final List<Entry> entries;

  /// Entries added from the backup, including [renamed] ones.
  final int added;

  /// Backup entries already in the vault (same name, username, password).
  final int skipped;

  /// Added entries whose name was taken, saved as "Name (2)" etc.
  final int renamed;
}

/// Backup import, merge: adds the backup's entries to [existing] without
/// changing or removing anything already saved.
/// * Same name (ignoring case), username and password → skipped.
/// * Name taken by a different entry → added as "Name (2)", "Name (3)"...
/// * An id already in use gets a fresh random id.
/// Saved and updated dates come across from the backup unchanged.
MergeResult mergeEntries(List<Entry> existing, List<Entry> incoming) {
  final result = [...existing];
  final ids = {for (final e in existing) e.id};
  var added = 0, skipped = 0, renamed = 0;

  bool nameTaken(String name) => result.any((e) => sameEntryName(e.name, name));

  for (final entry in incoming) {
    final name = cleanEntryName(entry.name);
    final duplicate = result.any(
      (e) =>
          sameEntryName(e.name, name) &&
          e.username == entry.username &&
          e.password == entry.password,
    );
    if (duplicate) {
      skipped++;
      continue;
    }
    final freeName = nextFreeEntryName(name, nameTaken);
    if (freeName != name) renamed++;
    final id = ids.contains(entry.id) ? randomHex(16) : entry.id;
    ids.add(id);
    result.add(
      Entry(
        id: id,
        name: freeName,
        username: entry.username,
        password: entry.password,
        created: entry.created,
        updated: entry.updated,
      ),
    );
    added++;
  }
  return MergeResult(
    entries: result,
    added: added,
    skipped: skipped,
    renamed: renamed,
  );
}
