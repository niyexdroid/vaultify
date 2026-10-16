import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/settings/settings.dart';

/// True on Windows and macOS, where the desktop shell is used.
bool get isDesktop => Platform.isWindows || Platform.isMacOS;

const Size defaultWindowSize = Size(420, 680);
const Size minimumWindowSize = Size(380, 560);

/// Sets the desktop window's size, using [saved] bounds from a previous run
/// when there are some. Does nothing on mobile.
Future<void> configureDesktopWindow({WindowBounds? saved}) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  // Window size memory: never open smaller than the minimum, however the
  // settings file got its numbers.
  final size = saved == null
      ? defaultWindowSize
      : Size(
          saved.width.clamp(minimumWindowSize.width, double.infinity),
          saved.height.clamp(minimumWindowSize.height, double.infinity),
        );
  final options = WindowOptions(
    title: 'Vaultify',
    size: size,
    minimumSize: minimumWindowSize,
    center: saved?.x == null || saved?.y == null,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (saved?.x != null && saved?.y != null) {
      await windowManager.setPosition(Offset(saved!.x!, saved.y!));
      // The saved spot may have been on a monitor that is no longer
      // plugged in, which would open the window out of reach.
      await _ensureOnScreen(Offset(saved.x!, saved.y!), size);
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Window size memory: centres the window if the position it was given
/// lands outside every display that is currently connected.
Future<void> _ensureOnScreen(Offset position, Size size) async {
  final List<Display> displays;
  try {
    displays = await screenRetriever.getAllDisplays();
  } on Object {
    // If the displays can't be read, leave the window where it was put
    // rather than yanking a correctly placed window to the centre.
    return;
  }
  // Enough of the title bar must sit inside a screen to grab it with a mouse.
  const double grabMargin = 80;
  final reachable = displays.any((display) {
    final origin = display.visiblePosition ?? Offset.zero;
    final area = display.visibleSize ?? display.size;
    return position.dx + size.width - grabMargin > origin.dx &&
        position.dx + grabMargin < origin.dx + area.width &&
        position.dy + size.height - grabMargin > origin.dy &&
        position.dy + grabMargin < origin.dy + area.height;
  });
  if (!reachable) await windowManager.center();
}

/// Window size memory: watches the desktop window and reports its new bounds
/// shortly after the user stops dragging or resizing.
class WindowBoundsWatcher with WindowListener {
  WindowBoundsWatcher({this.settle = const Duration(seconds: 1)});

  /// Resizing fires continuously, so the save waits until it goes quiet.
  final Duration settle;

  void Function(WindowBounds)? _onSettled;
  Timer? _timer;

  /// Starts watching; [onSettled] is called with the window's bounds once it
  /// has been still for [settle].
  void start(void Function(WindowBounds) onSettled) {
    _onSettled = onSettled;
    windowManager.addListener(this);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onSettled = null;
    windowManager.removeListener(this);
  }

  // Dragging the window's edge or title bar, which is the usual way.
  @override
  void onWindowResized() => _schedule();

  @override
  void onWindowMoved() => _schedule();

  // Coming back to a normal window from maximised, snapped or minimised.
  @override
  void onWindowUnmaximize() => _schedule();

  @override
  void onWindowRestore() => _schedule();

  @override
  void onWindowUndocked() => _schedule();

  // Catch-all: snapping with Win+arrow or moving the window by keyboard
  // reports nothing above, but the window always loses focus eventually.
  @override
  void onWindowBlur() => _schedule();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(settle, _report);
  }

  Future<void> _report() async {
    // A maximised or full-screen window would save the screen's size as the
    // restored size, so those states are skipped.
    if (await windowManager.isMaximized() ||
        await windowManager.isFullScreen() ||
        await windowManager.isMinimized()) {
      return;
    }
    final size = await windowManager.getSize();
    final position = await windowManager.getPosition();
    _onSettled?.call(
      WindowBounds(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
      ),
    );
  }
}
