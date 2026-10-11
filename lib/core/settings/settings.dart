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

  Settings copyWith({
    UnlockType? unlockType,
    int? autoLockMinutes,
    int? backgroundLockSeconds,
    int? clipboardClearSeconds,
    GeneratorOptions? generator,
    LockoutState? lockout,
    SortOrder? sortOrder,
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
      );

  Map<String, Object?> toJson() => {
        'unlockType': unlockType?.name,
        'autoLockMinutes': autoLockMinutes,
        'backgroundLockSeconds': backgroundLockSeconds,
        'clipboardClearSeconds': clipboardClearSeconds,
        'generator': generator.toJson(),
        'lockout': lockout.toJson(),
        'sortOrder': sortOrder.name,
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
    );
  }
}
