import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/app.dart';
import 'package:vaultify/core/security/biometric_policy.dart';
import 'package:vaultify/core/settings/settings.dart';
import 'package:vaultify/core/vault/vault_file.dart';
import 'package:vaultify/platform/biometrics.dart';
import 'package:vaultify/ui/session.dart';

import '../fakes.dart';

// Mobile extras tests (Milestone 7): biometric unlock offer, scan unlock,
// failed-scan and 7-day limits, PIN change, Options switches and
// background lock.
void main() {
  const pin = '12345678';
  late DateTime now;
  late FakeVaultRepository repo;
  late FakeSettingsStore store;
  late FakeBiometrics bio;

  setUp(() {
    now = DateTime(2026, 10, 12, 9);
    repo = FakeVaultRepository(secret: pin);
    store = FakeSettingsStore();
    bio = FakeBiometrics();
  });

  // Biometric unlock is already on, with a key stored [pinAge] ago.
  void biometricsOn({Duration pinAge = Duration.zero, int failures = 0}) {
    store.saved = const Settings().copyWith(
      biometricEnabled: true,
      biometricOffered: true,
      biometricFailures: failures,
    );
    bio.record = BiometricRecord(
      key: fakeKeyFor(pin),
      secretEnteredAt: now.subtract(pinAge),
    ).encode();
  }

  // Opens the app on a phone-sized screen (tall so Options fits).
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpVaultify(tester,
        repo: repo,
        store: store,
        mobile: true,
        clock: () => now,
        biometrics: bio);
  }

  Future<void> typePin(WidgetTester tester, [String value = pin]) async {
    await tapDigits(tester, value);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
  }

  bool onUnlockScreen() => find.text('Unlock Vaultify').evaluate().isNotEmpty;
  final scanButton = find.text('Use fingerprint or face');
  final offer = find.text('Unlock with fingerprint or face?');

  // Background lock: the app leaving the screen and coming back.
  Future<void> leaveApp(WidgetTester tester) async {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
  }

  Future<void> returnToApp(WidgetTester tester) async {
    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
  }

  group('biometric offer', () {
    testWidgets('asked after the first PIN unlock; Turn on stores the key',
        (tester) async {
      await open(tester);
      await typePin(tester);
      expect(offer, findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(bio.prompts, 1);
      expect(store.saved.biometricEnabled, isTrue);
      expect(store.saved.biometricOffered, isTrue);
      final record = BiometricRecord.decode(bio.record)!;
      expect(record.key, fakeKeyFor(pin));
      expect(find.text('Biometric unlock on'), findsOneWidget);
    });

    testWidgets('Not now is remembered and not asked again', (tester) async {
      await open(tester);
      await typePin(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(store.saved.biometricOffered, isTrue);
      expect(store.saved.biometricEnabled, isFalse);
      expect(bio.record, isNull);

      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();
      await typePin(tester);
      expect(offer, findsNothing);
    });

    testWidgets('not asked on a phone without fingerprint or face',
        (tester) async {
      bio.available = false;
      await open(tester);
      await typePin(tester);
      expect(offer, findsNothing);
      expect(find.text('Save to vault'), findsOneWidget);
    });
  });

  group('biometric unlock', () {
    testWidgets('the scan prompt opens by itself and unlocks', (tester) async {
      biometricsOn();
      await open(tester);
      expect(bio.prompts, 1);
      expect(onUnlockScreen(), isFalse);
      expect(find.text('Save to vault'), findsOneWidget);
    });

    testWidgets('closing the prompt costs nothing; the button tries again',
        (tester) async {
      biometricsOn();
      bio.results.add(BiometricResult.cancelled);
      await open(tester);
      expect(onUnlockScreen(), isTrue);
      expect(store.saved.biometricFailures, 0);

      await tester.tap(scanButton);
      await tester.pumpAndSettle();
      expect(onUnlockScreen(), isFalse);
    });

    testWidgets('5 failed scans need the PIN; the PIN resets the count',
        (tester) async {
      biometricsOn();
      bio.results.addAll(List.filled(5, BiometricResult.failed));
      await open(tester);
      expect(find.text('Not recognised. Try again or use your PIN.'),
          findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.tap(scanButton);
        await tester.pumpAndSettle();
      }
      expect(store.saved.biometricFailures, 5);
      expect(find.text('Enter your PIN to continue.'), findsOneWidget);
      expect(scanButton, findsNothing);

      // The PIN still works, clears the failed scans and refreshes the key.
      now = now.add(const Duration(days: 1));
      await typePin(tester);
      expect(onUnlockScreen(), isFalse);
      expect(store.saved.biometricFailures, 0);
      expect(BiometricRecord.decode(bio.record)!.secretEnteredAt,
          now.toUtc());
    });

    testWidgets('a phone that locked its sensor needs the PIN',
        (tester) async {
      biometricsOn();
      bio.results.add(BiometricResult.lockedOut);
      await open(tester);
      expect(find.text('Enter your PIN to continue.'), findsOneWidget);
      expect(store.saved.biometricFailures, BiometricPolicy.maxFailures);
    });

    testWidgets('after 7 days the PIN is needed', (tester) async {
      biometricsOn(pinAge: const Duration(days: 7, minutes: 1));
      await open(tester);
      expect(onUnlockScreen(), isTrue);
      expect(find.text('Enter your PIN to continue.'), findsOneWidget);
      expect(bio.record, isNull);

      // Typing the PIN stores a fresh key, so the next lock can scan again.
      await typePin(tester);
      expect(BiometricRecord.decode(bio.record), isNotNull);
    });

    testWidgets('no scan is offered during a wrong-attempt wait',
        (tester) async {
      biometricsOn();
      bio.results.add(BiometricResult.cancelled);
      await open(tester);
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '00000000');
      }
      expect(find.textContaining('Too many wrong tries'), findsOneWidget);
      expect(scanButton, findsNothing);
    });

    testWidgets('changing the PIN drops the stored key', (tester) async {
      biometricsOn();
      await open(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(VaultifyApp)));
      await container
          .read(sessionProvider.notifier)
          .changeSecret('11223344', UnlockType.pin);
      expect(bio.record, isNull);
      expect(store.saved.biometricEnabled, isTrue);

      // Next unlock: no scan, the new PIN is required.
      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();
      expect(bio.prompts, 1);
      expect(scanButton, findsNothing);
      await typePin(tester, '11223344');
      expect(onUnlockScreen(), isFalse);
    });
  });

  group('Options (mobile)', () {
    Future<void> openOptions(WidgetTester tester) async {
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
    }

    testWidgets('biometric switch turns on with a scan and off again',
        (tester) async {
      store.saved = const Settings().copyWith(biometricOffered: true);
      await open(tester);
      await typePin(tester);
      await openOptions(tester);

      await tester.tap(find.text('Biometric unlock'));
      await tester.pumpAndSettle();
      expect(bio.prompts, 1);
      expect(store.saved.biometricEnabled, isTrue);
      expect(bio.record, isNotNull);

      await tester.tap(find.text('Biometric unlock'));
      await tester.pumpAndSettle();
      expect(store.saved.biometricEnabled, isFalse);
      expect(bio.record, isNull);
      expect(find.text('Biometric unlock off'), findsOneWidget);
    });

    testWidgets('a failed scan leaves biometric unlock off', (tester) async {
      store.saved = const Settings().copyWith(biometricOffered: true);
      bio.results.add(BiometricResult.failed);
      await open(tester);
      await typePin(tester);
      await openOptions(tester);
      await tester.tap(find.text('Biometric unlock'));
      await tester.pumpAndSettle();
      expect(store.saved.biometricEnabled, isFalse);
      expect(bio.record, isNull);
      expect(find.text("Couldn't turn on biometric unlock"), findsOneWidget);
    });

    testWidgets('switch is greyed out without fingerprint or face',
        (tester) async {
      bio.available = false;
      await open(tester);
      await typePin(tester);
      await openOptions(tester);
      expect(
          find.text('Set up a fingerprint or face in your phone settings first'),
          findsOneWidget);
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.onChanged, isNull);
    });

    testWidgets('background lock delay is offered and saved', (tester) async {
      await open(tester);
      await typePin(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await openOptions(tester);
      expect(find.text('Lock in background'), findsOneWidget);
      await tester.tap(find.text('Immediately'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 s').last);
      await tester.pumpAndSettle();
      expect(store.saved.backgroundLockSeconds, 30);
    });

    testWidgets('desktop has neither mobile option', (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpVaultify(tester, repo: repo, store: store, biometrics: bio);
      await tester.enterText(find.byType(TextField).first, pin);
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Options'));
      await tester.pumpAndSettle();
      expect(find.text('Biometric unlock'), findsNothing);
      expect(find.text('Lock in background'), findsNothing);
    });
  });

  group('background lock', () {
    Future<void> openUnlocked(WidgetTester tester, {int seconds = 0}) async {
      store.saved = const Settings()
          .copyWith(biometricOffered: true, backgroundLockSeconds: seconds);
      await open(tester);
      await typePin(tester);
      expect(onUnlockScreen(), isFalse);
    }

    testWidgets('Immediately: locks as soon as the app leaves the screen',
        (tester) async {
      await openUnlocked(tester);
      await leaveApp(tester);
      expect(repo.unlocked, isFalse);
      await returnToApp(tester);
      expect(onUnlockScreen(), isTrue);
    });

    testWidgets('30 s: a short trip away stays open, a long one locks',
        (tester) async {
      await openUnlocked(tester, seconds: 30);
      await leaveApp(tester);
      now = now.add(const Duration(seconds: 10));
      await returnToApp(tester);
      expect(onUnlockScreen(), isFalse);

      // Phone paused the timer: the time away is checked on return.
      await leaveApp(tester);
      now = now.add(const Duration(seconds: 31));
      await returnToApp(tester);
      expect(onUnlockScreen(), isTrue);
    });

    testWidgets('30 s: the timer locks while still away', (tester) async {
      await openUnlocked(tester, seconds: 30);
      await leaveApp(tester);
      await tester.pump(const Duration(seconds: 31));
      expect(repo.unlocked, isFalse);
      await returnToApp(tester);
      expect(onUnlockScreen(), isTrue);
    });

    testWidgets('the scan prompt waits until the app is back on screen',
        (tester) async {
      // Fingerprint on from the start: the first scan opens the vault.
      biometricsOn();
      await open(tester);
      expect(bio.prompts, 1);
      expect(onUnlockScreen(), isFalse);

      await leaveApp(tester);
      await tester.pumpAndSettle();
      expect(repo.unlocked, isFalse);
      expect(bio.prompts, 1);

      await returnToApp(tester);
      expect(bio.prompts, 2);
      expect(onUnlockScreen(), isFalse);
    });
  });
}
