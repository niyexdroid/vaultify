import 'package:flutter/material.dart';

/// Vaultify colour tokens from SPEC.md "UI design". Defined once here; screens
/// read them through `context.colors`.
@immutable
class VaultifyColors extends ThemeExtension<VaultifyColors> {
  const VaultifyColors({
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.weak,
    required this.fair,
    required this.strong,
  });

  final Color primary;
  final Color onPrimary;
  final Color primarySoft;
  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color weak;
  final Color fair;
  final Color strong;

  static const light = VaultifyColors(
    primary: Color(0xFF1A9E5B),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFDCF2E5),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F6F7),
    border: Color(0xFFE3E5E8),
    text: Color(0xFF16181A),
    textSecondary: Color(0xFF5F6368),
    weak: Color(0xFFD93F3F),
    fair: Color(0xFFD9902B),
    strong: Color(0xFF1A9E5B),
  );

  static const dark = VaultifyColors(
    primary: Color(0xFF3DBE7A),
    onPrimary: Color(0xFF08210F),
    primarySoft: Color(0xFF173B28),
    background: Color(0xFF111315),
    surface: Color(0xFF1B1E21),
    border: Color(0xFF2C3034),
    text: Color(0xFFECEEF0),
    textSecondary: Color(0xFFA0A6AC),
    weak: Color(0xFFF26B6B),
    fair: Color(0xFFE8A94E),
    strong: Color(0xFF3DBE7A),
  );

  @override
  VaultifyColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primarySoft,
    Color? background,
    Color? surface,
    Color? border,
    Color? text,
    Color? textSecondary,
    Color? weak,
    Color? fair,
    Color? strong,
  }) {
    return VaultifyColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySoft: primarySoft ?? this.primarySoft,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      weak: weak ?? this.weak,
      fair: fair ?? this.fair,
      strong: strong ?? this.strong,
    );
  }

  @override
  VaultifyColors lerp(VaultifyColors? other, double t) {
    if (other == null) return this;
    return VaultifyColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      weak: Color.lerp(weak, other.weak, t)!,
      fair: Color.lerp(fair, other.fair, t)!,
      strong: Color.lerp(strong, other.strong, t)!,
    );
  }
}

/// Corner radii: 8 for controls, 12 for cards and sheets.
abstract final class Radii {
  static const double control = 8;
  static const double card = 12;
}

/// Spacing on an 8-point grid.
abstract final class Space {
  static const double half = 4;
  static const double x1 = 8;
  static const double x2 = 16;
  static const double x3 = 24;
  static const double x4 = 32;
}

/// Font families bundled in assets/fonts.
abstract final class Fonts {
  static const String ui = 'Inter';
  static const String mono = 'JetBrainsMono';
}

/// Font sizes: 12 captions, 13 body, 15 titles, 18 headings.
abstract final class FontSizes {
  static const double caption = 12;
  static const double body = 13;
  static const double title = 15;
  static const double heading = 18;
  static const double passwordDesktop = 18;
  static const double passwordMobile = 20;
}

/// Minimum touch target on mobile.
const double minTouchTarget = 44;

extension VaultifyThemeContext on BuildContext {
  VaultifyColors get colors => Theme.of(this).extension<VaultifyColors>()!;
}

/// Monospace style for showing a password.
TextStyle passwordTextStyle(VaultifyColors c, {required bool mobile}) {
  return TextStyle(
    fontFamily: Fonts.mono,
    fontSize: mobile ? FontSizes.passwordMobile : FontSizes.passwordDesktop,
    fontWeight: FontWeight.w400,
    color: c.text,
    letterSpacing: 0.5,
  );
}

abstract final class VaultifyTheme {
  static ThemeData get light => _build(VaultifyColors.light, Brightness.light);
  static ThemeData get dark => _build(VaultifyColors.dark, Brightness.dark);

  static ThemeData _build(VaultifyColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primary,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      secondaryContainer: c.primarySoft,
      onSecondaryContainer: c.primary,
      error: c.weak,
      onError: c.onPrimary,
      surface: c.background,
      onSurface: c.text,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainerHighest: c.surface,
      outline: c.border,
      outlineVariant: c.border,
      surfaceTint: Colors.transparent,
      shadow: Colors.transparent,
      scrim: Colors.black54,
    );

    TextStyle style(double size, FontWeight weight, Color color) =>
        TextStyle(fontFamily: Fonts.ui, fontSize: size, fontWeight: weight, color: color);

    final regular = FontWeight.w400;
    final medium = FontWeight.w500;
    final textTheme = TextTheme(
      headlineSmall: style(FontSizes.heading, medium, c.text),
      titleLarge: style(FontSizes.heading, medium, c.text),
      titleMedium: style(FontSizes.title, medium, c.text),
      titleSmall: style(FontSizes.body, medium, c.text),
      bodyLarge: style(FontSizes.title, regular, c.text),
      bodyMedium: style(FontSizes.body, regular, c.text),
      bodySmall: style(FontSizes.caption, regular, c.textSecondary),
      labelLarge: style(FontSizes.body, medium, c.text),
      labelMedium: style(FontSizes.caption, medium, c.text),
      labelSmall: style(FontSizes.caption, regular, c.textSecondary),
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
    );
    final borderSide = BorderSide(color: c.border, width: 1);
    OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: color, width: 1),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: Fonts.ui,
      textTheme: textTheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.border,
      shadowColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      extensions: [c],
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
        shape: Border(bottom: borderSide),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: borderSide,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(0, minTouchTarget),
          shape: controlShape,
          elevation: 0,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(0, minTouchTarget),
          side: borderSide,
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: c.textSecondary),
        border: inputBorder(c.border),
        enabledBorder: inputBorder(c.border),
        focusedBorder: inputBorder(c.primary),
        errorBorder: inputBorder(c.weak),
        focusedErrorBorder: inputBorder(c.weak),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: c.textSecondary, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: c.border,
        thumbColor: c.primary,
        overlayColor: c.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.onPrimary : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.primary : c.surface,
        ),
        trackOutlineColor: WidgetStatePropertyAll(c.border),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.primary,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.primary,
        dividerColor: c.border,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: regular),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.background,
        indicatorColor: c.primarySoft,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.card)),
          side: borderSide,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: borderSide,
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.background),
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: textTheme.bodySmall?.copyWith(color: c.background),
        decoration: BoxDecoration(
          color: c.text,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
    );
  }
}
