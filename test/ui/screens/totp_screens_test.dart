import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/totp/base32.dart';
import 'package:vaultify/core/totp/totp.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/ui/screens/totp_add_screen.dart';
import 'package:vaultify/ui/widgets/entry_row.dart';
import 'package:vaultify/ui/widgets/totp_code.dart';

import '../fakes.dart';

// TOTP code tests (Milestone 9): the live code and countdown on a saved
// row, copying it, and adding or removing the secret on desktop and phone.
void main() {
  const pin = '12345678';

  // The RFC 6238 test key, so the expected codes are the published ones.
  const key = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  const link = 'otpauth://totp/GitHub:ada@example.com?secret=$key'
      '&issuer=GitHub';

  DateTime at(int unixSeconds) =>
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);

  // TOTP codes: a moment inside the RFC 6238 step whose six-digit code is
  // 081804, with 10 seconds of that step left.
  final inStep = at(1111111100);

  // TOTP codes: just inside the next step, where the code is 050471.
  final nextStep = at(1111111111);

  TotpSecret secret() =>
      TotpSecret(key: decodeBase32(key), issuer: 'GitHub', account: 'ada');

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Entry entry(String name, {TotpSecret? totp}) => Entry.create(
      name: name,
      username: 'me@mail.com',
      password: '$name-secret',
      now: DateTime.utc(2026, 10, 3, 12),
      totp: totp);

  // Opens the app unlocked on Saved, with a clock the test controls.
  Future<FakeVaultRepository> openSaved(
    WidgetTester tester, {
    required List<Entry> entries,
    bool mobile = false,
    DateTime Function()? clock,
  }) async {
    tallView(tester);
    final repo = FakeVaultRepository(secret: pin)..saved.addAll(entries);
    await pumpVaultify(
      tester,
      repo: repo,
      mobile: mobile,
      clock: clock ?? () => inStep,
    );
    if (mobile) {
      await tapDigits(tester, pin);
    } else {
      await tester.enterText(find.byType(TextField).first, pin);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(mobile
        ? find.widgetWithText(NavigationDestination, 'Saved')
        : find.widgetWithText(Tab, 'Saved'));
    await tester.pumpAndSettle();
    return repo;
  }

  // The unlock page stays mounted behind the lock gate and has a shield
  // icon of its own, so row icons are looked for inside the row.
  Finder rowIcon(IconData icon) => find.descendant(
      of: find.byType(EntryRow), matching: find.byIcon(icon));

  // Clipboard: records what the app copies.
  List<String> watchClipboard(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return copied;
  }

  testWidgets('a saved row shows the live code, its account and the '
      'countdown', (tester) async {
    await openSaved(tester, entries: [entry('GitHub', totp: secret())]);

    // The code is the published RFC 6238 one, shown in two halves.
    expect(find.text('081 804'), findsOneWidget);
    expect(find.text('Two-factor code · GitHub · ada'), findsOneWidget);
    // 10 seconds left of this 30 second step.
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('the countdown ticks down and the code changes with the step',
      (tester) async {
    var now = inStep;
    await openSaved(
      tester,
      entries: [entry('GitHub', totp: secret())],
      clock: () => now,
    );
    expect(find.text('10'), findsOneWidget);

    // Later in the same step: a new countdown, the same code.
    now = inStep.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('081 804'), findsOneWidget);

    // Into the next step: a new code.
    now = nextStep;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('050 471'), findsOneWidget);
    expect(find.text('29'), findsOneWidget);
  });

  testWidgets('rows without a code show no code line', (tester) async {
    await openSaved(tester, entries: [entry('Gmail')]);
    expect(find.byType(TotpCodeView), findsNothing);
    expect(find.textContaining('Two-factor code'), findsNothing);
  });

  testWidgets('copy code puts the code on the clipboard (desktop)',
      (tester) async {
    final copied = watchClipboard(tester);
    await openSaved(tester, entries: [entry('GitHub', totp: secret())]);

    // The second copy icon in the row is the code's, under the password's.
    await tester.tap(rowIcon(Icons.copy_outlined).last);
    await tester.pumpAndSettle();

    expect(copied, ['081804']);
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('desktop: the shield icon adds a code from a pasted link',
      (tester) async {
    final repo = await openSaved(tester, entries: [entry('GitHub')]);

    await tester.tap(rowIcon(Icons.shield_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Two-factor code for GitHub'), findsOneWidget);
    // No camera button on desktop; pasting is the only way in.
    expect(find.text('Scan QR code'), findsNothing);

    await tester.enterText(find.byType(TextField).last, link);
    await tester.tap(find.widgetWithText(FilledButton, 'Add code'));
    await tester.pumpAndSettle();

    expect(find.text('Two-factor code added'), findsOneWidget);
    expect(repo.saved.single.totp!.key, decodeBase32(key));
    expect(repo.saved.single.totp!.issuer, 'GitHub');
    // The row now shows the live code.
    expect(find.text('081 804'), findsOneWidget);
  });

  testWidgets('the add page says what is wrong and stays open',
      (tester) async {
    await openSaved(tester, entries: [entry('GitHub')]);
    await tester.tap(rowIcon(Icons.shield_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'not a key! 189');
    await tester.tap(find.widgetWithText(FilledButton, 'Add code'));
    await tester.pumpAndSettle();

    expect(find.textContaining('setup key'), findsWidgets);
    expect(find.byType(TotpAddScreen), findsOneWidget);
  });

  testWidgets('desktop: removing a code asks first, then takes it away',
      (tester) async {
    final repo =
        await openSaved(tester, entries: [entry('GitHub', totp: secret())]);

    await tester.tap(rowIcon(Icons.shield));
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove the two-factor code for GitHub?'),
        findsOneWidget);

    // Cancel leaves it alone.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.hasTotp, isTrue);

    await tester.tap(rowIcon(Icons.shield));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(repo.saved.single.hasTotp, isFalse);
    expect(repo.saved.single.password, 'GitHub-secret');
    expect(find.text('Two-factor code removed'), findsOneWidget);
    expect(find.byType(TotpCodeView), findsNothing);
  });

  testWidgets('mobile: the sheet copies the code and can remove it',
      (tester) async {
    final copied = watchClipboard(tester);
    final repo = await openSaved(
      tester,
      entries: [entry('GitHub', totp: secret())],
      mobile: true,
    );

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(copied, ['081804']);

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove two-factor code'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.hasTotp, isFalse);
  });

  testWidgets('mobile: the sheet offers Add, and the add page offers the '
      'camera', (tester) async {
    await openSaved(tester, entries: [entry('GitHub')], mobile: true);

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('Copy code'), findsNothing);
    await tester.tap(find.text('Add two-factor code'));
    await tester.pumpAndSettle();

    expect(find.text('Scan QR code'), findsOneWidget);
  });

  test('a code is shown in two halves', () {
    expect(groupTotpCode('081804'), '081 804');
    expect(groupTotpCode('12345678'), '1234 5678');
  });
}
