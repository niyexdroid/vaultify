import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/totp/otpauth.dart';
import '../../core/totp/totp.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/auth_layout.dart';
import 'qr_scan_screen.dart';

/// Add two-factor code: paste an `otpauth://` link or a setup key, or (on a
/// phone) scan the QR code the website shows. Pops with the [TotpSecret]
/// once it reads, so the caller can save it on the entry.
class TotpAddScreen extends ConsumerStatefulWidget {
  const TotpAddScreen({super.key, required this.entryName});

  final String entryName;

  @override
  ConsumerState<TotpAddScreen> createState() => _TotpAddScreenState();
}

class _TotpAddScreenState extends ConsumerState<TotpAddScreen> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  // Add two-factor code: read what was typed, pasted or scanned and hand it
  // back to the saved screen. The text stays on the page if it won't read.
  void _use(String text) {
    try {
      final secret = parseTotpInput(text);
      Navigator.pop(context, secret);
    } on TotpInputException catch (e) {
      setState(() => _error = e.message);
    }
  }

  // Add two-factor code: paste button, for people who copied the key.
  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    _input.text = text.trim();
    setState(() => _error = null);
  }

  // Scan QR code (mobile): the camera page hands back the link it read.
  // Background lock is paused, because the camera permission prompt counts
  // as leaving the app on iOS.
  Future<void> _scan() async {
    final pause = ref.read(backgroundLockPauseProvider);
    final link = await pause.during(() => Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const QrScanScreen()),
        ));
    if (!mounted || link == null) return;
    _use(link);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = ref.watch(mobileLayoutProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return AuthLayout(
      appBar: AppBar(title: const Text('Add two-factor code')),
      heading: 'Two-factor code for ${widget.entryName}',
      children: [
        Text(
          mobile
              ? 'Scan the QR code the website shows, or paste its '
                  'otpauth:// link or setup key.'
              : 'Paste the otpauth:// link or the setup key the website '
                  'shows beside its QR code.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: Space.x2),
        if (mobile) ...[
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
          const SizedBox(height: Space.x2),
        ],
        TextField(
          controller: _input,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 2,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'otpauth://totp/... or setup key',
            suffixIcon: IconButton(
              tooltip: 'Paste',
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
            ),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: _use,
        ),
        const SizedBox(height: Space.x2),
        AuthButton(label: 'Add code', onPressed: () => _use(_input.text)),
        AuthMessage(_error, error: _error != null),
      ],
    );
  }
}
