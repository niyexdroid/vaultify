import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/ui/widgets/entry_row.dart';

import '../fakes.dart';

// Saved screen tests (Milestone 5): empty state, rows, search, sort, show
// (re-hides after 10 s), copy, delete, desktop row icons and mobile sheet.
void main() {
  const pin = '12345678';

  // Saved screen: a tall view so every row fits without scrolling.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Entry entry(String name, String username, String password, int day) =>
      Entry.create(
          name: name,
          username: username,
          password: password,
          now: DateTime.utc(2026, 10, day, 12));

  // Opens the app unlocked on the Saved area with [entries] in the vault.
  Future<(FakeVaultRepository, FakeSettingsStore)> openSaved(
    WidgetTester tester, {
    List<Entry> entries = const [],
    bool mobile = false,
  }) async {
    tallView(tester);
    final repo = FakeVaultRepository(secret: pin)..saved.addAll(entries);
    final store = FakeSettingsStore();
    await pumpVaultify(tester, repo: repo, store: store, mobile: mobile);
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
    return (repo, store);
  }

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

  final gmail = entry('Gmail', 'me@mail.com', 'gmail-secret', 3);
  final bank = entry('bank', '', 'bank-secret', 5);

  Finder rowOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(EntryRow));

  List<String> rowNames(WidgetTester tester) => [
        for (final r in tester.widgetList<EntryRow>(find.byType(EntryRow)))
          r.entry.name
      ];

  testWidgets('empty vault shows "Save your first password" and opens the '
      'Generator', (tester) async {
    await openSaved(tester);
    expect(find.text('Save your first password'), findsOneWidget);
    await tester.tap(find.text('Open generator'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Generate'), findsOneWidget);
    expect(find.text('Save your first password'), findsNothing);
  });

  testWidgets('rows are masked, A–Z, with username or "No username" and date',
      (tester) async {
    await openSaved(tester, entries: [gmail, bank]);
    expect(find.text('2 saved'), findsOneWidget);
    expect(rowNames(tester), ['bank', 'Gmail']);
    expect(find.text(maskedPassword), findsNWidgets(2));
    expect(find.text('me@mail.com · 3 Oct 2026'), findsOneWidget);
    expect(find.text('No username · 5 Oct 2026'), findsOneWidget);
    expect(find.text('gmail-secret'), findsNothing);
  });

  testWidgets('search filters by name or username and shows "x of y"',
      (tester) async {
    await openSaved(tester, entries: [gmail, bank]);
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'BAN');
    await tester.pump();
    expect(rowNames(tester), ['bank']);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'me@');
    await tester.pump();
    expect(rowNames(tester), ['Gmail']);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('0 of 2'), findsOneWidget);
  });

  testWidgets('sort newest first is applied and saved', (tester) async {
    final zoo = entry('Zoo', '', 'zoo-secret', 9);
    final (_, store) = await openSaved(tester, entries: [gmail, bank, zoo]);
    expect(rowNames(tester), ['bank', 'Gmail', 'Zoo']);
    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest first').last);
    await tester.pumpAndSettle();
    // Zoo 9 Oct, bank 5 Oct, Gmail 3 Oct.
    expect(rowNames(tester), ['Zoo', 'bank', 'Gmail']);
    expect(store.saved.sortOrder, SortOrder.newestFirst);
  });

  testWidgets('Show reveals the password, then it re-hides after 10 s',
      (tester) async {
    await openSaved(tester, entries: [gmail]);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.text('gmail-secret'), findsOneWidget);
    expect(find.text(maskedPassword), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('gmail-secret'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('gmail-secret'), findsNothing);
    expect(find.text(maskedPassword), findsOneWidget);
  });

  testWidgets('desktop icons copy the password and the username',
      (tester) async {
    final copied = watchClipboard(tester);
    await openSaved(tester, entries: [gmail]);
    final row = rowOf('Gmail');
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip('Copy password')));
    await tester.pump();
    expect(find.text('Password copied'), findsOneWidget);
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip('Copy username')));
    await tester.pump();
    expect(copied, ['gmail-secret', 'me@mail.com']);
    expect(find.text('Username copied'), findsOneWidget);
  });

  testWidgets('Delete asks first; Cancel keeps, Delete removes',
      (tester) async {
    final (repo, _) = await openSaved(tester, entries: [gmail, bank]);
    Finder deleteIcon() => find.descendant(
        of: rowOf('Gmail'), matching: find.byTooltip('Delete'));

    await tester.tap(deleteIcon());
    await tester.pumpAndSettle();
    expect(find.text('Delete Gmail?'), findsOneWidget);
    expect(find.text("This can't be undone."), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(2));

    await tester.tap(deleteIcon());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.saved.map((e) => e.name), ['bank']);
    expect(rowNames(tester), ['bank']);
    expect(find.text('1 saved'), findsOneWidget);
  });

  testWidgets('mobile: no row icons; tap opens the actions sheet',
      (tester) async {
    final copied = watchClipboard(tester);
    final (repo, _) =
        await openSaved(tester, entries: [gmail, bank], mobile: true);
    expect(find.byTooltip('Delete'), findsNothing);

    // Show from the sheet.
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    for (final action in [
      'Show password',
      'Copy password',
      'Copy username',
      'Delete',
    ]) {
      expect(find.text(action), findsOneWidget);
    }
    await tester.tap(find.text('Show password'));
    await tester.pumpAndSettle();
    expect(find.text('gmail-secret'), findsOneWidget);

    // Copy username from the sheet; disabled when there is none.
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy username'));
    await tester.pumpAndSettle();
    expect(copied, ['me@mail.com']);
    await tester.tap(find.text('bank'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Copy username'))
            .enabled,
        isFalse);

    // Delete from the sheet, after confirming.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete bank?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.saved.map((e) => e.name), ['Gmail']);

    // Let the shown password's 10 s timer finish.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('mobile: long-press copies the password', (tester) async {
    final copied = watchClipboard(tester);
    await openSaved(tester, entries: [gmail], mobile: true);
    await tester.longPress(find.text('Gmail'));
    await tester.pump();
    expect(copied, ['gmail-secret']);
    expect(find.text('Password copied'), findsOneWidget);
  });
}
