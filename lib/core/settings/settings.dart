import '../generator/generator.dart';
import '../security/lockout.dart';
import '../vault/vault_file.dart';

/// Saved list sort order: A–Z (default) or newest first.
enum SortOrder { nameAsc, newestFirst }

/// Window size memory: the desktop window's last size and position, so it
/// reopens where you left it. Plain numbers, so core stays free of Flutter.
class WindowBounds {
  const WindowBounds({
    required this.width,
    required this.height,
    this.x,
    this.y,
  });

  /// Sizes outside these bounds are treated as damaged and ignored, so a bad
  /// settings file can never open a window too small to use or far off screen.
  static const double minSide = 200;
  static const double maxSide = 20000;
  static const double maxOffset = 20000;

  final double width;
  final double height;

  /// Top-left position; null means "let the system place the window".
  final double? x;
  final double? y;

  Map<String, Object?> toJson() => {
        'width': width,
        'height': height,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
      };

  /// Window size memory: reads saved bounds, returning null if anything is
  /// missing, not a number, or out of range.
  static WindowBounds? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final width = _side(json['width']);
    final height = _side(json['height']);
    if (width == null || height == null) return null;
    return WindowBounds(
      width: width,
      height: height,
      x: _offset(json['x']),
      y: _offset(json['y']),
    );
  }

  static double? _side(Object? value) {
    final number = _number(value);
    if (number == null) return null;
    return number >= minSide && number <= maxSide ? number : null;
  }

  static double? _offset(Object? value) {
    final number = _number(value);
    if (number == null) return null;
    return number.abs() <= maxOffset ? number : null;
  }

  static double? _number(Object? value) {
    final number = value is num ? value.toDouble() : null;
    if (number == null || !number.isFinite) return null;
    return number;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowBounds &&
      other.width == width &&
      other.height == height &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(width, height, x, y);
}

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
    this.windowBounds,
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

  /// Window size memory (desktop): last window size and position; null until
  /// the window has been moved or resized once.
  final WindowBounds? windowBounds;

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
    WindowBounds? windowBounds,
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
        windowBounds: windowBounds ?? this.windowBounds,
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
        if (windowBounds != null) 'windowBounds': windowBounds!.toJson(),
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
      windowBounds: WindowBounds.fromJson(json['windowBounds']),
    );
  }
}
