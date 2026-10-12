import 'dart:io';

import 'package:flutter/services.dart';

/// Sensitive clipboard flag (Android): copies a password with the
/// "sensitive" mark, so Android 13+ hides it in the clipboard preview.
/// Handled by MainActivity.kt; Flutter's own Clipboard can't set the mark.
const _channel = MethodChannel('app.vaultify/clipboard');

/// Sensitive clipboard flag: copies [text] marked as sensitive on Android,
/// and with Flutter's plain Clipboard elsewhere (or if the channel fails).
Future<void> copySensitive(String text) async {
  if (Platform.isAndroid) {
    try {
      await _channel.invokeMethod<void>('copySensitive', {'text': text});
      return;
    } on PlatformException {
      // Fall through to a plain copy.
    } on MissingPluginException {
      // Fall through to a plain copy.
    }
  }
  await Clipboard.setData(ClipboardData(text: text));
}
