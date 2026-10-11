import 'package:flutter/material.dart';

import '../theme.dart';

/// Number pad (mobile PIN entry): large 0–9 keys and a delete key that edit
/// [controller]'s text. Long-press delete clears the whole PIN.
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.enabled = true,
  });

  final TextEditingController controller;
  final int maxLength;
  final bool enabled;

  static const double _keyHeight = 56;

  void _type(String digit) {
    if (controller.text.length >= maxLength) return;
    controller.text = controller.text + digit;
  }

  void _delete() {
    final text = controller.text;
    if (text.isEmpty) return;
    controller.text = text.substring(0, text.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Row(children: [for (final d in row) _digitKey(context, d)]),
        Row(
          children: [
            const Expanded(child: SizedBox(height: _keyHeight)),
            _digitKey(context, '0'),
            Expanded(
              child: SizedBox(
                height: _keyHeight,
                child: GestureDetector(
                  onLongPress: enabled ? controller.clear : null,
                  child: IconButton(
                    tooltip: 'Delete digit',
                    onPressed: enabled ? _delete : null,
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Number pad: one digit key; the digit itself is the screen-reader label.
  Widget _digitKey(BuildContext context, String digit) {
    final c = context.colors;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(Space.half),
        child: SizedBox(
          height: _keyHeight,
          child: TextButton(
            onPressed: enabled ? () => _type(digit) : null,
            style: TextButton.styleFrom(
              foregroundColor: c.text,
              textStyle: const TextStyle(
                fontFamily: Fonts.ui,
                fontSize: FontSizes.heading,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(digit),
          ),
        ),
      ),
    );
  }
}

/// PIN dots (mobile PIN entry): one filled dot per digit typed, with empty
/// dots up to the minimum PIN length. The digits are never shown.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, required this.minLength});

  final int length;
  final int minLength;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slots = length > minLength ? length : minLength;
    return Semantics(
      label: '$length digits entered',
      excludeSemantics: true,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < slots; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < length ? c.primary : Colors.transparent,
                  border: Border.all(
                    color: i < length ? c.primary : c.textSecondary,
                    width: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
