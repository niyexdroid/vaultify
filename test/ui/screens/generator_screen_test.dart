import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/generator/generator.dart';

import '../fakes.dart';

// Generator screen tests: password on open, options regenerate, length
// limits, no-set hint, strength label, copy, save panel with duplicates,
// pasted passwords, and the desktop tabs / mobile bottom bar.
void main() {
  const pin = '12345678';

  // Generator: a tall view so the whole screen fits without scrolling.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<FakeVaultRepository> openUnlocked(WidgetTester tester,
      {bool mobile = false}) async {
    tallView(tester);
    final repo = FakeVaultRepository(secret: pin);
    await pumpVaultify(tester, repo: repo, mobile: mobile);
    if (mobile) {
      await tapDigits(tester, pin);
    } else {
      await tester.enterText(find.byType(TextField).first, pin);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    return repo;
  }

  String password(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('a password is generated on open, 16 long, Very strong',
      (tester) async {
    await openUnlocked(tester);
    expect(password(tester), hasLength(16));
    // 16 × log2(88) ≈ 103 bits.
    expect(find.text('Very strong'), findsOneWidget);
  });

  testWidgets('Generate and option changes make a new password',
      (tester) async {
    await openUnlocked(tester);
    final first = password(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pump();
    final second = password(tester);
    expect(second, isNot(first));

    // Only numbers left: the next password is digits only.
    for (final label in ['Uppercase', 'Lowercase', 'Symbols']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(password(tester), matches(RegExp(r'^[0-9]{16}$')));
    // 16 × log2(10) ≈ 53 bits.
    expect(find.text('Fair'), findsOneWidget);
  });

  testWidgets('no set selected shows the hint', (tester) async {
    await openUnlocked(tester);
    for (final label in ['Uppercase', 'Lowercase', 'Numbers', 'Symbols']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(find.text('Pick at least one character type'), findsOneWidget);

    // Custom ticked with characters clears it.
    await tester.tap(find.text('Custom'));
    await tester.pump();
    await tester.enterText(field('Characters to use, e.g. äöü€'), 'xy');
    await tester.pump();
    expect(find.text('Pick at least one character type'), findsNothing);
    expect(password(tester), matches(RegExp(r'^[xy]{16}$')));
  });

  testWidgets('length: − / + buttons and typed number up to 128',
      (tester) async {
    await openUnlocked(tester);
    await tester.tap(find.byTooltip('Longer'));
    await tester.pump();
    expect(password(tester), hasLength(17));
    await tester.tap(find.byTooltip('Shorter'));
    await tester.tap(find.byTooltip('Shorter'));
    await tester.pump();
    expect(password(tester), hasLength(15));

    final lengthField = find.byKey(const Key('lengthField'));
    await tester.enterText(lengthField, '100');
    await tester.pump();
    expect(password(tester), hasLength(100));

    // Over 128 or under 4 is pulled back into range on submit.
    await tester.enterText(lengthField, '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(password(tester), hasLength(GeneratorOptions.maxLength));
    await tester.enterText(lengthField, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(password(tester), hasLength(GeneratorOptions.minLength));
  });

  testWidgets('copy puts the password on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await openUnlocked(tester);
    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();
    expect(copied, password(tester));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('save needs a name, then saves and clears the fields',
      (tester) async {
    final repo = await openUnlocked(tester);
    await tester.tap(find.text('Save to vault'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(repo.saved, isEmpty);

    final generated = password(tester);
    await tester.enterText(field('Name'), 'Gmail');
    await tester.enterText(field('Username (optional)'), 'me@example.com');
    await tester.tap(find.text('Save to vault'));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.name, 'Gmail');
    expect(repo.saved.single.username, 'me@example.com');
    expect(repo.saved.single.password, generated);
    expect(find.widgetWithText(SnackBar, 'Saved'), findsOneWidget);
    expect(tester.widget<TextField>(field('Name')).controller!.text, isEmpty);
  });

  testWidgets('a pasted password can be saved', (tester) async {
    final repo = await openUnlocked(tester);
    await tester.enterText(find.byType(TextField).first, 'abc123');
    await tester.pump();
    expect(find.text('Weak'), findsOneWidget);
    await tester.enterText(field('Name'), 'Bank');
    await tester.tap(find.text('Save to vault'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.password, 'abc123');
  });

  testWidgets('duplicate name: Keep both adds (2), Replace overwrites',
      (tester) async {
    final repo = await openUnlocked(tester);
    Future<void> saveAs(String name) async {
      await tester.enterText(field('Name'), name);
      await tester.tap(find.text('Save to vault'));
      await tester.pumpAndSettle();
    }

    await saveAs('Gmail');
    await saveAs('gmail');
    expect(find.text('gmail is already saved'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect(repo.saved.map((e) => e.name), ['Gmail', 'gmail (2)']);

    await tester.enterText(find.byType(TextField).first, 'replacement-pw');
    await saveAs('Gmail');
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(2));
    expect(repo.saved.first.password, 'replacement-pw');

    // Cancel saves nothing.
    await saveAs('Gmail');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(2));
  });

  testWidgets('desktop tabs switch areas and keep the password',
      (tester) async {
    await openUnlocked(tester);
    final generated = password(tester);
    await tester.enterText(field('Name'), 'Gmail');
    await tester.tap(find.text('Save to vault'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Saved'));
    await tester.pumpAndSettle();
    expect(find.text('1 saved'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Generator'));
    await tester.pumpAndSettle();
    expect(password(tester), generated);
  });

  testWidgets('mobile: bottom bar instead of tabs', (tester) async {
    await openUnlocked(tester, mobile: true);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('0 saved'), findsOneWidget);
  });
}
