import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/lockout.dart';
import '../../core/vault/vault_file.dart';
import '../providers.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/auth_layout.dart';
import '../widgets/secret_input.dart';

/// Unlock screen: asks for the PIN or master password, and shows the tries
/// left or the wrong-attempt wait with a live countdown.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key, required this.type});

  final UnlockType type;

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _input = TextEditingController();

  bool _busy = false;
  bool _justFailed = false;
  String? _hint;

  // Bumped after each try so the field is rebuilt with focus.
  int _attempt = 0;

  // Wrong-attempt delays: redraws the countdown once a second while a wait
  // runs, plus once when it ends to re-enable the field.
  Timer? _ticker;
  bool _wasWaiting = false;

  // Biometric unlock (mobile): whether a scan is offered, whether one is
  // running, whether the automatic prompt has been shown, and its message.
  bool _bioReady = false;
  bool _bioBusy = false;
  bool _bioAutoTried = false;
  String? _bioMessage;
  AppLifecycleListener? _lifecycle;

  /// Biometric unlock: text in the system fingerprint / face prompt.
  static const biometricReason = 'Unlock Vaultify';

  bool get _isPin => widget.type == UnlockType.pin;
  String get _noun => _isPin ? 'PIN' : 'password';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final lockout = ref.read(sessionProvider).value?.lockout;
      final waiting = lockout?.isLocked(ref.read(clockProvider)()) ?? false;
      if (waiting || _wasWaiting) setState(() {});
      _wasWaiting = waiting;
    });
    if (ref.read(mobileLayoutProvider)) {
      // Biometric unlock: a background lock builds this screen while the
      // app is away, so the automatic prompt waits until it is back.
      _lifecycle = AppLifecycleListener(onResume: _autoScan);
      _checkBiometrics();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle?.dispose();
    _input.dispose();
    super.dispose();
  }

  // Biometric unlock: find out if a scan is offered, then prompt once.
  Future<void> _checkBiometrics() async {
    final ready = await ref.read(sessionProvider.notifier).biometricsReady();
    if (!mounted || !ready) return;
    setState(() => _bioReady = true);
    _autoScan();
  }

  // Biometric unlock: the automatic prompt, shown once per lock and only
  // while the app is on screen.
  void _autoScan() {
    if (!_bioReady || _bioAutoTried) return;
    final appState = WidgetsBinding.instance.lifecycleState;
    if (appState != null && appState != AppLifecycleState.resumed) return;
    _bioAutoTried = true;
    _scan();
  }

  // Biometric unlock: one fingerprint / face check.
  Future<void> _scan() async {
    if (_busy || _bioBusy) return;
    setState(() {
      _bioBusy = true;
      _bioMessage = null;
    });
    final outcome = await ref
        .read(sessionProvider.notifier)
        .unlockWithBiometrics(biometricReason);
    if (!mounted) return;
    setState(() {
      _bioBusy = false;
      switch (outcome) {
        case BiometricUnlock.failed:
          _bioMessage = 'Not recognised. Try again or use your $_noun.';
        case BiometricUnlock.secretRequired:
          _bioReady = false;
          _bioMessage = 'Enter your $_noun to continue.';
        case BiometricUnlock.success:
        case BiometricUnlock.cancelled:
        case BiometricUnlock.waiting:
        case BiometricUnlock.damaged:
          break;
      }
    });
  }

  // Unlock: skip obviously invalid entries (they can't be right and
  // shouldn't cost a try), otherwise ask the session controller.
  Future<void> _unlock() async {
    if (_busy || _bioBusy) return;
    final value = _input.text;
    if (value.isEmpty) return;
    if (!widget.type.isValidSecret(value)) {
      setState(() => _hint = _isPin
          ? 'Your PIN is ${UnlockType.minPinLength}–${UnlockType.maxPinLength} digits.'
          : 'Your password is at least ${UnlockType.minPasswordLength} characters.');
      return;
    }
    setState(() {
      _busy = true;
      _hint = null;
      _bioMessage = null;
    });
    final outcome = await ref.read(sessionProvider.notifier).unlock(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _justFailed = outcome == UnlockOutcome.wrong;
      _attempt++;
      _input.clear();
    });
  }

  // Wrong-attempt delays: "Wrong PIN. 3 tries left before a wait." or
  // "Too many wrong tries. Try again in 0:27."
  String? _message(LockoutState lockout, Duration wait) {
    if (wait > Duration.zero) {
      return 'Too many wrong tries. Try again in ${_formatWait(wait)}.';
    }
    if (_hint != null) return _hint;
    if (_bioMessage != null) return _bioMessage;
    final left = lockout.attemptsBeforeWait;
    final tries = left == 1 ? '1 try' : '$left tries';
    final leftText = left > 0 ? ' $tries left before a wait.' : '';
    if (_justFailed) return 'Wrong $_noun.$leftText';
    if (lockout.failedAttempts > 0 && left > 0) return leftText.trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(mobileLayoutProvider);
    final lockout =
        ref.watch(sessionProvider).value?.lockout ?? LockoutState.initial;
    final wait = lockout.remaining(ref.read(clockProvider)());
    final waiting = wait > Duration.zero;

    return AuthLayout(
      heading: 'Unlock Vaultify',
      children: [
        SecretInput(
          key: ValueKey(_attempt),
          type: widget.type,
          mobile: mobile,
          controller: _input,
          enabled: !_busy && !waiting,
          onSubmit: _unlock,
        ),
        const SizedBox(height: Space.x2),
        AuthButton(
          label: 'Unlock',
          busy: _busy,
          onPressed: waiting ? null : _unlock,
        ),
        // Biometric unlock (mobile): try a scan again after closing the
        // prompt or a failed scan. Hidden during a wrong-attempt wait.
        if (_bioReady && !waiting) ...[
          const SizedBox(height: Space.x1),
          TextButton.icon(
            onPressed: _busy || _bioBusy ? null : _scan,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Use fingerprint or face'),
          ),
        ],
        AuthMessage(
          _message(lockout, wait),
          error: _justFailed && !waiting,
        ),
      ],
    );
  }
}

/// Wrong-attempt delays: 27 s → "0:27", 5 min → "5:00".
String _formatWait(Duration d) {
  // Round up so the countdown never shows 0:00 while still waiting.
  final total = (d.inMilliseconds / 1000).ceil();
  final minutes = total ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
