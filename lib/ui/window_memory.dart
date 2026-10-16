import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings.dart';
import '../platform/window.dart';
import 'session.dart';

/// Window size memory: saves the desktop window's size and position shortly
/// after the user stops dragging or resizing, so the next launch reopens the
/// same way. Does nothing on mobile, where the app is always full screen.
class WindowMemory extends ConsumerStatefulWidget {
  const WindowMemory({super.key, required this.child, this.watcher});

  final Widget child;

  /// Injected by tests; normally a real watcher is made when on desktop.
  final WindowBoundsWatcher? watcher;

  @override
  ConsumerState<WindowMemory> createState() => _WindowMemoryState();
}

class _WindowMemoryState extends ConsumerState<WindowMemory> {
  WindowBoundsWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    final watcher =
        widget.watcher ?? (isDesktop ? WindowBoundsWatcher() : null);
    if (watcher == null) return;
    _watcher = watcher..start(_save);
  }

  @override
  void dispose() {
    _watcher?.stop();
    super.dispose();
  }

  /// Window size memory: writes the new bounds through the normal settings
  /// path, so it can't race with other settings being saved.
  void _save(WindowBounds bounds) {
    final session = ref.read(sessionProvider);
    // Nothing to save into yet while settings are still loading.
    if (!session.hasValue) return;
    if (session.requireValue.settings.windowBounds == bounds) return;
    ref
        .read(sessionProvider.notifier)
        .updateSettings((s) => s.copyWith(windowBounds: bounds));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
