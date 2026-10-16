import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/settings/settings_store.dart';
import 'platform/window.dart';
import 'ui/providers.dart';
import 'ui/window_memory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App data folder: vault.vfy and settings.json live in the private
  // support folder. Read first, because the window size memory below needs
  // the saved bounds before the window is shown.
  final directory = await getApplicationSupportDirectory();
  final settings = await SettingsStore(directory).load();
  await configureDesktopWindow(saved: settings.windowBounds);
  runApp(ProviderScope(
    overrides: [appDirectoryProvider.overrideWithValue(directory)],
    // Window size memory: saves the window's size and position as it changes.
    child: const WindowMemory(child: VaultifyApp()),
  ));
}
