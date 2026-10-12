import 'dart:async';

/// Clipboard clearing: puts a value on the clipboard and, for passwords,
/// clears it after the time from Options, but only if the clipboard still
/// holds that value (so something copied since is left alone).
///
/// Pure Dart: the app passes in functions that use Flutter's `Clipboard`;
/// tests pass fakes and a [startTimer] they can fire by hand.
class ClipboardGuard {
  ClipboardGuard({
    required this.write,
    required this.read,
    Future<void> Function(String text)? writeSecret,
    this.clock = DateTime.now,
    Timer Function(Duration, void Function())? startTimer,
  })  : writeSecret = writeSecret ?? write,
        _startTimer = startTimer ?? Timer.new;

  /// Puts text on the clipboard.
  final Future<void> Function(String text) write;

  /// Sensitive clipboard flag: puts a password on the clipboard marked as
  /// sensitive where the platform supports it (Android 13+ then hides it
  /// from the clipboard preview). Defaults to [write].
  final Future<void> Function(String text) writeSecret;

  /// Reads the clipboard's text (null if none).
  final Future<String?> Function() read;

  final DateTime Function() clock;
  final Timer Function(Duration, void Function()) _startTimer;

  Timer? _timer;
  DateTime? _clearAt;

  // Clipboard clearing: the copied password, kept only until it's cleared
  // (needed to check the clipboard still holds it).
  String? _pending;

  /// Clipboard clearing: when the copied password will be cleared, or null
  /// when nothing is waiting (used for "Clipboard clears in 24s").
  DateTime? get clearAt => _clearAt;

  /// Clipboard clearing: seconds left before clearing, or null.
  int? secondsLeft() {
    final at = _clearAt;
    if (at == null) return null;
    final left = at.difference(clock()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  /// Copy password: copies [password] and schedules clearing after
  /// [clearAfterSeconds] (0 = never). Replaces any earlier countdown.
  Future<void> copyPassword(String password, int clearAfterSeconds) async {
    _cancel();
    await writeSecret(password);
    if (clearAfterSeconds <= 0) return;
    final after = Duration(seconds: clearAfterSeconds);
    _pending = password;
    _clearAt = clock().add(after);
    _timer = _startTimer(after, _clearIfUnchanged);
  }

  /// Copy username (and other non-secret text): copied as is, never
  /// cleared. Stops a password countdown, since the password is gone from
  /// the clipboard anyway.
  Future<void> copyText(String text) async {
    _cancel();
    await write(text);
  }

  /// Clipboard clearing: stops any countdown (app shutting down).
  void dispose() => _cancel();

  // Clipboard clearing: clear only if our password is still there.
  Future<void> _clearIfUnchanged() async {
    final pending = _pending;
    _timer = null;
    _clearAt = null;
    _pending = null;
    if (pending == null) return;
    try {
      if (await read() == pending) await write('');
    } catch (_) {
      // Clipboard unavailable (e.g. another app holds it): nothing to do.
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _clearAt = null;
    _pending = null;
  }
}
