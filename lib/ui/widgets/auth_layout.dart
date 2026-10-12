import 'package:flutter/material.dart';

import '../theme.dart';

/// Unlock and setup layout: centred column with the shield icon and one
/// heading, as in SPEC.md "Unlock and setup screens". Scrolls on short
/// screens so the number pad never overflows.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.heading,
    required this.children,
    this.appBar,
  });

  final String heading;
  final List<Widget> children;

  /// Change PIN or password: a bar with a back button (setup and unlock
  /// have none).
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.shield_outlined, size: 48, color: c.primary),
                  const SizedBox(height: Space.x2),
                  Text(
                    heading,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.x3),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Unlock and setup: the attempts, wait or error message under the button,
/// in secondary text. Takes no space when [text] is null.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text, {super.key, this.error = false});

  final String? text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final message = text;
    if (message == null) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.x2),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: error ? c.weak : c.textSecondary),
      ),
    );
  }
}

/// Unlock and setup: the one filled button, showing a small spinner while
/// the key is being derived.
class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.textSecondary),
            )
          : Text(label),
    );
  }
}
