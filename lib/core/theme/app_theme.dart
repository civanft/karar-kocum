import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material 3 tema — beyaz ağırlıklı, premium, dark mode destekli.
/// Tohum rengi tasarım aşamasında kesinleşecek (şimdilik lacivert).
abstract final class AppTheme {
  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(seedColor: AppTokens.seedColor);
  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: AppTokens.seedColor,
    brightness: Brightness.dark,
  );

  static ThemeData get light => _base(_lightScheme);
  static ThemeData get dark => _base(_darkScheme);

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      );
}
