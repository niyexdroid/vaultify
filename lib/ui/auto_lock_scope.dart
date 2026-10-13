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
///
/// Background lock (mobile): also locks when the app leaves the screen,
/// immediately or after the delay chosen in Options.
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

  // Background lock: watches the app going to / coming back from the
  // background (mobile only), and when it left.
  AppLifecycleListener? _lifecycle;
  DateTime? _hiddenAt;
  Timer? _backgroundTimer;

  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _check = Timer.periodic(AutoLockScope.checkEvery, (_) => _checkIdle());
    if (ref.read(mobileLayoutProvider)) {
      _lifecycle = AppLifecycleListener(
        onHide: _onHidden,
        onShow: _onShown,
      );
    }
  }

  @override
  void dispose() {
    _check?.cancel();
    _backgroundTimer?.cancel();
    _lifecycle?.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  int get _backgroundSeconds =>
      ref.read(sessionProvider).value?.settings.backgroundLockSeconds ?? 0;

  // Background lock: "Immediately" locks as the app leaves the screen;
  // otherwise a timer locks after the delay. Phones may pause that timer,
  // so the time away is also checked on return.
  void _onHidden() {
    // Backup export/import: Vaultify's own Save / Open window is showing.
    if (ref.read(backgroundLockPauseProvider).active) return;
    _hiddenAt = _now();
    final seconds = _backgroundSeconds;
    if (seconds <= 0) {
      _lock();
      return;
    }
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(Duration(seconds: seconds), _lock);
  }

  // Background lock: back on screen; lock if away for the delay or longer.
  void _onShown() {
    _backgroundTimer?.cancel();
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null) return;
    final away = _now().difference(hiddenAt);
    if (away.isNegative || away >= Duration(seconds: _backgroundSeconds)) {
      _lock();
    } else {
      _touch();
    }
  }

  void _lock() {
    _check?.cancel();
    _backgroundTimer?.cancel();
    ref.read(sessionProvider.notifier).lock();
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
    if (_idle.isDue(_now(), minutes)) _lock();
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
