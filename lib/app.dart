import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/screens/damaged_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/unlock_screen.dart';
import 'ui/session.dart';
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
    final session = ref.watch(sessionProvider);
    return switch (session) {
      AsyncData(:final value) => switch (value.phase) {
          Phase.setup => const SetupScreen(),
          Phase.locked => UnlockScreen(type: value.unlockType!),
          Phase.damaged => DamagedScreen(hasBackup: value.hasBackup),
          Phase.unlocked => const UnlockedHome(),
        },
      AsyncError() => const _StartupError(),
      _ => const Scaffold(body: SizedBox.shrink()),
    };
  }
}

/// Unlocked home (Milestone 3 placeholder): title bar with the Lock button.
/// Milestone 4 replaces the body with the Generator and the shells.
class UnlockedHome extends ConsumerWidget {
  const UnlockedHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: c.primary),
            const SizedBox(width: Space.x1),
            const Text('Vaultify'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Lock',
            onPressed: () => ref.read(sessionProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Vault unlocked',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
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
