import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/backup.dart';
import 'package:vaultify/core/vault/entry.dart';
import 'package:vaultify/ui/screens/backup_import_screen.dart';

import '../fakes.dart';

// Backup export/import tests: Options → Export backup (PIN, backup password
// twice, Save window), Import backup (pick file, password, merge), and
// background lock staying off while the Save / Open window is open.
void main() {
  const pin = '12345678';
  const backupPassword = 'a long backup password';
  final now = DateTime.utc(2026, 10, 12);

  late FakeVaultRepository repo;
  late FakeSettingsStore store;
  late FakeBackupFiles files;

  Entry entry(String name, [String pw = 'pw']) =>
      Entry.create(name: name, password: pw, now: now);

  setUp(() {
    repo = FakeVaultRepository(secret: pin);
    store = FakeSettingsStore();
    files = FakeBackupFiles();
  });

  // Opens the app unlocked on the Options tab (desktop layout).
  Future<void> openOptions(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpVaultify(
      tester,
      repo: repo,
      store: store,
      backupFiles: files,
      clock: () => now,
    );
    await tester.enterText(find.byType(TextField).first, pin);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Options'));
    await tester.pumpAndSettle();
  }

  // Type into the page's field and press its filled button.
  Future<void> submit(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField).last, value);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  group('export', () {
    testWidgets('PIN, backup password twice, then the file is saved', (
      tester,
    ) async {
      repo.saved.addAll([entry('Gmail', 'secret-1'), entry('Bank')]);
      await openOptions(tester);
      await tapRow(tester, 'Export backup');
      expect(find.text('Enter your current PIN'), findsOneWidget);

      await submit(tester, '11112222');
      expect(find.textContaining('Wrong PIN.'), findsOneWidget);
      expect(store.saved.lockout.failedAttempts, 1);
      await submit(tester, pin);

      expect(find.text('Choose a backup password'), findsOneWidget);
      await submit(tester, 'too short');
      expect(find.textContaining('at least 12 characters'), findsOneWidget);
      await submit(tester, backupPassword);
      await submit(tester, 'something else entirely');
      expect(find.textContaining("didn't match"), findsOneWidget);

      await submit(tester, backupPassword);
      await submit(tester, backupPassword);
      expect(find.text('Backup saved'), findsOneWidget);
      expect(files.savedName, 'vaultify-backup-2026-10-12.vaultify');

      final back = await FakeBackupCodec().open(
        BackupFile.decode(files.savedText!),
        backupPassword,
      );
      expect(back.map((e) => e.password), ['secret-1', 'pw']);
    });

    testWidgets('an empty vault has nothing to export', (tester) async {
      await openOptions(tester);
      await tapRow(tester, 'Export backup');
      expect(find.text('No saved passwords to export yet'), findsOneWidget);
      expect(find.text('Enter your current PIN'), findsNothing);
    });

    testWidgets('cancelling the Save window lets you try again', (
      tester,
    ) async {
      repo.saved.add(entry('Gmail'));
      files.cancelSave = true;
      await openOptions(tester);
      await tapRow(tester, 'Export backup');
      await submit(tester, pin);
      await submit(tester, backupPassword);
      await submit(tester, backupPassword);
      expect(find.text('Your backup is ready'), findsOneWidget);
      expect(files.savedText, isNull);

      files.cancelSave = false;
      await tester.tap(find.text('Save backup file'));
      await tester.pumpAndSettle();
      expect(files.savedText, isNotNull);
      expect(find.text('Backup saved'), findsOneWidget);
    });
  });

  group('import', () {
    Future<String> backupOf(List<Entry> entries) =>
        FakeBackupCodec().seal(entries, backupPassword, now: now);

    testWidgets('wrong then right password merges the entries', (tester) async {
      repo.saved.add(entry('Gmail', 'old'));
      files.toPick = await backupOf([
        entry('Gmail', 'new'),
        entry('Bank'),
        entry('Shop'),
      ]);
      await openOptions(tester);
      await tapRow(tester, 'Import backup');
      expect(find.text('Enter the backup password'), findsOneWidget);
      expect(find.textContaining('12 Oct 2026'), findsOneWidget);

      await submit(tester, 'not the password');
      expect(find.text('Wrong backup password.'), findsOneWidget);
      // Backup passwords don't count toward the PIN's wrong tries.
      expect(store.saved.lockout.failedAttempts, 0);

      await submit(tester, backupPassword);
      expect(find.text('Imported 3 passwords · 1 renamed'), findsOneWidget);
      expect(repo.saved.map((e) => e.name), [
        'Gmail',
        'Gmail (2)',
        'Bank',
        'Shop',
      ]);
    });

    testWidgets('a file that is not a backup is refused', (tester) async {
      files.toPick = '{"format": "vaultify", "version": 1}';
      await openOptions(tester);
      await tapRow(tester, 'Import backup');
      expect(find.text("That file isn't a Vaultify backup"), findsOneWidget);
      expect(find.text('Enter the backup password'), findsNothing);
    });

    testWidgets('cancelling the Open window does nothing', (tester) async {
      await openOptions(tester);
      await tapRow(tester, 'Import backup');
      expect(find.text('Enter the backup password'), findsNothing);
      expect(find.text('Import backup'), findsOneWidget);
    });

    test('summary wording', () {
      MergeResult r(int a, int s, int n) =>
          MergeResult(entries: const [], added: a, skipped: s, renamed: n);
      expect(importSummary(r(1, 0, 0)), 'Imported 1 password');
      expect(
        importSummary(r(0, 2, 0)),
        'Nothing new to import · 2 were already saved',
      );
      expect(
        importSummary(r(2, 1, 1)),
        'Imported 2 passwords · 1 was already saved · 1 renamed',
      );
    });
  });

  group('background lock while the Save / Open window is open (mobile)', () {
    // Opens the app unlocked on the phone layout, with "lock immediately".
    Future<void> openMobileOptions(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store.saved = const Settings().copyWith(biometricOffered: true);
      await pumpVaultify(
        tester,
        repo: repo,
        store: store,
        backupFiles: files,
        mobile: true,
        clock: () => now,
      );
      await tapDigits(tester, pin);
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
    }

    // The system window covers the app: hidden, then back.
    void coverApp(WidgetTester tester) {
      files.whileOpen = () async {
        for (final s in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(s);
        }
      };
    }

    testWidgets('picking a file does not lock the vault', (tester) async {
      files.toPick = await FakeBackupCodec().seal(
        [entry('Bank')],
        backupPassword,
        now: now,
      );
      await openMobileOptions(tester);
      coverApp(tester);
      await tester.ensureVisible(find.text('Import backup'));
      await tapRow(tester, 'Import backup');
      expect(repo.unlocked, isTrue);
      expect(find.text('Enter the backup password'), findsOneWidget);
    });

    testWidgets('leaving the app any other way still locks', (tester) async {
      await openMobileOptions(tester);
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
      expect(repo.unlocked, isFalse);
    });
  });
}
