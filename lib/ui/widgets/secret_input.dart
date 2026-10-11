import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/vault/vault_file.dart';
import '../theme.dart';
import 'number_pad.dart';

/// Secret input (setup and unlock): a PIN or master password entry. Mobile
/// PINs use the on-screen number pad; everything else is a hidden text
/// field. The value lives only in [controller]; screens clear it after use.
class SecretInput extends StatefulWidget {
  const SecretInput({
    super.key,
    required this.type,
    required this.mobile,
    required this.controller,
    required this.onSubmit,
    this.enabled = true,
  });

  final UnlockType type;
  final bool mobile;
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  State<SecretInput> createState() => _SecretInputState();
}

class _SecretInputState extends State<SecretInput> {
  // Master password: show/hide toggle; PINs stay hidden.
  bool _obscured = true;

  bool get _isPin => widget.type == UnlockType.pin;

  @override
  Widget build(BuildContext context) {
    if (_isPin && widget.mobile) {
      return ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PinDots(
              length: widget.controller.text.length,
              minLength: UnlockType.minPinLength,
            ),
            const SizedBox(height: Space.x2),
            NumberPad(
              controller: widget.controller,
              maxLength: UnlockType.maxPinLength,
              enabled: widget.enabled,
            ),
          ],
        ),
      );
    }

    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: true,
      obscureText: _isPin || _obscured,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: _isPin ? TextInputType.number : TextInputType.visiblePassword,
      inputFormatters: _isPin
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(UnlockType.maxPinLength),
            ]
          : null,
      textAlign: _isPin ? TextAlign.center : TextAlign.start,
      onSubmitted: (_) => widget.onSubmit(),
      decoration: InputDecoration(
        hintText: _isPin ? 'PIN' : 'Master password',
        suffixIcon: _isPin
            ? null
            : IconButton(
                tooltip: _obscured ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
      ),
    );
  }
}
