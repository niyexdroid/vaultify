import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import '../vault_entries.dart';

/// Saved screen (Milestone 4 stand-in): the count and names, so saving can
/// be checked. Milestone 5 replaces it with search, show, copy and delete.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final entries = [...ref.watch(vaultEntriesProvider)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.all(Space.x2),
      children: [
        Text('${entries.length} saved', style: text.bodySmall),
        const SizedBox(height: Space.x1),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Text(e.name, style: text.titleSmall),
          ),
      ],
    );
  }
}
