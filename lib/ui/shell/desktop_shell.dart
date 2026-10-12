import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../generator_controller.dart';
import '../screens/saved_screen.dart';
import '../session.dart';
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

  // Keyboard shortcuts, Ctrl/Cmd+G: open the Generator and make a new
  // password.
  void _generate() {
    ref.read(currentAreaProvider.notifier).show(AppArea.generator);
    ref.read(generatorProvider.notifier).generate();
  }

  // Keyboard shortcuts, Ctrl/Cmd+F: open Saved and put the cursor in search
  // (once the Saved tab is showing).
  void _search() {
    ref.read(currentAreaProvider.notifier).show(AppArea.saved);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(savedSearchFocusProvider).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final area = ref.watch(currentAreaProvider);
    // Desktop tabs: follow area changes made elsewhere (e.g. the empty
    // Saved screen's "Open generator").
    ref.listen(currentAreaProvider, (_, next) {
      if (_tabs.index != next.index) _tabs.animateTo(next.index);
    });
    // Keyboard shortcuts: Cmd on macOS, Ctrl on Windows.
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator key(LogicalKeyboardKey k) =>
        SingleActivator(k, control: !mac, meta: mac);
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.keyG): _generate,
        key(LogicalKeyboardKey.keyL): () =>
            ref.read(sessionProvider.notifier).lock(),
        key(LogicalKeyboardKey.keyF): _search,
      },
      // Autofocus so shortcuts work before anything has been clicked.
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: VaultifyTitleBar(
            bottom: TabBar(
              controller: _tabs,
              tabs: [for (final a in AppArea.values) Tab(text: a.label)],
            ),
          ),
          body: AreaStack(current: area),
        ),
      ),
    );
  }
}
