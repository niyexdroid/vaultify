import 'dart:io';

/// About, Open folder (desktop): shows [path] in Explorer (Windows) or
/// Finder (macOS). Does nothing elsewhere. Returns false if it couldn't.
Future<bool> openFolder(String path) async {
  try {
    if (Platform.isWindows) {
      // Explorer's exit code is unreliable (often 1 on success): ignore it.
      await Process.run('explorer', [path]);
      return true;
    }
    if (Platform.isMacOS) {
      return (await Process.run('open', [path])).exitCode == 0;
    }
  } on ProcessException {
    return false;
  }
  return false;
}
