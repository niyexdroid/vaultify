import 'package:flutter/material.dart';

import 'ui/theme.dart';

class VaultifyApp extends StatelessWidget {
  const VaultifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vaultify',
      debugShowCheckedModeBanner: false,
      theme: VaultifyTheme.light,
      darkTheme: VaultifyTheme.dark,
      themeMode: ThemeMode.system,
      home: const _ThemePreview(),
    );
  }
}

/// Milestone 1 placeholder: shows the theme tokens so light and dark mode can
/// be checked. Replaced by setup/unlock and the shells in later milestones.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    const swatches = <String>[
      'primary', 'primarySoft', 'surface', 'border', 'text', 'textSecondary',
      'weak', 'fair', 'strong',
    ];
    final values = <Color>[
      c.primary, c.primarySoft, c.surface, c.border, c.text, c.textSecondary,
      c.weak, c.fair, c.strong,
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(Space.x3),
              children: [
                Icon(Icons.shield_outlined, size: 40, color: c.primary),
                const SizedBox(height: Space.x2),
                Text('Vaultify', style: text.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: Space.x1),
                Text('Theme preview', style: text.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: Space.x3),
                Container(
                  padding: const EdgeInsets.all(Space.x2),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(Radii.control),
                  ),
                  child: Text(
                    'k7#Rm2!vQp9@Lx4z',
                    style: passwordTextStyle(c, mobile: false),
                  ),
                ),
                const SizedBox(height: Space.x2),
                Wrap(
                  spacing: Space.x1,
                  runSpacing: Space.x1,
                  children: [
                    for (var i = 0; i < swatches.length; i++)
                      _Swatch(label: swatches[i], color: values[i]),
                  ],
                ),
                const SizedBox(height: Space.x3),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh),
                  label: const Text('Generate'),
                ),
                const SizedBox(height: Space.x1),
                OutlinedButton(onPressed: () {}, child: const Text('Save to vault')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: Space.half),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
