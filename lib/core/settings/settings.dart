import '../generator/generator.dart';
import '../security/lockout.dart';
import '../vault/vault_file.dart';

/// Saved list sort order: A–Z (default) or newest first.
enum SortOrder { nameAsc, newestFirst }

/// Settings: everything in `settings.json`. Nothing here is secret.
class Settings {
  const Settings({
    this.unlockType,
    this.autoLockMinutes = 5,
    this.backgroundLockSeconds = 0,
    this.clipboardClearSeconds = 30,
    this.generator = const GeneratorOptions(),
    this.lockout = LockoutState.initial,
    this.sortOrder = SortOrder.nameAsc,
    this.biometricEnabled = false,
    this.biometricOffered = false,
    this.biometricFailures = 0,
  });

  // Settings: the choices offered in Options. 0 means "never" / "off" /
  // "immediately" respectively.
  static const List<int> autoLockChoices = [1, 5, 15, 30, 0];
  static const List<int> backgroundLockChoices = [0, 30, 60];
  static const List<int> clipboardClearChoices = [15, 30, 60, 0];

  /// Unlock type chosen at setup; null until a vault exists.
  final UnlockType? unlockType;

  /// Auto-lock: idle minutes before locking; 0 = never.
  final int autoLockMinutes;

  /// Background lock (mobile): seconds in background before locking;
  /// 0 = immediately.
  final int backgroundLockSeconds;

  /// Clipboard clearing: seconds before a copied password is cleared;
  /// 0 = off.
  final int clipboardClearSeconds;

  /// Default generator settings.
  final GeneratorOptions generator;

  /// Wrong-attempt delays: counter and wait end time.
  final LockoutState lockout;

  /// Saved list sort order.
  final SortOrder sortOrder;

  /// Biometric unlock (mobile): fingerprint or face unlock is turned on.
  final bool biometricEnabled;

  /// Biometric unlock (mobile): the "Unlock with fingerprint or face?"
  /// offer has been shown once, so it isn't asked again.
  final bool biometricOffered;

  /// Biometric unlock (mobile): failed scans since the PIN or password was
  /// last typed; at 5 the PIN is required.
  final int biometricFailures;

  Settings copyWith({
    UnlockType? unlockType,
    int? autoLockMinutes,
    int? backgroundLockSeconds,
    int? clipboardClearSeconds,
    GeneratorOptions? generator,
    LockoutState? lockout,
    SortOrder? sortOrder,
    bool? biometricEnabled,
    bool? biometricOffered,
    int? biometricFailures,
  }) =>
      Settings(
        unlockType: unlockType ?? this.unlockType,
        autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
        backgroundLockSeconds:
            backgroundLockSeconds ?? this.backgroundLockSeconds,
        clipboardClearSeconds:
            clipboardClearSeconds ?? this.clipboardClearSeconds,
        generator: generator ?? this.generator,
        lockout: lockout ?? this.lockout,
        sortOrder: sortOrder ?? this.sortOrder,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        biometricOffered: biometricOffered ?? this.biometricOffered,
        biometricFailures: biometricFailures ?? this.biometricFailures,
      );

  Map<String, Object?> toJson() => {
        'unlockType': unlockType?.name,
        'autoLockMinutes': autoLockMinutes,
        'backgroundLockSeconds': backgroundLockSeconds,
        'clipboardClearSeconds': clipboardClearSeconds,
        'generator': generator.toJson(),
        'lockout': lockout.toJson(),
        'sortOrder': sortOrder.name,
        'biometricEnabled': biometricEnabled,
        'biometricOffered': biometricOffered,
        'biometricFailures': biometricFailures,
      };

  /// Settings: reads `settings.json`, using the default for any field that
  /// is missing or not one of the allowed choices.
  factory Settings.fromJson(Object? json) {
    const d = Settings();
    if (json is! Map<String, Object?>) return d;
    int choice(String key, List<int> allowed, int fallback) {
      final value = json[key];
      return value is int && allowed.contains(value) ? value : fallback;
    }

    final sort = json['sortOrder'];
    final failures = json['biometricFailures'];
    return Settings(
      unlockType: UnlockType.fromName(json['unlockType']),
      autoLockMinutes:
          choice('autoLockMinutes', autoLockChoices, d.autoLockMinutes),
      backgroundLockSeconds: choice('backgroundLockSeconds',
          backgroundLockChoices, d.backgroundLockSeconds),
      clipboardClearSeconds: choice('clipboardClearSeconds',
          clipboardClearChoices, d.clipboardClearSeconds),
      generator: GeneratorOptions.fromJson(json['generator']),
      lockout: LockoutState.fromJson(json['lockout']),
      sortOrder: SortOrder.values.firstWhere(
        (s) => s.name == sort,
        orElse: () => d.sortOrder,
      ),
      biometricEnabled: json['biometricEnabled'] == true,
      biometricOffered: json['biometricOffered'] == true,
      biometricFailures: failures is int && failures > 0 ? failures : 0,
    );
  }
}
