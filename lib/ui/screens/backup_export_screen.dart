import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault/backup.dart';
import '../../core/vault/vault_file.dart';
import '../providers.dart';
import '../session.dart';
import '../theme.dart';
import '../vault_entries.dart';
import '../widgets/auth_layout.dart';
import '../widgets/secret_input.dart';

/// Backup export (Options): enter the current PIN or password, choose a
/// backup password and confirm it, then pick where to save the encrypted
/// file. Pops with true once the file is saved. If wrong PIN entries reach
/// a wait, the app locks (and the lock gate closes this page).
class BackupExportScreen extends ConsumerStatefulWidget {
  const BackupExportScreen({super.key, required this.currentType});

  final UnlockType currentType;

  @override
  ConsumerState<BackupExportScreen> createState() => _BackupExportScreenState();
}

/// Backup export: the steps; [save] is shown again if the Save window was
/// cancelled.
enum _Step { current, choose, confirm, save }

class _BackupExportScreenState extends ConsumerState<BackupExportScreen> {
  final _input = TextEditingController();

  _Step _step = _Step.current;

  // Backup export: the backup password, kept only until confirmed.
  String? _first;

  // Backup export: the encrypted file text, kept so a cancelled Save
  // window can be reopened without encrypting again. Ciphertext only.
  String? _fileText;
  bool _busy = false;
  String? _error;

  String get _noun => widget.currentType == UnlockType.pin ? 'PIN' : 'password';

  static const _rules =
      'Use at least $minBackupPasswordLength characters. You need this '
      'password to open the backup on any device.';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _next(_Step step, {String? error}) {
    setState(() {
      _step = step;
      _error = error;
      _input.clear();
    });
  }

  // Step 1: check the current PIN or password (counts toward the 5 tries),
  // so someone holding an unlocked phone can't take a copy of everything.
  Future<void> _checkCurrent() async {
    final value = _input.text;
    if (_busy || value.isEmpty) return;
    if (!widget.currentType.isValidSecret(value)) {
      setState(() => _error = 'Wrong $_noun.');
      _input.clear();
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref
        .read(sessionProvider.notifier)
        .checkCurrentSecret(value);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case UnlockOutcome.success:
        _next(_Step.choose);
      case UnlockOutcome.wrong:
        final left = ref
            .read(sessionProvider)
            .requireValue
            .lockout
            .attemptsBeforeWait;
        final tries = left == 1 ? '1 try' : '$left tries';
        _next(
          _Step.current,
          error: 'Wrong $_noun. $tries left before Vaultify locks.',
        );
      case UnlockOutcome.waiting:
      case UnlockOutcome.damaged:
        // App locked; the lock gate closes this page.
        break;
    }
  }

  // Step 2: the backup password must be long enough.
  void _choose() {
    final value = _input.text;
    if (!isValidBackupPassword(value)) {
      setState(() => _error = _rules);
      return;
    }
    _first = value;
    _next(_Step.confirm);
  }

  // Step 3: entries must match; then encrypt and open the Save window.
  Future<void> _confirm() async {
    if (_busy) return;
    final value = _input.text;
    if (value != _first) {
      _first = null;
      _next(_Step.choose, error: "Passwords didn't match. Try again.");
      return;
    }
    setState(() => _busy = true);
    try {
      _fileText = await ref
          .read(vaultEntriesProvider.notifier)
          .exportBackup(value);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't create the backup. Try again.";
      });
      return;
    } finally {
      _first = null;
      if (mounted) _input.clear();
    }
    await _save();
  }

  // Step 4: the system Save window, with background lock paused while it
  // is open. Cancelling keeps the encrypted file so Save can be retried.
  Future<void> _save() async {
    final text = _fileText;
    if (text == null) return;
    setState(() => _busy = true);
    final now = ref.read(clockProvider)();
    String? error;
    var saved = false;
    try {
      saved = await ref
          .read(backgroundLockPauseProvider)
          .during(
            () => ref
                .read(backupFilesProvider)
                .save(backupFileName(now), utf8.encode(text)),
          );
    } catch (_) {
      error = "Couldn't save the file there. Try another place.";
    }
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _step = _Step.save;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(mobileLayoutProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    if (_step == _Step.save) {
      // Backup export: the Save window was cancelled (or failed).
      return AuthLayout(
        appBar: AppBar(title: const Text('Export backup')),
        heading: 'Your backup is ready',
        children: [
          Text(
            'Choose where to save it, for example Downloads, a USB stick or '
            'cloud storage.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.x2),
          AuthButton(label: 'Save backup file', busy: _busy, onPressed: _save),
          AuthMessage(_error, error: _error != null),
        ],
      );
    }

    final (heading, type, onSubmit, button) = switch (_step) {
      _Step.current => (
        'Enter your current $_noun',
        widget.currentType,
        _checkCurrent,
        'Continue',
      ),
      _Step.choose => (
        'Choose a backup password',
        UnlockType.password,
        _choose,
        'Continue',
      ),
      _ => (
        'Confirm the backup password',
        UnlockType.password,
        _confirm,
        'Save backup',
      ),
    };

    return AuthLayout(
      appBar: AppBar(title: const Text('Export backup')),
      heading: heading,
      children: [
        SecretInput(
          // New key per step so the field resets focus and show/hide state.
          key: ValueKey(_step),
          type: type,
          mobile: mobile,
          controller: _input,
          enabled: !_busy,
          onSubmit: onSubmit,
          hint: _step == _Step.current ? null : 'Backup password',
        ),
        const SizedBox(height: Space.x2),
        if (_step == _Step.confirm) ...[
          // No-recovery reminder before the file is made.
          Text(
            "Vaultify can't recover a forgotten backup password. Anyone with "
            'the file and this password can read your saved passwords.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.x2),
        ],
        AuthButton(label: button, busy: _busy, onPressed: onSubmit),
        AuthMessage(
          _error ?? (_step == _Step.choose ? _rules : null),
          error: _error != null,
        ),
      ],
    );
  }
}
