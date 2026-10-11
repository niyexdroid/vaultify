import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// True on Windows and macOS, where the desktop shell is used.
bool get isDesktop => Platform.isWindows || Platform.isMacOS;

const Size defaultWindowSize = Size(420, 680);
const Size minimumWindowSize = Size(380, 560);

/// Sets the desktop window's default and minimum size. Does nothing on mobile.
Future<void> configureDesktopWindow() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: 'Vaultify',
    size: defaultWindowSize,
    minimumSize: minimumWindowSize,
    center: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
