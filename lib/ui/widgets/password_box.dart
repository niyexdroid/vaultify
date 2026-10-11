import 'package:flutter/material.dart';

import '../theme.dart';

/// Password box: surface-coloured, editable, monospace password with a copy
/// icon on the right. Editable so an existing password can be pasted in.
class PasswordBox extends StatelessWidget {
  const PasswordBox({
    super.key,
    required this.controller,
    required this.mobile,
    required this.onChanged,
    required this.onCopy,
  });

  final TextEditingController controller;
  final bool mobile;
  final ValueChanged<String> onChanged;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.card),
      borderSide: BorderSide(color: c.border),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: passwordTextStyle(c, mobile: mobile),
      minLines: 1,
      maxLines: 3,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.visiblePassword,
      decoration: InputDecoration(
        fillColor: c.surface,
        hintText: 'Password',
        contentPadding: const EdgeInsets.fromLTRB(
            Space.x2, Space.x2, Space.x1, Space.x2),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: c.primary),
        ),
        suffixIcon: IconButton(
          tooltip: 'Copy password',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_outlined),
        ),
      ),
    );
  }
}
