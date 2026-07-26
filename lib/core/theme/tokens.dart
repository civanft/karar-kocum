import 'package:flutter/material.dart';

/// Tasarım token'ları — TEKNIK-MIMARI.md §6.3 (4'lük spacing ızgarası).
abstract final class AppTokens {
  static const Color seedColor = Color(0xFF1B2A6B);

  // Spacing (4'lük ızgara)
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // Radius
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 20;
  static const double radiusXl = 28; // hero/coach panel

  // Bileşen ölçüleri
  static const double buttonMinHeight = 52; // birincil CTA yüksekliği
  static const double cardElevation = 0; // düz; ayrım ince border ile

  // Elevation
  static const double elevSm = 1;

  // Süreler
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durMed = Duration(milliseconds: 300);

  // Erişilebilirlik
  static const double minTouchTarget = 48;
}
