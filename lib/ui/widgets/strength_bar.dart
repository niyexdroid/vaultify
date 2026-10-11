import 'package:flutter/material.dart';

import '../../core/generator/strength.dart';
import '../theme.dart';

/// Strength meter: 4 px full-width bar coloured by strength, with the label
/// on the right. Empty password shows an empty bar and no label.
class StrengthBar extends StatelessWidget {
  const StrengthBar({super.key, required this.bits, required this.empty});

  final double bits;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strength = Strength.fromBits(bits);
    final color = switch (strength) {
      Strength.weak => c.weak,
      Strength.fair => c.fair,
      Strength.strong || Strength.veryStrong => c.strong,
    };
    final fill = empty ? 0.0 : strengthFill(bits);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: c.border),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fill,
                    child: ColoredBox(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.x2),
        SizedBox(
          width: 76,
          child: Text(
            empty ? '' : strength.label,
            textAlign: TextAlign.right,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
