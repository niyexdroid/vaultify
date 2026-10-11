import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/vault/vault_file.dart';

import '../fakes.dart';

// Unlock screen tests: right and wrong PIN, tries-left message, the wait
// after 5 wrong tries with its countdown, lock, and the mobile number pad.
void main() {
  const pin = '12345678';
  Finder unlockButton() => find.widgetWithText(FilledButton, 'Unlock');

  Future<void> tryPin(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField), value);
    await tester.tap(unlockButton());
    // Plain pumps: the wait countdown keeps redrawing, so never "settles".
    await tester.pump();
    await tester.pump();
  }

  testWidgets('right PIN unlocks; Lock returns to unlock', (tester) async {
    final repo = FakeVaultRepository(secret: pin);
    await pumpVaultify(tester, repo: repo);
    expect(find.text('Unlock Vaultify'), findsOneWidget);

    await tryPin(tester, pin);
    expect(find.text('Save to vault'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock Vaultify'), findsOneWidget);
    expect(repo.unlocked, isFalse);
  });

  testWidgets('wrong PIN never shows the vault and counts down tries',
      (tester) async {
    await pumpVaultify(tester, repo: FakeVaultRepository(secret: pin));
    await tryPin(tester, '11111111');
    expect(find.text('Save to vault'), findsNothing);
    expect(find.text('Wrong PIN. 4 tries left before a wait.'), findsOneWidget);

    await tryPin(tester, '22222222');
    expect(find.text('Wrong PIN. 3 tries left before a wait.'), findsOneWidget);
  });

  testWidgets('too-short PIN does not cost a try', (tester) async {
    final repo = FakeVaultRepository(secret: pin);
    await pumpVaultify(tester, repo: repo);
    await tryPin(tester, '123');
    expect(repo.tried, isEmpty);
    expect(find.text('Your PIN is 6–12 digits.'), findsOneWidget);
  });

  testWidgets('5 wrong tries show the wait, then it counts down and ends',
      (tester) async {
    var now = DateTime.utc(2026, 10, 11, 12);
    final repo = FakeVaultRepository(secret: pin);
    await pumpVaultify(tester, repo: repo, clock: () => now);

    for (var i = 0; i < 5; i++) {
      await tryPin(tester, '00000000');
    }
    expect(find.text('Too many wrong tries. Try again in 0:30.'), findsOneWidget);
    expect(tester.widget<FilledButton>(unlockButton()).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Too many wrong tries. Try again in 0:20.'), findsOneWidget);

    now = now.add(const Duration(seconds: 21));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Too many wrong tries'), findsNothing);

    await tryPin(tester, pin);
    expect(find.text('Save to vault'), findsOneWidget);
  });

  testWidgets('a running wait is shown after a restart', (tester) async {
    final now = DateTime.utc(2026, 10, 11, 12);
    final store = FakeSettingsStore();
    store.saved = store.saved.copyWith(
      lockout: store.saved.lockout
          .recordFailure(now)
          .recordFailure(now)
          .recordFailure(now)
          .recordFailure(now)
          .recordFailure(now),
    );
    await pumpVaultify(tester,
        repo: FakeVaultRepository(secret: pin), store: store, clock: () => now);
    expect(find.text('Too many wrong tries. Try again in 0:30.'), findsOneWidget);
  });

  testWidgets('password vault asks for the master password', (tester) async {
    await pumpVaultify(tester,
        repo: FakeVaultRepository(
            secret: 'long enough pw', type: UnlockType.password));
    expect(find.text('Master password'), findsOneWidget);
    await tryPin(tester, 'wrong password!');
    expect(find.text('Wrong password. 4 tries left before a wait.'),
        findsOneWidget);
    await tryPin(tester, 'long enough pw');
    expect(find.text('Save to vault'), findsOneWidget);
  });

  testWidgets('mobile: unlock with the number pad', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpVaultify(tester,
        repo: FakeVaultRepository(secret: pin), mobile: true);
    await tapDigits(tester, '12345679');
    // Delete fixes the last digit.
    await tester.tap(find.byTooltip('Delete digit'));
    await tester.pump();
    await tapDigits(tester, '8');
    await tester.tap(unlockButton());
    await tester.pumpAndSettle();
    expect(find.text('Save to vault'), findsOneWidget);
  });
}
