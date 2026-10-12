import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shell_parts.dart';

/// Desktop shell (Windows, macOS): title bar with tabs under it.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: AppArea.values.length,
    vsync: this,
    initialIndex: ref.read(currentAreaProvider).index,
  )..addListener(_onTab);

  // Desktop tabs: a clicked tab becomes the current area.
  void _onTab() {
    final tapped = AppArea.values[_tabs.index];
    if (ref.read(currentAreaProvider) != tapped) {
      ref.read(currentAreaProvider.notifier).show(tapped);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final area = ref.watch(currentAreaProvider);
    // Desktop tabs: follow area changes made elsewhere (e.g. the empty
    // Saved screen's "Open generator").
    ref.listen(currentAreaProvider, (_, next) {
      if (_tabs.index != next.index) _tabs.animateTo(next.index);
    });
    return Scaffold(
      appBar: VaultifyTitleBar(
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final a in AppArea.values) Tab(text: a.label)],
        ),
      ),
      body: AreaStack(current: area),
    );
  }
}
