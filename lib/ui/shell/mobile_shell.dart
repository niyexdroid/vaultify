import 'package:flutter/material.dart';

import 'shell_parts.dart';

/// Mobile shell (Android, iOS): title bar and a bottom navigation bar;
/// content capped at 600 wide and centred on tablets.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  AppArea _area = AppArea.generator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const VaultifyTitleBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: AreaStack(current: _area),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _area.index,
        onDestinationSelected: (i) =>
            setState(() => _area = AppArea.values[i]),
        destinations: [
          for (final a in AppArea.values)
            NavigationDestination(
              icon: Icon(a.icon),
              selectedIcon: Icon(a.selectedIcon),
              label: a.label,
            ),
        ],
      ),
    );
  }
}
