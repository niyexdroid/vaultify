import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand/vaultify_mark.dart';
import '../screens/generator_screen.dart';
import '../screens/options_screen.dart';
import '../screens/saved_screen.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/content_width.dart';

/// App areas: Generator, Saved and Options, in tab / bottom-bar order.
enum AppArea {
  generator('Generator', Icons.password, Icons.password),
  saved('Saved', Icons.key_outlined, Icons.key),
  options('Options', Icons.tune_outlined, Icons.tune);

  const AppArea(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// App areas: which area is showing. Shared so a screen can switch areas
/// (the empty Saved screen opens the Generator); back to Generator on lock.
final currentAreaProvider =
    NotifierProvider<CurrentArea, AppArea>(CurrentArea.new);

class CurrentArea extends Notifier<AppArea> {
  @override
  AppArea build() {
    ref.watch(sessionProvider.select((s) => s.value?.phase));
    return AppArea.generator;
  }

  void show(AppArea area) => state = area;
}

/// App areas: every area's screen kept alive in an IndexedStack, so
/// switching tabs keeps the generated password and typed names.
class AreaStack extends StatelessWidget {
  const AreaStack({super.key, required this.current});

  final AppArea current;

  @override
  Widget build(BuildContext context) {
    // Content width cap: applied once here so all three areas are centred and
    // never stretch across a maximised desktop window.
    return IndexedStack(
      index: current.index,
      children: const [
        ContentWidth(child: GeneratorScreen()),
        ContentWidth(child: SavedScreen()),
        ContentWidth(child: OptionsScreen()),
      ],
    );
  }
}

/// Title bar: green V-monogram mark + "Vaultify", Lock button on the right.
/// [bottom] holds the desktop tabs.
class VaultifyTitleBar extends ConsumerWidget implements PreferredSizeWidget {
  const VaultifyTitleBar({super.key, this.bottom});

  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
      kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return AppBar(
      title: Row(
        children: [
          // Brand mark: the V-monogram, matching the app icon.
          VaultifyMark(size: 26, color: c.primary),
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
        const SizedBox(width: Space.half),
      ],
      bottom: bottom,
    );
  }
}
