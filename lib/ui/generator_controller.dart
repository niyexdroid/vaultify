import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/generator/generator.dart';
import '../core/generator/strength.dart';
import 'session.dart';

/// Generator screen state: the chosen options, what's in the password box,
/// and whether the "Pick at least one character type" hint shows.
class GeneratorState {
  const GeneratorState({
    required this.options,
    required this.password,
    required this.generated,
    this.noSetHint = false,
  });

  final GeneratorOptions options;

  /// Password box contents (generated, typed or pasted).
  final String password;

  /// True while [password] is exactly what the generator made, so strength
  /// can use the real pool size instead of guessing from the characters.
  final bool generated;

  /// No character type selected: show the hint under the checkboxes.
  final bool noSetHint;

  /// Strength meter: bits for the password box.
  double get bits => generated
      ? entropyBits(options.clampedLength, options.pool.length)
      : passwordBits(password);

  GeneratorState copyWith({
    GeneratorOptions? options,
    String? password,
    bool? generated,
    bool? noSetHint,
  }) =>
      GeneratorState(
        options: options ?? this.options,
        password: password ?? this.password,
        generated: generated ?? this.generated,
        noSetHint: noSetHint ?? this.noSetHint,
      );
}

/// Generator screen controller. Auto-disposed with the unlocked shell, so
/// locking drops the password from memory.
final generatorProvider =
    NotifierProvider.autoDispose<GeneratorController, GeneratorState>(
        GeneratorController.new);

class GeneratorController extends Notifier<GeneratorState> {
  // Generator: start from the default generator settings and make a fresh
  // password as soon as the screen opens.
  @override
  GeneratorState build() {
    final options =
        ref.read(sessionProvider).value?.settings.generator ??
            const GeneratorOptions();
    return _generate(GeneratorState(
      options: options,
      password: '',
      generated: false,
    ));
  }

  /// Generate button and Ctrl/Cmd+G: a new password with the
  /// current options.
  void generate() => state = _generate(state);

  /// Any option change makes a new password straight away.
  void setOptions(GeneratorOptions options) =>
      state = _generate(state.copyWith(options: options));

  /// Password box: typed or pasted text replaces the generated password.
  void edit(String text) {
    if (text == state.password) return;
    state = state.copyWith(password: text, generated: false);
  }

  // Generator: on "no set selected" keep the box as it is and show the hint.
  static GeneratorState _generate(GeneratorState s) {
    try {
      return s.copyWith(
        password: generatePassword(s.options),
        generated: true,
        noSetHint: false,
      );
    } on NoCharacterSetException {
      return s.copyWith(noSetHint: true);
    }
  }
}
