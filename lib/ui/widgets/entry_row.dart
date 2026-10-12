import 'package:flutter/material.dart';

import '../../core/vault/entry.dart';
import '../theme.dart';

/// Saved row: masked password shown in place of the real one.
const String maskedPassword = '••••••';

/// Saved row: one saved entry — letter badge, name over "username · date",
/// masked password, and (desktop) eye, copy and trash icons. On mobile the
/// icons are left out: tapping opens the actions sheet, long-press copies.
/// When [revealed], the real password shows on its own line below.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.entry,
    required this.revealed,
    required this.mobile,
    required this.onToggleShow,
    required this.onCopyPassword,
    required this.onCopyUsername,
    required this.onDelete,
    this.onTap,
    this.onLongPress,
  });

  final Entry entry;
  final bool revealed;
  final bool mobile;
  final VoidCallback onToggleShow;
  final VoidCallback onCopyPassword;
  final VoidCallback onCopyUsername;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final username = entry.username.isEmpty ? 'No username' : entry.username;
    final mono = passwordTextStyle(c, mobile: mobile);

    // Saved row, desktop: action icons always visible.
    Widget icon(String tooltip, IconData data, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: onPressed,
          icon: Icon(data),
        );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.x2, vertical: Space.x1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  LetterBadge(name: entry.name),
                  const SizedBox(width: Space.x1 + Space.half),
                  // Name (medium) over username · saved date (secondary).
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.name,
                            style: text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text('$username · ${formatSavedDate(entry.updated)}',
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.x1),
                  if (!revealed)
                    Text(
                      maskedPassword,
                      semanticsLabel: 'Password hidden',
                      style: mono.copyWith(
                          fontSize: FontSizes.body, color: c.textSecondary),
                    ),
                  if (!mobile) ...[
                    const SizedBox(width: Space.half),
                    icon(revealed ? 'Hide password' : 'Show password',
                        revealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        onToggleShow),
                    icon('Copy password', Icons.copy_outlined, onCopyPassword),
                    icon('Copy username', Icons.person_outline,
                        entry.username.isEmpty ? null : onCopyUsername),
                    icon('Delete', Icons.delete_outline, onDelete),
                  ],
                ],
              ),
              // Show password: the real password, selectable, until it
              // re-hides.
              if (revealed)
                Padding(
                  padding: const EdgeInsets.only(
                      left: 30 + Space.x1 + Space.half, top: Space.half),
                  child: SelectableText(
                    entry.password,
                    style: mono.copyWith(fontSize: FontSizes.title),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved row: 30 × 30 rounded badge with the name's first letter.
class LetterBadge extends StatelessWidget {
  const LetterBadge({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trimmed = name.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.primarySoft,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Text(
          letter,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: c.primary),
        ),
      ),
    );
  }
}

/// Saved row: saved date like "11 Oct 2026", in local time.
String formatSavedDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final d = date.toLocal();
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
