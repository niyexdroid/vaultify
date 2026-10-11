import 'package:flutter/material.dart';

import 'shell_parts.dart';

/// Desktop shell (Windows, macOS): title bar with tabs under it.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: AppArea.values.length, vsync: this)
        ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: VaultifyTitleBar(
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final a in AppArea.values) Tab(text: a.label)],
        ),
      ),
      body: AreaStack(current: AppArea.values[_tabs.index]),
    );
  }
}
