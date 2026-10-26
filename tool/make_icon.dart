// App icon: draws the Vaultify icon source PNGs into assets/icon/.
//
// Not a test of the app — it is a drawing script that happens to run on the
// Flutter test binding, because painting needs a Flutter engine. Re-run it
// only when the icon design changes:
//
//   flutter test tool/make_icon.dart
//   dart run flutter_launcher_icons
//
// Design: the V-monogram shield from lib/ui/brand/vaultify_mark.dart, white
// on a green rounded square. The shape itself lives in that one file so the
// icon and the mark drawn inside the app can never drift apart.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/ui/brand/vaultify_mark.dart';

/// Brand green, kept in step with `primary` in lib/ui/theme.dart.
const Color brandGreen = Color(0xFF1A9E5B);

const double canvas = kMarkCanvas;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write app icon sources', () async {
    // Rounded square for Android legacy, Windows and macOS.
    await _write('assets/icon/vaultify.png', rounded: true);
    // iOS supplies its own rounded mask and forbids transparency, so its
    // source is a plain opaque square.
    await _write('assets/icon/vaultify_ios.png', rounded: false);
    // Android adaptive foreground: mark only, transparent behind it, inset
    // so the system's circular/squircle mask never clips it.
    await _write(
      'assets/icon/vaultify_foreground.png',
      rounded: false,
      transparent: true,
      inset: 0.62,
    );
  });
}

/// Paints one icon variant and writes it as a PNG.
Future<void> _write(
  String path, {
  required bool rounded,
  bool transparent = false,
  double inset = 1.0,
}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, const Rect.fromLTWH(0, 0, canvas, canvas));

  if (!transparent) {
    final bg = Paint()..color = brandGreen;
    if (rounded) {
      // 22% corner radius reads as the usual rounded app-icon square.
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, canvas, canvas),
          const Radius.circular(canvas * 0.22),
        ),
        bg,
      );
    } else {
      c.drawRect(const Rect.fromLTWH(0, 0, canvas, canvas), bg);
    }
  }

  // Scale the mark about the canvas centre for the inset variant.
  c.save();
  c.translate(canvas / 2, canvas / 2);
  c.scale(inset);
  c.translate(-canvas / 2, -canvas / 2);
  c.drawPath(vaultifyMarkPath(), Paint()..color = const Color(0xFFFFFFFF));
  c.restore();

  final image = await recorder.endRecording().toImage(
    canvas.toInt(),
    canvas.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  stdout.writeln('wrote $path');
}
