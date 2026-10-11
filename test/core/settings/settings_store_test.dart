import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/security/lockout.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/settings/settings_store.dart';

// Settings store tests: load/save of settings.json.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vaultify_settings_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('missing file gives defaults', () async {
    final s = await SettingsStore(dir).load();
    expect(s.toJson(), const Settings().toJson());
  });

  test('saved settings load back, including the lockout counter', () async {
    final store = SettingsStore(dir);
    final s = const Settings().copyWith(
      autoLockMinutes: 30,
      lockout: LockoutState.initial.recordFailure(DateTime.utc(2026)),
    );
    await store.save(s);
    final back = await SettingsStore(dir).load();
    expect(back.toJson(), s.toJson());
    expect(await File('${store.file.path}.tmp').exists(), isFalse);
  });

  test('a damaged file gives defaults instead of crashing', () async {
    final store = SettingsStore(dir);
    await store.file.writeAsString('{"autoLock');
    expect((await store.load()).toJson(), const Settings().toJson());
  });

  test('save creates the folder if needed', () async {
    final nested = Directory('${dir.path}${Platform.pathSeparator}sub');
    await SettingsStore(nested).save(const Settings());
    expect(await SettingsStore(nested).file.exists(), isTrue);
  });
}
