import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/ui/screens/qr_scan_screen.dart';
import 'package:vaultify/ui/theme.dart';

// Scan QR code: the viewfinder is driven here on its own, because the scan
// screen itself needs a camera that a widget test does not have.
Widget _host({bool reduceMotion = false}) => MaterialApp(
      theme: VaultifyTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: const Scaffold(body: ScanViewfinder()),
      ),
    );

// Where the sweeping line sits inside the square, top to bottom.
double _lineY(WidgetTester tester) =>
    tester.getCenter(find.byKey(ScanViewfinder.lineKey)).dy;

void main() {
  testWidgets('scanner line sweeps down and back up', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    final start = _lineY(tester);

    await tester.pump(const Duration(milliseconds: 900));
    final middle = _lineY(tester);
    expect(middle, greaterThan(start), reason: 'the line should travel down');

    await tester.pump(const Duration(milliseconds: 900));
    final end = _lineY(tester);
    expect(end, greaterThan(middle));

    // Past the turn it comes back up instead of jumping to the top.
    await tester.pump(const Duration(milliseconds: 900));
    expect(_lineY(tester), lessThan(end));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion parks the line instead of sweeping it',
      (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pump();
    final parked = _lineY(tester);

    await tester.pump(const Duration(milliseconds: 900));
    expect(_lineY(tester), parked);

    await tester.pumpWidget(const SizedBox());
  });
}
