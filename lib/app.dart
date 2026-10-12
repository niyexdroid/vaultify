import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/auto_lock_scope.dart';
import 'ui/providers.dart';
import 'ui/screens/damaged_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/unlock_screen.dart';
import 'ui/session.dart';
import 'ui/shell/desktop_shell.dart';
import 'ui/shell/mobile_shell.dart';
import 'ui/theme.dart';

class VaultifyApp extends StatelessWidget {
  const VaultifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vaultify',
      debugShowCheckedModeBanner: false,
      theme: VaultifyTheme.light,
      darkTheme: VaultifyTheme.dark,
      themeMode: ThemeMode.system,
      home: const LockGate(),
    );
  }
}

/// Lock gate: shows setup, unlock, the damaged-vault screen or the app,
/// depending on the session. Locking always lands back here on unlock.
class LockGate extends ConsumerWidget {
  const LockGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lock: close any dialog, sheet or page (e.g. "Delete Gmail?" or
    // Change PIN) left open over the app, so nothing shows over Unlock.
    ref.listen(sessionProvider.select((s) => s.value?.phase), (prev, next) {
      if (prev == Phase.unlocked && next != Phase.unlocked) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final session = ref.watch(sessionProvider);
    return switch (session) {
      AsyncData(:final value) => switch (value.phase) {
          Phase.setup => const SetupScreen(),
          Phase.locked => UnlockScreen(type: value.unlockType!),
          Phase.damaged => DamagedScreen(hasBackup: value.hasBackup),
          Phase.unlocked => const AutoLockScope(child: UnlockedHome()),
        },
      AsyncError() => const _StartupError(),
      _ => const Scaffold(body: SizedBox.shrink()),
    };
  }
}

/// Unlocked home: desktop shell (tabs) on Windows and macOS, mobile shell
/// (bottom bar) on Android and iOS.
class UnlockedHome extends ConsumerWidget {
  const UnlockedHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(mobileLayoutProvider)
        ? const MobileShell()
        : const DesktopShell();
  }
}

/// Lock gate: shown if the app folder can't be read at start-up.
class _StartupError extends StatelessWidget {
  const _StartupError();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Text(
            "Vaultify couldn't open its data folder.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
