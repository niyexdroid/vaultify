import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultify/core/security/clipboard_guard.dart';

// Clipboard clearing tests: clears after the chosen time, only if the
// clipboard still holds the copied password.
void main() {
  late String? clipboard;
  late DateTime now;
  late List<_ManualTimer> timers;

  ClipboardGuard guard() => ClipboardGuard(
        write: (text) async => clipboard = text,
        read: () async => clipboard,
        clock: () => now,
        startTimer: (duration, callback) {
          final t = _ManualTimer(duration, callback);
          timers.add(t);
          return t;
        },
      );

  setUp(() {
    clipboard = null;
    now = DateTime.utc(2026, 10, 12, 9);
    timers = [];
  });

  test('clears the copied password after the chosen time', () async {
    final g = guard();
    await g.copyPassword('s3cret', 30);
    expect(clipboard, 's3cret');
    expect(timers.single.duration, const Duration(seconds: 30));

    now = now.add(const Duration(seconds: 6));
    expect(g.secondsLeft(), 24);

    await timers.single.fire();
    expect(clipboard, '');
    expect(g.secondsLeft(), isNull);
  });

  test('leaves the clipboard alone if something else was copied', () async {
    final g = guard();
    await g.copyPassword('s3cret', 30);
    clipboard = 'copied in another app';
    await timers.single.fire();
    expect(clipboard, 'copied in another app');
  });

  test('"off" copies without clearing', () async {
    final g = guard();
    await g.copyPassword('s3cret', 0);
    expect(clipboard, 's3cret');
    expect(timers, isEmpty);
    expect(g.secondsLeft(), isNull);
  });

  test('a new copy replaces the earlier countdown', () async {
    final g = guard();
    await g.copyPassword('first', 30);
    await g.copyPassword('second', 15);
    expect(timers.first.isActive, isFalse);
    await timers.last.fire();
    expect(clipboard, '');
  });

  test('copying a username stops the password countdown', () async {
    final g = guard();
    await g.copyPassword('s3cret', 30);
    await g.copyText('me@example.com');
    expect(timers.single.isActive, isFalse);
    expect(g.secondsLeft(), isNull);
    expect(clipboard, 'me@example.com');
  });

  test('sensitive clipboard flag: passwords use writeSecret, usernames write',
      () async {
    final secret = <String>[];
    final plain = <String>[];
    final g = ClipboardGuard(
      write: (text) async => plain.add(text),
      writeSecret: (text) async => secret.add(text),
      read: () async => null,
    );
    await g.copyPassword('s3cret', 0);
    await g.copyText('me@example.com');
    expect(secret, ['s3cret']);
    expect(plain, ['me@example.com']);
  });
}

/// Test timer: fired by hand instead of waiting.
class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  Future<void> fire() async {
    if (!_active) return;
    _active = false;
    _callback();
    // Let the guard's async clearing finish.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
