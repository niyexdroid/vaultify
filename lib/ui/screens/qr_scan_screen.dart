import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';

/// Scan QR code (mobile): points the camera at a two-factor QR code and
/// pops with the `otpauth://` text it reads. Nothing is photographed,
/// stored or sent anywhere — the frames are read on the phone and dropped.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  // QR codes only, and the same code is not reported twice.
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Scan QR code: the first readable code wins; later frames are ignored
  // so the page can't pop twice.
  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.trim().isEmpty) continue;
      _handled = true;
      Navigator.pop(context, value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // Camera refused or missing: say so instead of a black screen.
            errorBuilder: (context, error) => _ScanProblem(
              message: switch (error.errorCode) {
                MobileScannerErrorCode.permissionDenied =>
                  'Vaultify needs camera permission to read a QR code. You '
                      'can also paste the setup key instead.',
                MobileScannerErrorCode.unsupported =>
                  "This phone's camera can't be used. Paste the setup key "
                      'instead.',
                _ => "The camera couldn't be opened. Paste the setup key "
                    'instead.',
              },
            ),
          ),
          // Scan QR code: the viewfinder drawn over the camera picture.
          // Taps belong to the camera underneath, so it ignores pointers.
          const IgnorePointer(child: ScanViewfinder()),
          // A hint strip at the bottom, over the camera picture.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: c.text.withValues(alpha: 0.6),
              padding: const EdgeInsets.all(Space.x2),
              child: SafeArea(
                top: false,
                child: Text(
                  'Point the camera at the QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.background),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scan QR code: the message shown in place of the camera picture when the
/// camera can't be used.
class _ScanProblem extends StatelessWidget {
  const _ScanProblem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 40, color: c.weak),
            const SizedBox(height: Space.x2),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Space.x2),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scan QR code: the viewfinder over the camera picture (public so a
/// widget test can drive it without a camera) — a square window
/// with the rest dimmed, corner brackets, and a line sweeping up and down
/// so the screen reads as a scanner and shows where to hold the code. It is
/// decoration only; reading the code does not depend on the code being
/// inside the square.
class ScanViewfinder extends StatefulWidget {
  const ScanViewfinder({super.key});

  /// Lets a widget test find the sweeping line without a camera.
  static const lineKey = Key('scan-sweep-line');

  @override
  State<ScanViewfinder> createState() => _ScanViewfinderState();
}

class _ScanViewfinderState extends State<ScanViewfinder>
    with SingleTickerProviderStateMixin {
  // One pass of the line takes 1.8 s, then it runs back the other way.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Accessibility: with "reduce motion" on, the line sits still in the
    // middle instead of sweeping.
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
      _sweep.value = 0.5;
    } else if (!_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        // A square about two thirds of the narrow side, within sane limits
        // so it stays usable on a small phone and on a tablet.
        final side = (box.biggest.shortestSide * 0.68).clamp(160.0, 280.0);
        // SizedBox.expand: without it the Stack would shrink to the square
        // and sit in the corner, taking the dimming with it.
        return SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ViewfinderPainter(side: side, bracket: c.primary),
                ),
              ),
              SizedBox(
                width: side,
                height: side,
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_sweep.value);
                    return Align(
                      // -1 is the top edge of the square, 1 the bottom.
                      alignment: Alignment(0, t * 2 - 1),
                      child: _SweepLine(color: c.primary),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Scan QR code: the sweeping line itself — brightest in the middle and
/// fading out at both ends, with a soft glow under it.
class _SweepLine extends StatelessWidget {
  const _SweepLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ScanViewfinder.lineKey,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: Space.x1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color.withValues(alpha: 0),
          ],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
        ],
      ),
    );
  }
}

/// Scan QR code: dims everything outside the square window and draws the
/// four corner brackets.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.side, required this.bracket});

  final double side;
  final Color bracket;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: side,
        height: side,
      ),
      const Radius.circular(Radii.card),
    );

    // Everything but the window, dimmed, so the eye goes to the square.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = const Color(0x8C000000),
    );

    // Corner brackets: one unbroken L at each corner, following the round
    // of the window so there is no gap at the turn.
    final pen = Paint()
      ..color = bracket
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = window.outerRect;
    _bracket(canvas, r.topLeft, 1, 1, pen);
    _bracket(canvas, r.topRight, -1, 1, pen);
    _bracket(canvas, r.bottomLeft, 1, -1, pen);
    _bracket(canvas, r.bottomRight, -1, -1, pen);
  }

  /// One corner bracket. It is drawn as the top-left corner every time and
  /// flipped into place, so all four stay identical.
  void _bracket(Canvas canvas, Offset at, double sx, double sy, Paint pen) {
    const arm = 22.0;
    const radius = Radii.card;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(sx, sy);
    canvas.drawPath(
      Path()
        ..moveTo(radius + arm, 0)
        ..lineTo(radius, 0)
        ..arcToPoint(
          const Offset(0, radius),
          radius: const Radius.circular(radius),
          clockwise: false,
        )
        ..lineTo(0, radius + arm),
      pen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.side != side || old.bracket != bracket;
}
