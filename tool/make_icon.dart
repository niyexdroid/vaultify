// App icon: draws the Vaultify icon source PNGs into assets/icon/.
//
// Not a test of the app — it is a drawing script that happens to run on the
// Flutter test binding, because painting needs a Flutter engine. Re-run it
// only when the icon design changes:
//
//   flutter test tool/make_icon.dart
//   dart run flutter_launcher_icons
//
// Design (SPEC.md "Window and layout sizes"): a white shield with a keyhole
// on a green rounded square. The keyhole is a real hole in the shield, so the
// green shows through it and the Android adaptive foreground stays clear.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Brand green, kept in step with `primary` in lib/ui/theme.dart.
const Color brandGreen = Color(0xFF1A9E5B);

const double canvas = 1024;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write app icon sources', () async {
    // Rounded square for Android legacy, Windows and macOS.
    await _write('assets/icon/vaultify.png', rounded: true, shield: true);
    // iOS supplies its own rounded mask and forbids transparency, so its
    // source is a plain opaque square.
    await _write('assets/icon/vaultify_ios.png', rounded: false, shield: true);
    // Android adaptive foreground: shield only, transparent behind it, inset
    // so the system's circular/squircle mask never clips it.
    await _write(
      'assets/icon/vaultify_foreground.png',
      rounded: false,
      shield: true,
      transparent: true,
      inset: 0.72,
    );
  });
}

/// Paints one icon variant and writes it as a PNG.
Future<void> _write(
  String path, {
  required bool rounded,
  required bool shield,
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

  if (shield) {
    c.save();
    // Scale the shield about the canvas centre for the inset variant.
    c.translate(canvas / 2, canvas / 2);
    c.scale(inset);
    c.translate(-canvas / 2, -canvas / 2);
    c.drawPath(_shieldWithKeyhole(), Paint()..color = const Color(0xFFFFFFFF));
    c.restore();
  }

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

/// The shield outline with the keyhole cut out of it.
Path _shieldWithKeyhole() =>
    Path.combine(PathOperation.difference, _shield(), _keyhole());

/// Shield: flat top with rounded corners, straight sides, curving to a point.
Path _shield() {
  const double left = 262, right = 762, top = 236, bottom = 806;
  const double corner = 58, straight = 250;
  return Path()
    ..moveTo(left + corner, top)
    ..lineTo(right - corner, top)
    ..quadraticBezierTo(right, top, right, top + corner)
    ..lineTo(right, top + straight)
    ..cubicTo(right, bottom - 170, right - 120, bottom - 66, canvas / 2, bottom)
    ..cubicTo(left + 120, bottom - 66, left, bottom - 170, left, top + straight)
    ..lineTo(left, top + corner)
    ..quadraticBezierTo(left, top, left + corner, top)
    ..close();
}

/// Keyhole: a round hole over a tapered slot, centred on the shield.
Path _keyhole() {
  const double cx = canvas / 2, cy = 452, radius = 74;
  const double slotTop = cy + 36, slotBottom = 660;
  const double topHalf = 30, bottomHalf = 48;
  return Path()
    ..addOval(
      const Rect.fromLTRB(cx - radius, cy - radius, cx + radius, cy + radius),
    )
    ..moveTo(cx - topHalf, slotTop)
    ..lineTo(cx + topHalf, slotTop)
    ..lineTo(cx + bottomHalf, slotBottom)
    ..lineTo(cx - bottomHalf, slotBottom)
    ..close();
}
