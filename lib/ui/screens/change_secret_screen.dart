import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault/vault_file.dart';
import '../providers.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/auth_layout.dart';
import '../widgets/secret_input.dart';

/// Change PIN or password (Options): enter the current secret, then the new
/// one twice; the vault is re-encrypted with a new salt. With a different
/// [newType] this also switches between PIN and master password.
///
/// Pops with true once changed. If wrong current entries reach a wait, the
/// app locks (and the lock gate closes this page).
class ChangeSecretScreen extends ConsumerStatefulWidget {
  const ChangeSecretScreen({
    super.key,
    required this.currentType,
    required this.newType,
  });

  final UnlockType currentType;
  final UnlockType newType;

  @override
  ConsumerState<ChangeSecretScreen> createState() =>
      _ChangeSecretScreenState();
}

/// Change PIN or password: the three steps.
enum _Step { current, choose, confirm }

class _ChangeSecretScreenState extends ConsumerState<ChangeSecretScreen> {
  final _input = TextEditingController();

  _Step _step = _Step.current;

  // Change PIN or password: the new secret, kept only until confirmed.
  String? _first;
  bool _busy = false;
  String? _error;

  static String _noun(UnlockType t) =>
      t == UnlockType.pin ? 'PIN' : 'password';

  String get _newNoun => _noun(widget.newType);

  // Change PIN or password: rule hint for the new secret.
  String get _rules => widget.newType == UnlockType.pin
      ? 'Use ${UnlockType.minPinLength}–${UnlockType.maxPinLength} digits. '
            '${UnlockType.recommendedPinLength} or more is safer.'
      : 'Use at least ${UnlockType.minPasswordLength} characters.';

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

  // Step 1: check the current PIN or password (counts toward the 5 tries).
  Future<void> _checkCurrent() async {
    final value = _input.text;
    if (_busy || value.isEmpty) return;
    if (!widget.currentType.isValidSecret(value)) {
      setState(() => _error = 'Wrong ${_noun(widget.currentType)}.');
      _input.clear();
      return;
    }
    setState(() => _busy = true);
    final outcome =
        await ref.read(sessionProvider.notifier).checkCurrentSecret(value);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case UnlockOutcome.success:
        _next(_Step.choose);
      case UnlockOutcome.wrong:
        final left = ref.read(sessionProvider).requireValue.lockout
            .attemptsBeforeWait;
        final tries = left == 1 ? '1 try' : '$left tries';
        _next(_Step.current,
            error: 'Wrong ${_noun(widget.currentType)}. '
                '$tries left before Vaultify locks.');
      case UnlockOutcome.waiting:
      case UnlockOutcome.damaged:
        // App locked; the lock gate closes this page.
        break;
    }
  }

  // Step 2: the new secret must follow the rules.
  void _choose() {
    final value = _input.text;
    if (!widget.newType.isValidSecret(value)) {
      setState(() => _error = _rules);
      return;
    }
    _first = value;
    _next(_Step.confirm);
  }

  // Step 3: entries must match; then re-encrypt the vault.
  Future<void> _confirm() async {
    if (_busy) return;
    final value = _input.text;
    if (value != _first) {
      _first = null;
      _next(_Step.choose,
          error: "${_newNoun == 'PIN' ? 'PINs' : 'Passwords'} didn't match. "
              'Try again.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .changeSecret(value, widget.newType);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't change it. Your old $_newNoun still works.";
      });
    } finally {
      _first = null;
      if (mounted) _input.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(mobileLayoutProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final switching = widget.currentType != widget.newType;
    final title = switching
        ? (widget.newType == UnlockType.pin
            ? 'Switch to a PIN'
            : 'Switch to a master password')
        : 'Change ${_noun(widget.currentType)}';

    final (heading, type, onSubmit, button) = switch (_step) {
      _Step.current => (
          'Enter your current ${_noun(widget.currentType)}',
          widget.currentType,
          _checkCurrent,
          'Continue',
        ),
      _Step.choose => (
          'Choose your new $_newNoun',
          widget.newType,
          _choose,
          'Continue',
        ),
      _Step.confirm => (
          'Confirm your new $_newNoun',
          widget.newType,
          _confirm,
          switching ? 'Switch' : 'Change $_newNoun',
        ),
    };

    return AuthLayout(
      appBar: AppBar(title: Text(title)),
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
        ),
        const SizedBox(height: Space.x2),
        if (_step == _Step.confirm) ...[
          // No-recovery reminder before the change is made.
          Text(
            "Vaultify can't recover a forgotten $_newNoun.",
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
