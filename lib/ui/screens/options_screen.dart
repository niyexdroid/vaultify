import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/generator/generator.dart';
import '../../core/settings/settings.dart';
import '../../core/vault/backup.dart';
import '../../core/vault/vault_file.dart';
import '../../platform/open_folder.dart';
import '../app_info.dart';
import '../biometric_offer.dart';
import '../generator_controller.dart';
import '../providers.dart';
import '../session.dart';
import '../theme.dart';
import '../vault_entries.dart';
import 'backup_export_screen.dart';
import 'backup_import_screen.dart';
import 'change_secret_screen.dart';

/// Options screen: unlock secret, biometric unlock and background lock
/// (mobile), auto-lock, clipboard clearing, generator defaults and About.
class OptionsScreen extends ConsumerWidget {
  const OptionsScreen({super.key});

  // Options: a change toast ("Auto-lock set to 15 min").
  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Change PIN or password: opens the change page; [newType] different from
  // the current type switches between PIN and master password.
  Future<void> _changeSecret(
    BuildContext context,
    UnlockType current,
    UnlockType newType,
  ) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ChangeSecretScreen(currentType: current, newType: newType),
      ),
    );
    if (changed == true && context.mounted) {
      _toast(context,
          newType == UnlockType.pin ? 'PIN changed' : 'Password changed');
    }
  }

  // Backup export: opens the export steps; nothing to do for an empty vault.
  Future<void> _exportBackup(
    BuildContext context,
    WidgetRef ref,
    UnlockType type,
  ) async {
    if (ref.read(vaultEntriesProvider).isEmpty) {
      _toast(context, 'No saved passwords to export yet');
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BackupExportScreen(currentType: type)),
    );
    if (saved == true && context.mounted) _toast(context, 'Backup saved');
  }

  // Backup import: pick a file (background lock paused while the Open
  // window shows), check it is a backup, then ask for its password.
  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    const notBackup = "That file isn't a Vaultify backup";
    String? text;
    try {
      text = await ref
          .read(backgroundLockPauseProvider)
          .during(() => ref.read(backupFilesProvider).pickText());
    } catch (_) {
      if (context.mounted) _toast(context, notBackup);
      return;
    }
    if (text == null || !context.mounted) return;
    final BackupFile file;
    try {
      file = BackupFile.decode(text);
    } on VaultFormatException {
      _toast(context, notBackup);
      return;
    }
    final result = await Navigator.of(context).push<MergeResult>(
      MaterialPageRoute(builder: (_) => BackupImportScreen(file: file)),
    );
    if (result != null && context.mounted) {
      _toast(context, importSummary(result));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).requireValue;
    final settings = session.settings;
    final type = session.unlockType ?? UnlockType.pin;
    final mobile = ref.watch(mobileLayoutProvider);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final controller = ref.read(sessionProvider.notifier);
    final otherType =
        type == UnlockType.pin ? UnlockType.password : UnlockType.pin;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      children: [
        // Options, unlock secret: change it, or switch PIN ↔ password.
        const _Section('Unlock'),
        ListTile(
          leading: const Icon(Icons.password),
          title: Text(type == UnlockType.pin ? 'Change PIN' : 'Change password'),
          onTap: () => _changeSecret(context, type, type),
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: Text(type == UnlockType.pin
              ? 'Use a master password instead'
              : 'Use a PIN instead'),
          onTap: () => _changeSecret(context, type, otherType),
        ),
        // Options, biometric unlock (mobile): on/off. Greyed out when the
        // phone has no fingerprint or face set up.
        if (mobile) _BiometricTile(settings: settings, type: type),

        // Options, auto-lock: idle time before locking.
        const _Section('Protection'),
        _ChoiceTile(
          icon: Icons.lock_clock_outlined,
          title: 'Auto-lock',
          subtitle: 'Locks after this long without use',
          value: settings.autoLockMinutes,
          choices: Settings.autoLockChoices,
          label: (m) => m == 0 ? 'Never' : '$m min',
          onChanged: (m) =>
              controller.updateSettings((s) => s.copyWith(autoLockMinutes: m)),
        ),

        // Options, background lock (mobile): how soon after leaving the
        // app it locks.
        if (mobile)
          _ChoiceTile(
            icon: Icons.phonelink_lock_outlined,
            title: 'Lock in background',
            subtitle: 'After you switch away from Vaultify',
            value: settings.backgroundLockSeconds,
            choices: Settings.backgroundLockChoices,
            label: backgroundLockLabel,
            onChanged: (s) => controller
                .updateSettings((v) => v.copyWith(backgroundLockSeconds: s)),
          ),

        // Options, clipboard clearing: time before a copied password is
        // cleared. iOS can only clear while the app is open.
        _ChoiceTile(
          icon: Icons.content_paste_off_outlined,
          title: 'Clear copied passwords',
          subtitle: defaultTargetPlatform == TargetPlatform.iOS
              ? 'On iPhone, clearing only happens while Vaultify is open'
              : 'Only if the clipboard still holds the password',
          value: settings.clipboardClearSeconds,
          choices: Settings.clipboardClearChoices,
          label: (s) => s == 0 ? 'Off' : '$s s',
          onChanged: (s) => controller
              .updateSettings((v) => v.copyWith(clipboardClearSeconds: s)),
        ),

        // Options, default generator settings: what the Generator starts
        // with each time the app is unlocked.
        const _Section('Generator defaults'),
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(describeGeneratorOptions(settings.generator)),
          subtitle: const Text('Used each time Vaultify is unlocked'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          child: Wrap(
            spacing: Space.x1,
            runSpacing: Space.x1,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final current = ref.read(generatorProvider).options;
                  await controller.updateSettings(
                      (s) => s.copyWith(generator: current));
                  if (context.mounted) {
                    _toast(context, 'Generator defaults saved');
                  }
                },
                child: const Text('Use current generator settings'),
              ),
              TextButton(
                onPressed: () async {
                  await controller.updateSettings(
                      (s) => s.copyWith(generator: const GeneratorOptions()));
                  if (context.mounted) {
                    _toast(context, 'Generator defaults reset');
                  }
                },
                child: const Text('Reset'),
              ),
            ],
          ),
        ),

        // Backup export/import: an encrypted file with its own password, to
        // keep safe or to move passwords to another device.
        const _Section('Backup'),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Export backup'),
          subtitle: const Text(
            'Save an encrypted copy of your passwords, protected by a '
            'backup password',
          ),
          onTap: () => _exportBackup(context, ref, type),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import backup'),
          subtitle: const Text(
            'Add passwords from a backup file, e.g. from another device',
          ),
          onTap: () => _importBackup(context, ref),
        ),

        // About: version, this-device-only note, data folder (desktop).
        const _Section('About'),
        ListTile(
          leading: Icon(Icons.shield_outlined, color: c.primary),
          title: const Text('Vaultify $appVersion'),
          subtitle: const Text(
            'Your vault lives only on this device. Each device keeps its own '
            'separate vault; nothing is synced or sent anywhere.',
          ),
        ),
        if (!mobile) ...[
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Data folder'),
            subtitle: SelectableText(
              ref.watch(appDirectoryProvider).path,
              style: text.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.x2, 0, Space.x2, Space.x2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok =
                      await openFolder(ref.read(appDirectoryProvider).path);
                  if (!ok && context.mounted) {
                    _toast(context, "Couldn't open the folder");
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open folder'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Default generator settings: "Uppercase, lowercase, numbers, symbols ·
/// 16 characters".
String describeGeneratorOptions(GeneratorOptions o) {
  final sets = [
    if (o.uppercase) 'uppercase',
    if (o.lowercase) 'lowercase',
    if (o.numbers) 'numbers',
    if (o.symbols) 'symbols',
    if (o.custom) 'custom',
  ];
  final what = sets.isEmpty ? 'No character types' : sets.join(', ');
  final sentence = what[0].toUpperCase() + what.substring(1);
  return '$sentence · ${o.clampedLength} characters';
}

/// Background lock: 0 → "Immediately", 30 → "30 s", 60 → "1 min".
String backgroundLockLabel(int seconds) => switch (seconds) {
      0 => 'Immediately',
      60 => '1 min',
      _ => '$seconds s',
    };

/// Options, biometric unlock (mobile): the on/off switch. Turning it on
/// asks for a scan first; turning it off removes the stored key.
class _BiometricTile extends ConsumerStatefulWidget {
  const _BiometricTile({required this.settings, required this.type});

  final Settings settings;
  final UnlockType type;

  @override
  ConsumerState<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends ConsumerState<_BiometricTile> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    final controller = ref.read(sessionProvider.notifier);
    String? message;
    if (on) {
      message = biometricEnableMessage(
          await controller.enableBiometrics(biometricEnableReason));
    } else {
      await controller.disableBiometrics();
      message = 'Biometric unlock off';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) OptionsScreen._toast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(biometricsAvailableProvider).value ?? false;
    final noun = widget.type == UnlockType.pin ? 'PIN' : 'password';
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Biometric unlock'),
      subtitle: Text(available
          ? 'Fingerprint or face. Your $noun is still needed every 7 days.'
          : 'Set up a fingerprint or face in your phone settings first'),
      value: available && widget.settings.biometricEnabled,
      onChanged: available && !_busy ? _toggle : null,
    );
  }
}

/// Options: section caption ("Unlock", "Protection", ...).
class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Space.x2, Space.x3, Space.x2, Space.half),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.colors.textSecondary),
      ),
    );
  }
}

/// Options: a setting with a small drop-down of choices on the right.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.choices,
    required this.label,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final List<int> choices;
  final String Function(int) label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          borderRadius: BorderRadius.circular(Radii.control),
          items: [
            for (final c in choices)
              DropdownMenuItem(value: c, child: Text(label(c))),
          ],
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
        ),
      ),
    );
  }
}
