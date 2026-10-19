import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../../core/totp/totp.dart';
import '../../core/vault/entry.dart';
import '../providers.dart';
import '../session.dart';
import '../shell/shell_parts.dart';
import '../theme.dart';
import '../vault_entries.dart';
import '../widgets/entry_row.dart';
import '../widgets/status_line.dart';
import '../widgets/totp_code.dart';
import 'totp_add_screen.dart';

/// Search: the search field's focus, shared so Ctrl/Cmd+F can jump to it.
final savedSearchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'Saved search');
  ref.onDispose(node.dispose);
  return node;
});

/// Saved screen: search, count and sort, then the saved rows with show,
/// copy and delete. Desktop rows have icons; mobile rows open a sheet.
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  /// Show password: how long a shown password stays visible.
  static const revealFor = Duration(seconds: 10);

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  final _search = TextEditingController();
  String _query = '';

  // Show password: entry id → timer that hides it again after 10 s.
  final Map<String, Timer> _revealed = {};

  @override
  void dispose() {
    _search.dispose();
    for (final t in _revealed.values) {
      t.cancel();
    }
    super.dispose();
  }

  // Show password: show for 10 s, or hide now if already shown.
  void _toggleShow(Entry e) {
    setState(() {
      final timer = _revealed.remove(e.id);
      if (timer != null) {
        timer.cancel();
      } else {
        _revealed[e.id] = Timer(SavedScreen.revealFor, () {
          if (mounted) setState(() => _revealed.remove(e.id));
        });
      }
    });
  }

  // Copy password: cleared after the Options time (clipboard clearing).
  Future<void> _copyPassword(String password) async {
    if (password.isEmpty) return;
    await ref.read(clipboardGuardProvider).copyPassword(password,
        ref.read(sessionProvider).requireValue.settings.clipboardClearSeconds);
    _toast('Password copied');
  }

  // Copy code (TOTP): the code showing right now, cleared from the
  // clipboard on the same timer as a password.
  Future<void> _copyCodeText(String code) async {
    await ref.read(clipboardGuardProvider).copyPassword(code,
        ref.read(sessionProvider).requireValue.settings.clipboardClearSeconds);
    _toast('Code copied');
  }

  // Copy code (TOTP), from the mobile sheet: works out the code showing
  // right now, then copies it.
  Future<void> _copyCode(Entry e) async {
    final secret = e.totp;
    if (secret == null) return;
    final code = await totpCode(secret, ref.read(clockProvider)());
    if (!mounted) return;
    await _copyCodeText(code);
  }

  // Add two-factor code: the add page reads a QR code or a pasted link,
  // then the secret is saved on the entry.
  Future<void> _addCode(Entry e) async {
    final secret = await Navigator.push<TotpSecret>(
      context,
      MaterialPageRoute(builder: (_) => TotpAddScreen(entryName: e.name)),
    );
    if (secret == null || !mounted) return;
    try {
      await ref.read(vaultEntriesProvider.notifier).setTotp(e.id, secret);
      _toast('Two-factor code added');
    } catch (_) {
      _toast("Couldn't save the code. Try again.");
    }
  }

  // Remove two-factor code: asks first, because the secret is only kept
  // here and the website would have to be set up again.
  Future<void> _removeCode(Entry e) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove the two-factor code for ${e.name}?'),
        content: const Text(
            "The password stays. You'll need the website's QR code or setup "
            'key to add the code again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.colors.weak),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await ref.read(vaultEntriesProvider.notifier).setTotp(e.id, null);
      _toast('Two-factor code removed');
    } catch (_) {
      _toast("Couldn't remove the code. Try again.");
    }
  }

  // Copy username: not secret, so it stays on the clipboard.
  Future<void> _copyUsername(String username) async {
    if (username.isEmpty) return;
    await ref.read(clipboardGuardProvider).copyText(username);
    _toast('Username copied');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Delete: asks "Delete Gmail? This can't be undone." first, then saves.
  Future<void> _delete(Entry e) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${e.name}?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.colors.weak),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await ref.read(vaultEntriesProvider.notifier).delete(e.id);
      _revealed.remove(e.id)?.cancel();
      _toast('Deleted');
    } catch (_) {
      _toast("Couldn't delete. Try again.");
    }
  }

  // Mobile row actions: bottom sheet with Show, Copy password, Copy
  // username and Delete.
  Future<void> _openSheet(Entry e) async {
    final c = context.colors;
    final action = await showModalBottomSheet<_RowAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.x2, 0, Space.x2, Space.x1),
              child: Text(e.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: Icon(_revealed.containsKey(e.id)
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              title: Text(_revealed.containsKey(e.id)
                  ? 'Hide password'
                  : 'Show password'),
              onTap: () => Navigator.pop(context, _RowAction.show),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy password'),
              onTap: () => Navigator.pop(context, _RowAction.copyPassword),
            ),
            ListTile(
              enabled: e.username.isNotEmpty,
              leading: const Icon(Icons.person_outline),
              title: const Text('Copy username'),
              onTap: () => Navigator.pop(context, _RowAction.copyUsername),
            ),
            // TOTP codes: copy the live code, and add or remove the secret.
            if (e.hasTotp)
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Copy code'),
                onTap: () => Navigator.pop(context, _RowAction.copyCode),
              ),
            ListTile(
              leading: Icon(
                  e.hasTotp ? Icons.shield : Icons.shield_outlined),
              title: Text(e.hasTotp
                  ? 'Remove two-factor code'
                  : 'Add two-factor code'),
              onTap: () => Navigator.pop(
                  context, e.hasTotp ? _RowAction.removeCode
                      : _RowAction.addCode),
            ),
            ListTile(
              iconColor: c.weak,
              textColor: c.weak,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, _RowAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _RowAction.show:
        _toggleShow(e);
      case _RowAction.copyPassword:
        await _copyPassword(e.password);
      case _RowAction.copyUsername:
        await _copyUsername(e.username);
      case _RowAction.copyCode:
        await _copyCode(e);
      case _RowAction.addCode:
        await _addCode(e);
      case _RowAction.removeCode:
        await _removeCode(e);
      case _RowAction.delete:
        await _delete(e);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mobile = ref.watch(mobileLayoutProvider);
    final all = ref.watch(vaultEntriesProvider);
    final order = ref.watch(sessionProvider
            .select((s) => s.value?.settings.sortOrder)) ??
        SortOrder.nameAsc;

    // Empty state: nothing saved yet.
    if (all.isEmpty) return const _EmptyState();

    final shown = searchAndSort(all, _query, order);
    final count = _query.trim().isEmpty
        ? '${all.length} saved'
        : '${shown.length} of ${all.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search: filters by name or username as you type.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.x2, Space.x2, Space.x2, Space.x1),
          child: TextField(
            controller: _search,
            focusNode: ref.watch(savedSearchFocusProvider),
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),

        // Count caption ("4 saved" / "2 of 4") and sort choice.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          child: Row(
            children: [
              Expanded(child: Text(count, style: text.bodySmall)),
              PopupMenuButton<SortOrder>(
                tooltip: 'Sort',
                initialValue: order,
                onSelected: (o) =>
                    ref.read(sessionProvider.notifier).setSortOrder(o),
                itemBuilder: (context) => [
                  for (final o in SortOrder.values)
                    PopupMenuItem(value: o, child: Text(_sortLabel(o))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.x1, vertical: Space.x1 + Space.half),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_sortLabel(order), style: text.bodySmall),
                      const SizedBox(width: Space.half),
                      const Icon(Icons.swap_vert, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Saved rows, separated by 1 px lines.
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text('No matches', style: text.bodyMedium),
                )
              : ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = shown[i];
                    return EntryRow(
                      key: ValueKey(e.id),
                      entry: e,
                      mobile: mobile,
                      revealed: _revealed.containsKey(e.id),
                      onToggleShow: () => _toggleShow(e),
                      onCopyPassword: () => _copyPassword(e.password),
                      onCopyUsername: () => _copyUsername(e.username),
                      onDelete: () => _delete(e),
                      onAddCode: () => _addCode(e),
                      onRemoveCode: () => _removeCode(e),
                      // TOTP codes: the live code line, only for entries
                      // that have a two-factor secret.
                      codeView: e.totp == null
                          ? null
                          : TotpCodeView(
                              secret: e.totp!,
                              mobile: mobile,
                              onCopy: _copyCodeText,
                            ),
                      // Mobile: tap opens the actions sheet, long-press
                      // copies the password.
                      onTap: mobile ? () => _openSheet(e) : null,
                      onLongPress:
                          mobile ? () => _copyPassword(e.password) : null,
                    );
                  },
                ),
        ),

        // Status line: clipboard countdown and auto-lock time.
        const StatusLine(),
      ],
    );
  }
}

/// Mobile row actions: what was picked in the bottom sheet.
enum _RowAction {
  show,
  copyPassword,
  copyUsername,
  copyCode,
  addCode,
  removeCode,
  delete,
}

/// Saved list sort: label shown in the sort menu.
String _sortLabel(SortOrder o) => switch (o) {
      SortOrder.nameAsc => 'A–Z',
      SortOrder.newestFirst => 'Newest first',
    };

/// Empty state: "Save your first password" with a button to the Generator.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_outlined, size: 40, color: c.textSecondary),
            const SizedBox(height: Space.x2),
            Text('Save your first password',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.x2),
            OutlinedButton(
              onPressed: () => ref
                  .read(currentAreaProvider.notifier)
                  .show(AppArea.generator),
              child: const Text('Open generator'),
            ),
          ],
        ),
      ),
    );
  }
}
