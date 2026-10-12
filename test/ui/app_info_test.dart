import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/ui/app_info.dart';

// About: the version shown in Options matches pubspec.yaml.
void main() {
  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match?.group(1), appVersion);
  });
}
