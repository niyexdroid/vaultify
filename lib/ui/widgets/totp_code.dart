import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/totp/totp.dart';
import '../providers.dart';
import '../theme.dart';

/// TOTP codes: the live code for one saved entry, with the seconds left in
/// a ring beside it and a copy button. Ticks once a second and works out a
/// new code only when the time step rolls over.
class TotpCodeView extends ConsumerStatefulWidget {
  const TotpCodeView({
    super.key,
    required this.secret,
    required this.mobile,
    required this.onCopy,
  });

  final TotpSecret secret;
  final bool mobile;

  /// Copy code: called with the code showing right now.
  final ValueChanged<String> onCopy;

  @override
  ConsumerState<TotpCodeView> createState() => _TotpCodeViewState();
}

class _TotpCodeViewState extends ConsumerState<TotpCodeView> {
  Timer? _tick;
  String? _code;
  int _step = -1;
  int _secondsLeft = 0;
  double _fractionLeft = 1;

  @override
  void initState() {
    super.initState();
    _refresh();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(TotpCodeView old) {
    super.didUpdateWidget(old);
    // A different secret (the row was given a new one) needs a new code.
    if (old.secret != widget.secret) {
      _step = -1;
      _refresh();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // TOTP countdown: the ring and seconds move every tick; the code itself
  // is only recomputed when the 30 second step changes.
  Future<void> _refresh() async {
    final now = ref.read(clockProvider)();
    final secret = widget.secret;
    final step = totpStep(secret, now);
    setState(() {
      _secondsLeft = totpSecondsLeft(secret, now);
      _fractionLeft = totpFractionLeft(secret, now);
    });
    if (step == _step && _code != null) return;
    final code = await totpCode(secret, now);
    if (!mounted) return;
    setState(() {
      _step = step;
      _code = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final code = _code;
    final shown = code == null ? '······' : groupTotpCode(code);

    return Row(
      children: [
        // The code itself, spaced in two halves so it is easy to read out.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shown,
                semanticsLabel: code == null
                    ? 'Two-factor code loading'
                    : 'Two-factor code $code',
                style: passwordTextStyle(c, mobile: widget.mobile).copyWith(
                  fontSize: FontSizes.title,
                  color: c.primary,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                widget.secret.label.isEmpty
                    ? 'Two-factor code'
                    : 'Two-factor code · ${widget.secret.label}',
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // TOTP countdown: ring that empties as the code runs out, with the
        // seconds left inside it.
        Semantics(
          label: '$_secondsLeft seconds left',
          excludeSemantics: true,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _fractionLeft,
                  strokeWidth: 2,
                  backgroundColor: c.primarySoft,
                  valueColor: AlwaysStoppedAnimation(c.primary),
                ),
                Text('$_secondsLeft',
                    style: text.bodySmall?.copyWith(fontSize: 10)),
              ],
            ),
          ),
        ),
        const SizedBox(width: Space.half),
        IconButton(
          tooltip: 'Copy code',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          constraints: BoxConstraints(
              minWidth: widget.mobile ? minTouchTarget : 32,
              minHeight: widget.mobile ? minTouchTarget : 32),
          onPressed: code == null ? null : () => widget.onCopy(code),
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

/// TOTP codes: "123456" shown as "123 456" (and eight digits as
/// "1234 5678"), the way authenticator apps split them.
String groupTotpCode(String code) {
  final half = code.length ~/ 2;
  return '${code.substring(0, half)} ${code.substring(half)}';
}
