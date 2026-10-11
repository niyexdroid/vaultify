import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/vault/vault_file.dart';

import '../fakes.dart';

// Setup screen tests: PIN and password rules, confirm step, the
// "I understand" warning, mismatch, and the mobile number pad.
void main() {
  Finder button(String label) => find.widgetWithText(FilledButton, label);

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(button(label)).onPressed != null;

  testWidgets('desktop: create a PIN after confirming and ticking the warning',
      (tester) async {
    final repo = FakeVaultRepository();
    await pumpVaultify(tester, repo: repo);
    expect(find.text('Create your PIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your PIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12345678');
    // Warning must be ticked before setup completes.
    expect(enabled(tester, 'Create vault'), isFalse);
    await tester.tap(find.text('I understand'));
    await tester.pump();
    expect(enabled(tester, 'Create vault'), isTrue);

    await tester.tap(button('Create vault'));
    await tester.pumpAndSettle();
    expect(repo.secret, '12345678');
    expect(repo.type, UnlockType.pin);
    expect(find.text('Save to vault'), findsOneWidget);
  });

  testWidgets('PIN rules: too short or too long is refused', (tester) async {
    await pumpVaultify(tester, repo: FakeVaultRepository());

    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create your PIN'), findsOneWidget);

    // The field itself stops at 12 digits and drops letters.
    await tester.enterText(find.byType(TextField), '1234567890123ab');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123456789012',
    );
  });

  testWidgets('password rule: at least 10 characters', (tester) async {
    final repo = FakeVaultRepository();
    await pumpVaultify(tester, repo: repo);
    await tester.tap(find.text('Use a master password instead'));
    await tester.pumpAndSettle();
    expect(find.text('Create your password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'short');
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create your password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'long enough pw');
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'long enough pw');
    await tester.tap(find.text('I understand'));
    await tester.pump();
    await tester.tap(button('Create vault'));
    await tester.pumpAndSettle();
    expect(repo.type, UnlockType.password);
  });

  testWidgets('mismatched confirm starts over', (tester) async {
    final repo = FakeVaultRepository();
    await pumpVaultify(tester, repo: repo);
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '87654321');
    await tester.tap(find.text('I understand'));
    await tester.pump();
    await tester.tap(button('Create vault'));
    await tester.pumpAndSettle();

    expect(find.text('Create your PIN'), findsOneWidget);
    expect(find.text("PINs didn't match. Try again."), findsOneWidget);
    expect(repo.secret, isNull);
  });

  testWidgets('mobile: PIN is entered on the number pad', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeVaultRepository();
    await pumpVaultify(tester, repo: repo, mobile: true);
    expect(find.byType(TextField), findsNothing);

    await tapDigits(tester, '24680135');
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    await tapDigits(tester, '24680135');
    await tester.tap(find.text('I understand'));
    await tester.pump();
    await tester.tap(button('Create vault'));
    await tester.pumpAndSettle();
    expect(repo.secret, '24680135');
  });
}
