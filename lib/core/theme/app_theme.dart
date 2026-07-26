import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'tokens.dart';

/// Material 3 tema — "Sıcak Premium Koç" yönü (Sprint C-5).
/// Açık ColorScheme + bilinçli bileşen temaları; artık salt fromSeed değil.
/// Zemin sıcak kırık beyaz (light) / sıcak siyah (dark) — saf beyaz/siyah YOK.
abstract final class AppTheme {
  static ThemeData get light => _build(_lightScheme, AppSemanticColors.light);
  static ThemeData get dark => _build(_darkScheme, AppSemanticColors.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppPalette.lightPrimary,
    onPrimary: AppPalette.lightOnPrimary,
    primaryContainer: AppPalette.lightPrimaryContainer,
    onPrimaryContainer: AppPalette.lightOnPrimaryContainer,
    secondary: AppPalette.lightSecondary,
    onSecondary: AppPalette.lightOnSecondary,
    secondaryContainer: AppPalette.lightSecondaryContainer,
    onSecondaryContainer: AppPalette.lightOnSecondaryContainer,
    tertiary: AppPalette.lightTertiary,
    onTertiary: AppPalette.lightOnTertiary,
    tertiaryContainer: AppPalette.lightTertiaryContainer,
    onTertiaryContainer: AppPalette.lightOnTertiaryContainer,
    error: AppPalette.lightError,
    onError: AppPalette.lightOnError,
    errorContainer: AppPalette.lightErrorContainer,
    onErrorContainer: AppPalette.lightOnErrorContainer,
    surface: AppPalette.lightSurface,
    onSurface: AppPalette.lightOnSurface,
    surfaceContainerLowest: AppPalette.lightSurface,
    surfaceContainerLow: AppPalette.lightCanvas,
    surfaceContainer: AppPalette.lightSurfaceContainer,
    surfaceContainerHigh: AppPalette.lightSurfaceContainerHigh,
    surfaceContainerHighest: AppPalette.lightSurfaceContainerHigh,
    onSurfaceVariant: AppPalette.lightOnSurfaceVariant,
    outline: AppPalette.lightOutline,
    outlineVariant: AppPalette.lightOutlineVariant,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppPalette.darkPrimary,
    onPrimary: AppPalette.darkOnPrimary,
    primaryContainer: AppPalette.darkPrimaryContainer,
    onPrimaryContainer: AppPalette.darkOnPrimaryContainer,
    secondary: AppPalette.darkSecondary,
    onSecondary: AppPalette.darkOnSecondary,
    secondaryContainer: AppPalette.darkSecondaryContainer,
    onSecondaryContainer: AppPalette.darkOnSecondaryContainer,
    tertiary: AppPalette.darkTertiary,
    onTertiary: AppPalette.darkOnTertiary,
    tertiaryContainer: AppPalette.darkTertiaryContainer,
    onTertiaryContainer: AppPalette.darkOnTertiaryContainer,
    error: AppPalette.darkError,
    onError: AppPalette.darkOnError,
    errorContainer: AppPalette.darkErrorContainer,
    onErrorContainer: AppPalette.darkOnErrorContainer,
    surface: AppPalette.darkSurface,
    onSurface: AppPalette.darkOnSurface,
    surfaceContainerLowest: AppPalette.darkCanvas,
    surfaceContainerLow: AppPalette.darkSurface,
    surfaceContainer: AppPalette.darkSurfaceContainer,
    surfaceContainerHigh: AppPalette.darkSurfaceContainerHigh,
    surfaceContainerHighest: AppPalette.darkSurfaceContainerHigh,
    onSurfaceVariant: AppPalette.darkOnSurfaceVariant,
    outline: AppPalette.darkOutline,
    outlineVariant: AppPalette.darkOutlineVariant,
  );

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final canvas = scheme.brightness == Brightness.light
        ? AppPalette.lightCanvas
        : AppPalette.darkCanvas;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: [semantic],
    );

    final radiusMd = BorderRadius.circular(AppTokens.radiusMd);

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, scheme),
      appBarTheme: AppBarTheme(
        // Zeminle bütünleşir, ağır gölge yok.
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: AppTokens.cardElevation,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppTokens.buttonMinHeight),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          side: BorderSide(color: scheme.outline),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppTokens.minTouchTarget),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s4,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: AppTokens.s4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    );
  }

  /// M3 varsayılanından daha güçlü hiyerarşi: başlıklar iri/kalın,
  /// gövde okunur. Sistem fontu (paket eklenmez).
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        height: 1.1,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
