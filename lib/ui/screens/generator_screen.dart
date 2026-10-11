import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/generator/generator.dart';
import '../../core/vault/entry.dart';
import '../generator_controller.dart';
import '../providers.dart';
import '../theme.dart';
import '../vault_entries.dart';
import '../widgets/password_box.dart';
import '../widgets/strength_bar.dart';

/// Generator screen: password box, strength, options, Generate, and the
/// save panel, top to bottom as in SPEC.md "Generator screen".
class GeneratorScreen extends ConsumerStatefulWidget {
  const GeneratorScreen({super.key});

  @override
  ConsumerState<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends ConsumerState<GeneratorScreen> {
  final _password = TextEditingController();
  final _custom = TextEditingController();
  final _length = TextEditingController();
  final _lengthFocus = FocusNode();
  final _name = TextEditingController();
  final _username = TextEditingController();

  String? _nameError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(generatorProvider);
    _password.text = s.password;
    _custom.text = s.options.customChars;
    _length.text = '${s.options.length}';
    // Length number: tidy up a half-typed value when the field loses focus.
    _lengthFocus.addListener(() {
      if (!_lengthFocus.hasFocus) _commitLength();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _custom.dispose();
    _length.dispose();
    _lengthFocus.dispose();
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  GeneratorController get _gen => ref.read(generatorProvider.notifier);
  GeneratorOptions get _options => ref.read(generatorProvider).options;

  // Length: change the length, keeping it within 4–128.
  void _setLength(int value) {
    final length =
        value.clamp(GeneratorOptions.minLength, GeneratorOptions.maxLength);
    _length.text = '$length';
    if (length != _options.length) {
      _gen.setOptions(_options.copyWith(length: length));
    }
  }

  // Length number: apply a typed value once it's complete (or on leaving
  // the field), so typing "12" doesn't jump to 4 on the "1".
  void _commitLength() {
    final typed = int.tryParse(_length.text);
    _setLength(typed ?? _options.length);
  }

  // Copy password: plain copy for now; clipboard auto-clear is Milestone 6.
  Future<void> _copy() async {
    if (_password.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _password.text));
    _toast('Copied');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Save to vault: check the name, ask Replace or Keep both for a duplicate
  // name, save, then show "Saved" and clear the name fields.
  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final password = _password.text;
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    if (!Entry.isValidName(name)) {
      setState(() => _nameError =
          'Use ${Entry.maxNameLength} characters or fewer');
      return;
    }
    if (password.isEmpty) {
      _toast('Generate or paste a password first');
      return;
    }
    setState(() => _nameError = null);

    final entries = ref.read(vaultEntriesProvider.notifier);
    var choice = _DuplicateChoice.keepBoth;
    if (entries.nameExists(name)) {
      final picked = await _askDuplicate(name);
      if (picked == null || !mounted) return;
      choice = picked;
    }

    setState(() => _saving = true);
    try {
      final username = _username.text;
      if (choice == _DuplicateChoice.replace) {
        await entries.replace(
            name: name, username: username, password: password);
      } else {
        await entries.add(
            name: name, username: username, password: password, keepBoth: true);
      }
      if (!mounted) return;
      _name.clear();
      _username.clear();
      _toast('Saved');
    } catch (_) {
      if (mounted) _toast("Couldn't save. Try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Duplicate names: "Gmail is already saved" with Replace or Keep both.
  Future<_DuplicateChoice?> _askDuplicate(String name) {
    return showDialog<_DuplicateChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name is already saved'),
        content: const Text(
            'Replace its password, or keep both under different names?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _DuplicateChoice.keepBoth),
            child: const Text('Keep both'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DuplicateChoice.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final mobile = ref.watch(mobileLayoutProvider);
    final s = ref.watch(generatorProvider);
    final o = s.options;

    // Password box: show each new password (but don't fight the user's
    // typing, which already matches).
    ref.listen(generatorProvider, (_, next) {
      if (_password.text != next.password) _password.text = next.password;
      if (!_lengthFocus.hasFocus && _length.text != '${next.options.length}') {
        _length.text = '${next.options.length}';
      }
    });

    void toggle(GeneratorOptions next) => _gen.setOptions(next);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Password box and strength bar.
          PasswordBox(
            controller: _password,
            mobile: mobile,
            onChanged: _gen.edit,
            onCopy: _copy,
          ),
          const SizedBox(height: Space.x1 + Space.half),
          StrengthBar(bits: s.bits, empty: s.password.isEmpty),
          const SizedBox(height: Space.x2),

          // Character type checkboxes, two columns.
          Row(
            children: [
              Expanded(
                child: _OptionCheck(
                  label: 'Uppercase',
                  value: o.uppercase,
                  onChanged: (v) => toggle(o.copyWith(uppercase: v)),
                ),
              ),
              Expanded(
                child: _OptionCheck(
                  label: 'Lowercase',
                  value: o.lowercase,
                  onChanged: (v) => toggle(o.copyWith(lowercase: v)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _OptionCheck(
                  label: 'Numbers',
                  value: o.numbers,
                  onChanged: (v) => toggle(o.copyWith(numbers: v)),
                ),
              ),
              Expanded(
                child: _OptionCheck(
                  label: 'Symbols',
                  value: o.symbols,
                  onChanged: (v) => toggle(o.copyWith(symbols: v)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _OptionCheck(
                  label: 'Custom',
                  value: o.custom,
                  onChanged: (v) => toggle(o.copyWith(custom: v)),
                ),
              ),
              const Spacer(),
            ],
          ),

          // Custom characters field: appears under Custom when ticked.
          if (o.custom)
            Padding(
              padding: const EdgeInsets.only(top: Space.half),
              child: TextField(
                controller: _custom,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'Characters to use, e.g. äöü€',
                ),
                onChanged: (v) => toggle(_options.copyWith(customChars: v)),
              ),
            ),

          // No set selected: hint under the checkboxes.
          if (s.noSetHint)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Text(
                'Pick at least one character type',
                style: text.bodySmall?.copyWith(color: c.weak),
              ),
            ),
          const SizedBox(height: Space.x2),

          // Length row: label, slider (4–64), − / + buttons, typed number
          // (up to 128).
          Row(
            children: [
              Text('Length', style: text.bodyMedium),
              Expanded(
                child: Slider(
                  min: GeneratorOptions.minLength.toDouble(),
                  max: GeneratorOptions.sliderMaxLength.toDouble(),
                  value: o.length
                      .clamp(GeneratorOptions.minLength,
                          GeneratorOptions.sliderMaxLength)
                      .toDouble(),
                  onChanged: (v) => _setLength(v.round()),
                ),
              ),
              IconButton(
                tooltip: 'Shorter',
                onPressed: o.length > GeneratorOptions.minLength
                    ? () => _setLength(_options.length - 1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: 'Longer',
                onPressed: o.length < GeneratorOptions.maxLength
                    ? () => _setLength(_options.length + 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: Space.half),
              SizedBox(
                width: 56,
                child: TextField(
                  key: const Key('lengthField'),
                  controller: _length,
                  focusNode: _lengthFocus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null &&
                        n >= GeneratorOptions.minLength &&
                        n <= GeneratorOptions.maxLength &&
                        n != _options.length) {
                      _gen.setOptions(_options.copyWith(length: n));
                    }
                  },
                  onSubmitted: (_) => _commitLength(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),

          // Generate: the one filled button on the screen.
          FilledButton.icon(
            onPressed: _gen.generate,
            icon: const Icon(Icons.refresh),
            label: const Text('Generate'),
          ),
          const SizedBox(height: Space.x3),
          const Divider(),
          const SizedBox(height: Space.x3),

          // Save panel: name (required), username (optional), Save to vault.
          TextField(
            controller: _name,
            inputFormatters: [
              LengthLimitingTextInputFormatter(Entry.maxNameLength),
            ],
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Gmail',
              errorText: _nameError,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.x1 + Space.half),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username (optional)',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save to vault'),
          ),
        ],
      ),
    );
  }
}

/// Duplicate names: what to do when the name is already saved.
enum _DuplicateChoice { replace, keepBoth }

/// Generator options: a checkbox with its label; the whole row is tappable.
class _OptionCheck extends StatelessWidget {
  const _OptionCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.control),
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTouchTarget),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              semanticLabel: label,
            ),
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}
