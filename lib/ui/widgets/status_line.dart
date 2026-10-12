import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../session.dart';
import '../theme.dart';

/// Status line (Saved screen bottom): "Clipboard clears in 24s" on the
/// left while a copied password is waiting to be cleared, and the auto-lock
/// time ("Locks after 5 min") on the right.
class StatusLine extends ConsumerStatefulWidget {
  const StatusLine({super.key});

  @override
  ConsumerState<StatusLine> createState() => _StatusLineState();
}

class _StatusLineState extends ConsumerState<StatusLine> {
  // Status line: redraw once a second so the countdown moves; only
  // rebuilds when the text actually changes.
  Timer? _ticker;
  int? _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _read();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _read();
      if (mounted && left != _secondsLeft) setState(() => _secondsLeft = left);
    });
  }

  int? _read() => ref.read(clipboardGuardProvider).secondsLeft();

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final minutes = ref.watch(sessionProvider
            .select((s) => s.value?.settings.autoLockMinutes)) ??
        0;
    final left = _secondsLeft;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: Space.x2, vertical: Space.x1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left == null ? '' : 'Clipboard clears in ${left}s',
              style: style,
            ),
          ),
          Text(
            minutes == 0 ? 'Auto-lock off' : 'Locks after $minutes min',
            style: style,
          ),
        ],
      ),
    );
  }
}
