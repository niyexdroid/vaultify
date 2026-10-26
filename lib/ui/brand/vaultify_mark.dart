/// Brand mark: the one definition of the Vaultify logo.
///
/// The mark is a V-monogram shield — the V of "Vaultify" drawn as two tapered
/// arms meeting at a point, with a keyhole sitting in the opening between
/// them. It is defined once here as a [Path] on a 1024 reference square so
/// that the app icon (tool/make_icon.dart) and every on-screen use are the
/// same shape; change it here and both follow.
///
/// Decided 2026-10-26: a V-monogram rather than a plain shield, because a
/// bare shield is what every other password manager uses.
library;

import 'package:flutter/widgets.dart';

/// The square the mark is drawn on. All coordinates below are in these units.
const double kMarkCanvas = 1024;

// Geometry of the V. Kept as named constants because the keyhole has to stay
// inside the opening between the arms: widen the arms and the keyhole must
// shrink or move up with them.
// The V is placed a little below the middle of the square on purpose: it is
// widest at the top, so its visual weight sits high and a geometrically
// centred mark looks like it is drifting upwards.
const double _armTop = 300; // where both arms are cut off square
const double _outerLeft = 236, _outerRight = 788;
const double _innerLeft = 336, _innerRight = 688;
const double _apexY = 800; // the point of the V
const double _innerApexY = 630;
const double _centreX = kMarkCanvas / 2;

/// The complete mark: the two arms of the V with the keyhole cut out of the
/// space between them, as a single path.
///
/// The keyhole is part of the same path and wound so that it reads as solid
/// where the arms are not, which lets the whole mark be painted with one
/// colour and still look right on any background.
Path vaultifyMarkPath({double size = kMarkCanvas}) {
  final path = Path()
    ..addPath(_vArms(), Offset.zero)
    ..addPath(_keyhole(), Offset.zero);
  if (size == kMarkCanvas) return path;
  final scale = size / kMarkCanvas;
  return path.transform(Matrix4.diagonal3Values(scale, scale, 1).storage);
}

/// The V itself: outer edges bow out slightly so the arms read as a shield
/// rather than a plain chevron; inner edges run straight to a point that sits
/// above the outer point, which is what gives the arms their taper.
Path _vArms() => Path()
  ..moveTo(_outerLeft, _armTop)
  // Outer left edge, sweeping down to the point.
  ..cubicTo(298, 476, 388, 648, _centreX, _apexY)
  // Outer right edge, back up to the top. Mirrors the left.
  ..cubicTo(kMarkCanvas - 388, 648, kMarkCanvas - 298, 476, _outerRight, _armTop)
  // Square-cut top of the right arm.
  ..lineTo(_innerRight, _armTop)
  // Inner right edge, down to the inner point.
  ..lineTo(_centreX, _innerApexY)
  // Inner left edge, back up to the top of the left arm.
  ..lineTo(_innerLeft, _armTop)
  ..close();

/// Keyhole: a round hole over a tapered slot, sitting in the opening between
/// the arms. Placed high enough that the narrowing V never crowds it.
Path _keyhole() {
  const double cy = 420, radius = 70;
  const double slotTop = 466, slotBottom = 532;
  const double topHalf = 25, bottomHalf = 36;
  return Path()
    ..addOval(
      const Rect.fromLTRB(
        _centreX - radius,
        cy - radius,
        _centreX + radius,
        cy + radius,
      ),
    )
    ..moveTo(_centreX - topHalf, slotTop)
    ..lineTo(_centreX + topHalf, slotTop)
    ..lineTo(_centreX + bottomHalf, slotBottom)
    ..lineTo(_centreX - bottomHalf, slotBottom)
    ..close();
}

/// Brand mark widget: draws the logo at [size] in [color].
///
/// Used in the title bar and on the unlock and setup screens. It paints the
/// shared path rather than a PNG, so it stays crisp at any size and needs no
/// asset bundled.
class VaultifyMark extends StatelessWidget {
  const VaultifyMark({super.key, this.size = 24, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(color)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      vaultifyMarkPath(size: size.shortestSide),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
