import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/crypto/cipher.dart';
import '../../core/vault/backup.dart';
import '../../core/vault/vault_file.dart';
import '../providers.dart';
import '../theme.dart';
import '../vault_entries.dart';
import '../widgets/auth_layout.dart';
import '../widgets/entry_row.dart';
import '../widgets/secret_input.dart';

/// Backup import (Options): asks for the backup password of an already
/// picked [file], then merges its entries into the vault (nothing saved is
/// changed or removed). Pops with the [MergeResult].
///
/// Wrong backup passwords don't count toward the PIN's wrong-attempt waits:
/// they only open a file the user already holds, not this vault.
class BackupImportScreen extends ConsumerStatefulWidget {
  const BackupImportScreen({super.key, required this.file});

  final BackupFile file;

  @override
  ConsumerState<BackupImportScreen> createState() => _BackupImportScreenState();
}

class _BackupImportScreenState extends ConsumerState<BackupImportScreen> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  // Backup import: decrypt with the typed password and merge.
  Future<void> _import() async {
    final password = _input.text;
    if (_busy || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String error;
    try {
      final result = await ref
          .read(vaultEntriesProvider.notifier)
          .importBackup(widget.file, password);
      if (mounted) Navigator.of(context).pop(result);
      return;
    } on DecryptionFailedException {
      error = 'Wrong backup password.';
    } on VaultFormatException {
      error = "This backup is damaged and can't be read.";
    } catch (_) {
      error = "Couldn't import. Your vault hasn't changed.";
    } finally {
      if (mounted) _input.clear();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(mobileLayoutProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      appBar: AppBar(title: const Text('Import backup')),
      heading: 'Enter the backup password',
      children: [
        Text(
          'Backup made ${formatSavedDate(widget.file.exported)}. Its '
          'passwords are added to this vault; nothing saved here is changed.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: Space.x2),
        SecretInput(
          type: UnlockType.password,
          mobile: mobile,
          controller: _input,
          enabled: !_busy,
          onSubmit: _import,
          hint: 'Backup password',
        ),
        const SizedBox(height: Space.x2),
        AuthButton(label: 'Import', busy: _busy, onPressed: _import),
        AuthMessage(_error, error: _error != null),
      ],
    );
  }
}

/// Backup import: the result toast, e.g. "Imported 5 passwords · 2 were
/// already saved · 1 renamed".
String importSummary(MergeResult r) {
  String plural(int n, String one, String many) => n == 1 ? one : many;
  final parts = [
    r.added == 0
        ? 'Nothing new to import'
        : 'Imported ${r.added} ${plural(r.added, 'password', 'passwords')}',
    if (r.skipped > 0)
      '${r.skipped} ${plural(r.skipped, 'was', 'were')} already saved',
    if (r.renamed > 0) '${r.renamed} renamed',
  ];
  return parts.join(' · ');
}
