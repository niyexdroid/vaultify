import 'package:flutter/material.dart';

import '../theme.dart';

/// Options screen (stand-in until Milestone 6): the About line only.
class OptionsScreen extends StatelessWidget {
  const OptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Space.x2),
      children: [
        Text('Your vault lives only on this device.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
