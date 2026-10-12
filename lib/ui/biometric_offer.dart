import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/biometrics.dart';
import 'session.dart';

/// Biometric unlock: text in the system prompt when turning it on.
const biometricEnableReason = 'Turn on biometric unlock for Vaultify';

/// Biometric unlock: toast after trying to turn it on, or null when the
/// person just closed the prompt.
String? biometricEnableMessage(BiometricResult result) => switch (result) {
      BiometricResult.success => 'Biometric unlock on',
      BiometricResult.cancelled => null,
      _ => "Couldn't turn on biometric unlock",
    };

/// Biometric unlock offer: wraps the unlocked app and, once after the first
/// PIN or password unlock on a phone with a fingerprint or face set up,
/// asks whether to use it next time.
class BiometricOffer extends ConsumerStatefulWidget {
  const BiometricOffer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BiometricOffer> createState() => _BiometricOfferState();
}

class _BiometricOfferState extends ConsumerState<BiometricOffer> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  // Biometric unlock offer: show the question once the session asks for it.
  Future<void> _maybeAsk() async {
    if (!mounted || _showing) return;
    if (ref.read(sessionProvider).value?.offerBiometrics != true) return;
    _showing = true;
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock with fingerprint or face?'),
        content: const Text(
          'Next time a scan can open Vaultify. Your PIN or password is still '
          'needed at least every 7 days and after 5 failed scans.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    _showing = false;
    if (!mounted) return;
    final result = await ref.read(sessionProvider.notifier).answerBiometricOffer(
          turnOn: turnOn == true,
          reason: biometricEnableReason,
        );
    final message = result == null ? null : biometricEnableMessage(result);
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s.value?.offerBiometrics),
        (_, next) {
      if (next == true) _maybeAsk();
    });
    return widget.child;
  }
}
