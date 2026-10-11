import 'dart:convert';
import 'dart:io';

import 'settings.dart';

/// Settings store: reads and writes `settings.json` in the app folder.
class SettingsStore {
  SettingsStore(this.directory);

  final Directory directory;

  static const String fileName = 'settings.json';

  File get file => File('${directory.path}${Platform.pathSeparator}$fileName');
  File get _tempFile => File('${file.path}.tmp');

  /// Settings store: loads settings; a missing or damaged file gives the
  /// defaults instead of stopping the app.
  Future<Settings> load() async {
    try {
      return Settings.fromJson(jsonDecode(await file.readAsString()));
    } on FileSystemException {
      return const Settings();
    } on FormatException {
      return const Settings();
    }
  }

  /// Settings store: saves via a temp file and rename, so a crash never
  /// leaves half a settings file (which would reset the lockout counter).
  Future<void> save(Settings settings) async {
    await directory.create(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    await _tempFile.writeAsString(text, flush: true);
    await _tempFile.rename(file.path);
  }
}
