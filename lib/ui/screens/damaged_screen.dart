import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets/auth_layout.dart';

/// Damaged vault: `vault.vfy` can't be read (not a wrong PIN). Offers to
/// restore the last good save from `vault.vfy.bak`.
class DamagedScreen extends ConsumerStatefulWidget {
  const DamagedScreen({super.key, required this.hasBackup});

  final bool hasBackup;

  @override
  ConsumerState<DamagedScreen> createState() => _DamagedScreenState();
}

class _DamagedScreenState extends ConsumerState<DamagedScreen> {
  bool _busy = false;
  String? _error;

  // Damaged vault: restore from backup; the lock gate then shows unlock.
  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).restoreFromBackup();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "The backup couldn't be read either.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      heading: "Vault can't be read",
      children: [
        Text(
          widget.hasBackup
              ? 'Your vault file is damaged or missing. You can restore the '
                  'last good save; anything saved after it will be lost.'
              : 'Your vault file is damaged and there is no backup to '
                  'restore from.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        if (widget.hasBackup) ...[
          const SizedBox(height: Space.x3),
          AuthButton(
            label: 'Restore last good save',
            busy: _busy,
            onPressed: _restore,
          ),
        ],
        AuthMessage(_error, error: true),
      ],
    );
  }
}
