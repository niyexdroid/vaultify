import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shell_parts.dart';

/// Mobile shell (Android, iOS): title bar and a bottom navigation bar;
/// content capped at 600 wide and centred on tablets.
class MobileShell extends ConsumerWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(currentAreaProvider);
    return Scaffold(
      appBar: const VaultifyTitleBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: AreaStack(current: area),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: area.index,
        onDestinationSelected: (i) =>
            ref.read(currentAreaProvider.notifier).show(AppArea.values[i]),
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
