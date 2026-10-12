import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/generator/generator.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/ui/screens/options_screen.dart';

import '../fakes.dart';

// Options and protection tests (Milestone 6): change PIN / switch to a
// password, wrong current PIN limits, auto-lock, keyboard shortcuts,
// clipboard clearing, status line and generator defaults.
void main() {
  const pin = '12345678';

  // A tall view so every Options row fits without scrolling.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Opens the app unlocked (desktop layout) with a controllable clock.
  Future<(FakeVaultRepository, FakeSettingsStore)> openUnlocked(
    WidgetTester tester, {
    DateTime Function()? clock,
    Settings settings = const Settings(),
    List<Entry> entries = const [],
  }) async {
    tallView(tester);
    final repo = FakeVaultRepository(secret: pin)..saved.addAll(entries);
    final store = FakeSettingsStore()..saved = settings;
    await pumpVaultify(tester, repo: repo, store: store, clock: clock);
    await tester.enterText(find.byType(TextField).first, pin);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    return (repo, store);
  }

  Future<void> openOptions(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(Tab, 'Options'));
    await tester.pumpAndSettle();
  }

  // Change PIN page: type into the field and press the filled button.
  Future<void> submit(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField).last, value);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  // Clipboard: a fake system clipboard the app reads and writes.
  List<String> fakeClipboard(WidgetTester tester) {
    final writes = <String>[];
    String? current;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        current = (call.arguments as Map)['text'] as String;
        writes.add(current!);
      } else if (call.method == 'Clipboard.getData') {
        return {'text': current};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return writes;
  }

  bool onUnlockScreen() => find.text('Unlock Vaultify').evaluate().isNotEmpty;

  group('change PIN or password', () {
    testWidgets('needs the current PIN, then the new one twice',
        (tester) async {
      final (repo, store) = await openUnlocked(tester);
      await openOptions(tester);
      await tester.tap(find.text('Change PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your current PIN'), findsOneWidget);

      await submit(tester, '11112222');
      expect(find.textContaining('Wrong PIN.'), findsOneWidget);
      expect(store.saved.lockout.failedAttempts, 1);

      await submit(tester, pin);
      expect(find.text('Choose your new PIN'), findsOneWidget);
      expect(store.saved.lockout.failedAttempts, 0);

      await submit(tester, '123');
      expect(find.textContaining('Use 6–12 digits'), findsOneWidget);
      await submit(tester, '24682468');
      await submit(tester, '99999999');
      expect(find.textContaining("didn't match"), findsOneWidget);

      await submit(tester, '24682468');
      await submit(tester, '24682468');
      expect(repo.secret, '24682468');
      expect(find.text('PIN changed'), findsOneWidget);
      expect(find.text('Change PIN'), findsOneWidget); // back on Options
    });

    testWidgets('switch to a master password', (tester) async {
      final (repo, store) = await openUnlocked(tester);
      await openOptions(tester);
      await tester.tap(find.text('Use a master password instead'));
      await tester.pumpAndSettle();
      await submit(tester, pin);
      expect(find.text('Choose your new password'), findsOneWidget);
      await submit(tester, 'a long master password');
      await submit(tester, 'a long master password');

      expect(repo.type, UnlockType.password);
      expect(store.saved.unlockType, UnlockType.password);
      expect(find.text('Password changed'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Use a PIN instead'), findsOneWidget);
    });

    testWidgets('5 wrong current PINs lock the app with a wait',
        (tester) async {
      final (_, store) = await openUnlocked(tester);
      await openOptions(tester);
      await tester.tap(find.text('Change PIN'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await submit(tester, '11112222');
      }
      expect(onUnlockScreen(), isTrue);
      expect(find.textContaining('Too many wrong tries'), findsOneWidget);
      expect(store.saved.lockout.failedAttempts, 5);
    });
  });

  group('auto-lock', () {
    testWidgets('locks after the idle time and closes open dialogs',
        (tester) async {
      var now = DateTime(2026, 10, 12, 9);
      await openUnlocked(tester,
          clock: () => now,
          entries: [
            Entry.create(name: 'Gmail', password: 'pw', now: now),
          ]);
      await tester.tap(find.widgetWithText(Tab, 'Saved'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Gmail?'), findsOneWidget);

      now = now.add(const Duration(minutes: 4, seconds: 58));
      await tester.pump(const Duration(seconds: 1));
      expect(onUnlockScreen(), isFalse);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(onUnlockScreen(), isTrue);
      expect(find.text('Delete Gmail?'), findsNothing);
    });

    testWidgets('activity restarts the idle time', (tester) async {
      var now = DateTime(2026, 10, 12, 9);
      await openUnlocked(tester, clock: () => now);
      now = now.add(const Duration(minutes: 4));
      await tester.tap(find.widgetWithText(Tab, 'Saved'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(onUnlockScreen(), isFalse);
    });

    testWidgets('the auto-lock choice is saved', (tester) async {
      final (_, store) = await openUnlocked(tester);
      await openOptions(tester);
      await tester.tap(find.text('5 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min').last);
      await tester.pumpAndSettle();
      expect(store.saved.autoLockMinutes, 15);
    });
  });

  group('keyboard shortcuts', () {
    testWidgets('Ctrl+L locks', (tester) async {
      await openUnlocked(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(onUnlockScreen(), isTrue);
    });

    testWidgets('Ctrl+G opens the Generator with a new password',
        (tester) async {
      await openUnlocked(tester);
      String password() => tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!
          .text;
      final before = password();
      await openOptions(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Generate'), findsOneWidget);
      expect(password(), isNot(before));
    });

    testWidgets('Ctrl+F opens Saved with the cursor in search',
        (tester) async {
      await openUnlocked(tester, entries: [
        Entry.create(name: 'Gmail', password: 'pw', now: DateTime(2026)),
      ]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final search = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Search'));
      expect(search.focusNode!.hasFocus, isTrue);
    });
  });

  group('clipboard clearing', () {
    testWidgets('clears a copied password after 30 s', (tester) async {
      final writes = fakeClipboard(tester);
      await openUnlocked(tester);
      await tester.tap(find.byTooltip('Copy password'));
      await tester.pump();
      expect(writes, hasLength(1));
      await tester.pump(const Duration(seconds: 29));
      expect(writes, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(writes.last, '');
    });

    testWidgets('leaves something copied since alone', (tester) async {
      final writes = fakeClipboard(tester);
      await openUnlocked(tester);
      await tester.tap(find.byTooltip('Copy password'));
      await tester.pump();
      await Clipboard.setData(const ClipboardData(text: 'other'));
      await tester.pump(const Duration(seconds: 30));
      expect(writes.last, 'other');
    });

    testWidgets('Off never clears', (tester) async {
      final writes = fakeClipboard(tester);
      await openUnlocked(tester,
          settings: const Settings(clipboardClearSeconds: 0));
      await tester.tap(find.byTooltip('Copy password'));
      await tester.pump(const Duration(minutes: 2));
      expect(writes, hasLength(1));
      expect(writes.single, isNotEmpty);
    });

    testWidgets('Saved status line shows the countdown and auto-lock time',
        (tester) async {
      fakeClipboard(tester);
      await openUnlocked(tester, entries: [
        Entry.create(name: 'Gmail', password: 'pw', now: DateTime(2026)),
      ]);
      await tester.tap(find.widgetWithText(Tab, 'Saved'));
      await tester.pumpAndSettle();
      expect(find.text('Locks after 5 min'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy password'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Clipboard clears in'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      expect(find.textContaining('Clipboard clears in'), findsNothing);
    });
  });

  group('generator defaults and About', () {
    testWidgets('current generator settings become the defaults',
        (tester) async {
      final (_, store) = await openUnlocked(tester);
      await tester.tap(find.text('Symbols'));
      await tester.pump();
      await openOptions(tester);
      await tester.tap(find.text('Use current generator settings'));
      await tester.pumpAndSettle();
      expect(store.saved.generator.symbols, isFalse);
      expect(
          find.text('Uppercase, lowercase, numbers · 16 characters'),
          findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(store.saved.generator.symbols, isTrue);
    });

    testWidgets('About says the vault stays on this device', (tester) async {
      await openUnlocked(tester);
      await openOptions(tester);
      expect(find.textContaining('lives only on this device'), findsOneWidget);
      expect(find.text('Open folder'), findsOneWidget);
    });

    test('describeGeneratorOptions', () {
      expect(describeGeneratorOptions(const GeneratorOptions()),
          'Uppercase, lowercase, numbers, symbols · 16 characters');
      expect(
          describeGeneratorOptions(const GeneratorOptions(
              uppercase: false,
              lowercase: false,
              numbers: false,
              symbols: false)),
          'No character types · 16 characters');
    });
  });
}
