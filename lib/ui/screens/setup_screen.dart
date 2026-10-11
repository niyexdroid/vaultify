import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault/vault_file.dart';
import '../providers.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/auth_layout.dart';
import '../widgets/secret_input.dart';

/// First-launch setup: pick PIN or master password, enter it, confirm it,
/// tick the no-recovery warning, then the vault is created and opened.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _input = TextEditingController();

  UnlockType _type = UnlockType.pin;

  // Setup: the first entry, kept only until it is confirmed or rejected.
  String? _first;
  bool _understood = false;
  bool _busy = false;
  String? _error;

  bool get _confirming => _first != null;
  String get _noun => _type == UnlockType.pin ? 'PIN' : 'password';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  // Setup: rule hint shown under the field while choosing.
  String get _rules => _type == UnlockType.pin
      ? 'Use ${UnlockType.minPinLength}–${UnlockType.maxPinLength} digits. '
            '${UnlockType.recommendedPinLength} or more is safer.'
      : 'Use at least ${UnlockType.minPasswordLength} characters.';

  // Setup: switch between PIN and master password; starts over.
  void _switchType() {
    setState(() {
      _type = _type == UnlockType.pin ? UnlockType.password : UnlockType.pin;
      _first = null;
      _understood = false;
      _error = null;
      _input.clear();
    });
  }

  // Setup, step 1: check the rules, then ask for it again.
  void _continue() {
    final value = _input.text;
    if (!_type.isValidSecret(value)) {
      setState(() => _error = _rules);
      return;
    }
    setState(() {
      _first = value;
      _error = null;
      _input.clear();
    });
  }

  // Setup, step 2: entries must match; then create the vault.
  Future<void> _create() async {
    if (!_understood || _busy) return;
    final value = _input.text;
    if (value != _first) {
      setState(() {
        _first = null;
        _understood = false;
        _error =
            "${_noun == 'PIN' ? 'PINs' : 'Passwords'} didn't match. Try again.";
        _input.clear();
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).create(value, _type);
      // Lock gate swaps this screen out once the vault exists.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't create the vault. Check there is free space and try again.";
      });
    } finally {
      _first = null;
      if (mounted) _input.clear();
    }
  }

  // Setup: back from confirm to choosing.
  void _back() {
    setState(() {
      _first = null;
      _understood = false;
      _error = null;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(mobileLayoutProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return AuthLayout(
      heading: _confirming ? 'Confirm your $_noun' : 'Create your $_noun',
      children: [
        if (!_confirming) ...[
          Text(
            _type == UnlockType.pin
                ? 'Your PIN unlocks Vaultify on this device.'
                : 'Your master password unlocks Vaultify on this device.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.x2),
        ],
        SecretInput(
          // New key per step so the field resets focus and show/hide state.
          key: ValueKey('$_type-$_confirming'),
          type: _type,
          mobile: mobile,
          controller: _input,
          enabled: !_busy,
          onSubmit: _confirming ? _create : _continue,
        ),
        const SizedBox(height: Space.x2),
        if (_confirming) ...[
          // Setup: no-recovery warning; must be ticked before creating.
          // A Material (not a coloured Container) so the checkbox row's
          // tap highlight paints on the card.
          Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: c.border),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vaultify can\'t recover a forgotten $_noun. If you lose it, '
                    'your saved passwords are gone for good.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: Space.x1),
                  CheckboxListTile(
                    value: _understood,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _understood = v ?? false),
                    title: Text('I understand', style: text.bodyMedium),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x2),
          AuthButton(
            label: 'Create vault',
            busy: _busy,
            onPressed: _understood ? _create : null,
          ),
          const SizedBox(height: Space.x1),
          TextButton(
            onPressed: _busy ? null : _back,
            child: const Text('Back'),
          ),
        ] else ...[
          AuthButton(label: 'Continue', onPressed: _continue),
          const SizedBox(height: Space.x1),
          TextButton(
            onPressed: _switchType,
            child: Text(
              _type == UnlockType.pin
                  ? 'Use a master password instead'
                  : 'Use a PIN instead',
            ),
          ),
        ],
        AuthMessage(
          _error ?? (_confirming ? null : _rules),
          error: _error != null,
        ),
      ],
    );
  }
}
