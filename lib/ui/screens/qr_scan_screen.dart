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
