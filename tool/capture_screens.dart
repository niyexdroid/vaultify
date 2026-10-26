// UI design pass: renders each screen and writes a PNG into build/screens/,
// so the layout can be checked against the UI design section of SPEC.md
// without a real device.
//
//   flutter test tool/capture_screens.dart --update-goldens
//
// Not part of the test suite; it asserts nothing. Delete the PNGs freely.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/vault/entry.dart';

import 'package:vaultify/ui/screens/qr_scan_screen.dart';
import 'package:vaultify/ui/theme.dart';

import '../test/ui/fakes.dart';

const String outDir = 'screens';

/// Material icons live in the Flutter SDK's cache, not in this repo. The
/// engine artefacts sit next to it, which is how the SDK root is found.
final String materialIconsPath = () {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final font = File('${dir.path}/artifacts/material_fonts/'
        'materialicons-regular.otf');
    if (font.existsSync()) return font.path;
    dir = dir.parent;
  }
  return '';
}();

void main() {
  // Real fonts, so the screenshots show actual words and icons instead of
  // the blank boxes the test font draws.
  setUpAll(_loadFonts);

  _captureViewfinder();

  // Desktop window at its default size, a maximised desktop window, and a
  // typical phone. The wide size is captured because the window is resizable:
  // layouts that look right at 420 can stretch badly at 1280.
  const desktop = Size(420, 680);
  const desktopWide = Size(1280, 800);
  const phone = Size(390, 844);

  for (final dark in [false, true]) {
    final suffix = dark ? 'dark' : 'light';

    testWidgets('generator + saved + options ($suffix)', (tester) async {
      await _sized(tester, desktop, dark);
      final repo = FakeVaultRepository(secret: '123456')
        ..saved.addAll(_sampleEntries());
      await pumpVaultify(tester, repo: repo);
      await _unlock(tester, mobile: false);
      await _shot(tester, 'desktop-generator-$suffix');

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      await _shot(tester, 'desktop-saved-$suffix');

      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      await _shot(tester, 'desktop-options-$suffix');
    });

    // Wide window: checks the generator, saved list and unlock screen do not
    // stretch across a maximised desktop window.
    testWidgets('wide desktop window ($suffix)', (tester) async {
      await _sized(tester, desktopWide, dark);
      final repo = FakeVaultRepository(secret: '123456')
        ..saved.addAll(_sampleEntries());
      await pumpVaultify(tester, repo: repo);
      await _shot(tester, 'wide-unlock-$suffix');

      await _unlock(tester, mobile: false);
      await _shot(tester, 'wide-generator-$suffix');

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      await _shot(tester, 'wide-saved-$suffix');
    });

    testWidgets('unlock screen ($suffix)', (tester) async {
      await _sized(tester, desktop, dark);
      await pumpVaultify(tester, repo: FakeVaultRepository(secret: '123456'));
      await _shot(tester, 'desktop-unlock-$suffix');
    });

    testWidgets('empty saved screen ($suffix)', (tester) async {
      await _sized(tester, desktop, dark);
      await pumpVaultify(tester, repo: FakeVaultRepository(secret: '123456'));
      await _unlock(tester, mobile: false);
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      await _shot(tester, 'desktop-saved-empty-$suffix');
    });

    testWidgets('mobile generator + saved ($suffix)', (tester) async {
      await _sized(tester, phone, dark);
      final repo = FakeVaultRepository(secret: '123456')
        ..saved.addAll(_sampleEntries());
      await pumpVaultify(tester, repo: repo, mobile: true);
      await _unlock(tester, mobile: true);
      await _shot(tester, 'mobile-generator-$suffix');

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      await _shot(tester, 'mobile-saved-$suffix');
    });
  }
}

/// Loads the app's bundled fonts plus Material icons into the test engine.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        stderr.writeln('missing font: $path');
        continue;
      }
      loader.addFont(
          file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Inter', [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
  ]);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-Regular.ttf']);
  await load('MaterialIcons', [materialIconsPath]);
}

/// Unlocks past the PIN screen: a number pad on mobile, a field on desktop.
Future<void> _unlock(WidgetTester tester, {required bool mobile}) async {
  if (mobile) {
    await tapDigits(tester, '123456');
  } else {
    await tester.enterText(find.byType(TextField).first, '123456');
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
  await tester.pumpAndSettle();
}

List<Entry> _sampleEntries() {
  final now = DateTime.utc(2026, 10, 14, 9, 30);
  return [
    Entry.create(
        name: 'Gmail',
        username: 'ade@example.com',
        password: 'Kq7!vR2mXz9aLp4T',
        now: now),
    Entry.create(
        name: 'GitHub',
        username: 'niyexdroid',
        password: 'Tz3@wQ8nYb5cHm1R',
        now: now),
    Entry.create(name: 'Bank', password: 'Nv6#jE4pUd2gSk8W', now: now),
  ];
}

Future<void> _sized(WidgetTester tester, Size size, bool dark) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue =
      dark ? Brightness.dark : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Writes the rendered app to a PNG under tool/screens. Uses the golden
/// mechanism purely as a way to save a picture, so it must be run with
/// --update-goldens.
Future<void> _shot(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$outDir/$name.png'),
  );
}

// Scan QR code: the viewfinder on its own, over a stand-in for the camera
// picture, since a widget test has no camera. The sweeping line is caught
// part way down its travel.
void _captureViewfinder() {
  for (final dark in [false, true]) {
    final suffix = dark ? 'dark' : 'light';
    testWidgets('scan viewfinder ($suffix)', (tester) async {
      await _sized(tester, const Size(390, 844), dark);
      await tester.pumpWidget(MaterialApp(
        theme: dark ? VaultifyTheme.dark : VaultifyTheme.light,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          backgroundColor: Color(0xFF3B3F45),
          body: ScanViewfinder(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await _shot(tester, 'scan-viewfinder-$suffix');
    });
  }
}
