import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/auto_lock.dart';
import 'providers.dart';
import 'session.dart';

/// Auto-lock: wraps the unlocked app. Any tap, click, mouse move, scroll or
/// key press counts as activity; after the idle time from Options with none,
/// the vault locks.
class AutoLockScope extends ConsumerStatefulWidget {
  const AutoLockScope({super.key, required this.child});

  final Widget child;

  /// Auto-lock: how often the idle time is checked.
  static const checkEvery = Duration(seconds: 1);

  @override
  ConsumerState<AutoLockScope> createState() => _AutoLockScopeState();
}

class _AutoLockScopeState extends ConsumerState<AutoLockScope> {
  late final IdleTracker _idle = IdleTracker(_now());
  Timer? _check;

  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _check = Timer.periodic(AutoLockScope.checkEvery, (_) => _checkIdle());
  }

  @override
  void dispose() {
    _check?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // Auto-lock: a key press is activity; the key still goes to the app.
  bool _onKey(KeyEvent event) {
    _touch();
    return false;
  }

  void _touch() => _idle.touch(_now());

  // Auto-lock: lock once idle for the chosen minutes (0 = never).
  void _checkIdle() {
    final minutes =
        ref.read(sessionProvider).value?.settings.autoLockMinutes ?? 0;
    if (_idle.isDue(_now(), minutes)) {
      _check?.cancel();
      ref.read(sessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      onPointerMove: (_) => _touch(),
      onPointerHover: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: widget.child,
    );
  }
}
