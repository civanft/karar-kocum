import 'package:flutter/material.dart';

/// Sıcak Premium Koç paleti (Sprint C-5 görsel yön).
///
/// Ham renk değerleri YALNIZ burada yaşar; ekran dosyaları bunlara doğrudan
/// erişmez — [ColorScheme] rolleri ve [AppSemanticColors] üzerinden kullanılır.
/// Değerler başlangıç paletidir; M3 kontrast uyumu için ince ayar yapıldı.
abstract final class AppPalette {
  // ---- Light ----
  static const lightPrimary = Color(0xFF2A3A8F); // derin indigo
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFDEE1F9);
  static const lightOnPrimaryContainer = Color(0xFF121C52);
  static const lightSecondary = Color(0xFF5B67B0); // lavanta-mavi (kontrast ↑)
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFE5E3F7);
  static const lightOnSecondaryContainer = Color(0xFF191E4A);
  static const lightTertiary = Color(0xFF9C5A2E); // terracotta (kontrast ↑)
  static const lightOnTertiary = Color(0xFFFFFFFF);
  static const lightTertiaryContainer = Color(0xFFF7E1D0);
  static const lightOnTertiaryContainer = Color(0xFF43230D);

  static const lightCanvas = Color(0xFFFAF7F2); // sıcak kırık beyaz zemin
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceContainer = Color(0xFFF2EEE7);
  static const lightSurfaceContainerHigh = Color(0xFFEDE8DF);
  static const lightOnSurface = Color(0xFF1C1B1A); // sıcak siyah
  static const lightOnSurfaceVariant = Color(0xFF5B564F); // pastel DEĞİL
  static const lightOutline = Color(0xFFC9C1B5);
  static const lightOutlineVariant = Color(0xFFE3DCD2);

  static const lightError = Color(0xFFB3261E);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFF9DEDC);
  static const lightOnErrorContainer = Color(0xFF410E0B);

  // Semantik ekstralar (ColorScheme'de rolü yok)
  static const lightSuccess = Color(0xFF2F7D5B); // adaçayı-yeşil (kontrast ↑)
  static const lightWarning = Color(0xFF9A6A18);
  static const lightInfo = Color(0xFF3A6EA5);
  static const lightHeroSurface = Color(0xFFEEF0FB); // hero yumuşak indigo
  static const lightHeroBorder = Color(0xFFD9DCF3);

  // ---- Dark ----
  static const darkPrimary = Color(0xFFAEB8FF);
  static const darkOnPrimary = Color(0xFF11183A);
  static const darkPrimaryContainer = Color(0xFF313D7A);
  static const darkOnPrimaryContainer = Color(0xFFDDE1FF);
  static const darkSecondary = Color(0xFFBEC4EE);
  static const darkOnSecondary = Color(0xFF232A54);
  static const darkSecondaryContainer = Color(0xFF3A4179);
  static const darkOnSecondaryContainer = Color(0xFFE1E2FF);
  static const darkTertiary = Color(0xFFE0A97E);
  static const darkOnTertiary = Color(0xFF45280F);
  static const darkTertiaryContainer = Color(0xFF60411F);
  static const darkOnTertiaryContainer = Color(0xFFFBDDC3);

  static const darkCanvas = Color(0xFF17150F); // sıcak siyah (saf değil)
  static const darkSurface = Color(0xFF201D17);
  static const darkSurfaceContainer = Color(0xFF2A2620);
  static const darkSurfaceContainerHigh = Color(0xFF352F28);
  static const darkOnSurface = Color(0xFFF3EFE7);
  static const darkOnSurfaceVariant = Color(0xFFB8B1A6);
  static const darkOutline = Color(0xFF4A443B);
  static const darkOutlineVariant = Color(0xFF332F29);

  static const darkError = Color(0xFFF2B8B5);
  static const darkOnError = Color(0xFF601410);
  static const darkErrorContainer = Color(0xFF8C1D18);
  static const darkOnErrorContainer = Color(0xFFF9DEDC);

  static const darkSuccess = Color(0xFF7FD0A6);
  static const darkWarning = Color(0xFFE8C07A);
  static const darkInfo = Color(0xFF9EC3E8);
  static const darkHeroSurface = Color(0xFF262742);
  static const darkHeroBorder = Color(0xFF3A3B5C);
}

/// ColorScheme'de karşılığı olmayan semantik roller. Tema üzerinden
/// `Theme.of(context).extension<AppSemanticColors>()` ile okunur; hard-code YOK.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.heroSurface,
    required this.heroBorder,
  });

  final Color success;
  final Color warning;
  final Color info;
  final Color heroSurface;
  final Color heroBorder;

  static const light = AppSemanticColors(
    success: AppPalette.lightSuccess,
    warning: AppPalette.lightWarning,
    info: AppPalette.lightInfo,
    heroSurface: AppPalette.lightHeroSurface,
    heroBorder: AppPalette.lightHeroBorder,
  );

  static const dark = AppSemanticColors(
    success: AppPalette.darkSuccess,
    warning: AppPalette.darkWarning,
    info: AppPalette.darkInfo,
    heroSurface: AppPalette.darkHeroSurface,
    heroBorder: AppPalette.darkHeroBorder,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? heroSurface,
    Color? heroBorder,
  }) =>
      AppSemanticColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        heroSurface: heroSurface ?? this.heroSurface,
        heroBorder: heroBorder ?? this.heroBorder,
      );

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      heroSurface: Color.lerp(heroSurface, other.heroSurface, t)!,
      heroBorder: Color.lerp(heroBorder, other.heroBorder, t)!,
    );
  }
}
