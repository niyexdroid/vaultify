import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'platform/window.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();
  // App data folder: vault.vfy and settings.json live in the private
  // support folder.
  final directory = await getApplicationSupportDirectory();
  runApp(ProviderScope(
    overrides: [appDirectoryProvider.overrideWithValue(directory)],
    child: const VaultifyApp(),
  ));
}
