import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_palette.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/core/theme/tokens.dart';

/// SPRINT C-5 — tema temeli testleri.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final light = AppTheme.light;
  final dark = AppTheme.dark;

  test('light scaffold saf beyaz DEĞİL', () {
    expect(light.scaffoldBackgroundColor, isNot(const Color(0xFFFFFFFF)));
    expect(light.scaffoldBackgroundColor, AppPalette.lightCanvas);
  });

  test('dark scaffold saf siyah DEĞİL', () {
    expect(dark.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
    expect(dark.scaffoldBackgroundColor, AppPalette.darkCanvas);
  });

  test('light primary/onPrimary kontrastı AA (>= 4.5)', () {
    final c = _contrast(
      light.colorScheme.primary,
      light.colorScheme.onPrimary,
    );
    expect(c, greaterThanOrEqualTo(4.5));
  });

  test('light ana metin/zemin kontrastı AA (>= 4.5)', () {
    final c = _contrast(
      light.colorScheme.onSurface,
      light.scaffoldBackgroundColor,
    );
    expect(c, greaterThanOrEqualTo(4.5));
  });

  test('dark ana metin/zemin kontrastı AA (>= 4.5)', () {
    final c = _contrast(
      dark.colorScheme.onSurface,
      dark.scaffoldBackgroundColor,
    );
    expect(c, greaterThanOrEqualTo(4.5));
  });

  test('ikincil metin/zemin kontrastı en az AA-large (>= 3.0)', () {
    final c = _contrast(
      light.colorScheme.onSurfaceVariant,
      light.scaffoldBackgroundColor,
    );
    expect(c, greaterThanOrEqualTo(3.0));
  });

  test('birincil buton minimum yüksekliği tanımlı', () {
    final size =
        light.filledButtonTheme.style?.minimumSize?.resolve({})?.height;
    expect(size, AppTokens.buttonMinHeight);
    expect(AppTokens.buttonMinHeight, greaterThanOrEqualTo(48));
  });

  test('light ve dark tema oluşturulabiliyor + M3', () {
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
  });

  test('semantik renk extension her iki temada mevcut', () {
    expect(light.extension<AppSemanticColors>(), isNotNull);
    expect(dark.extension<AppSemanticColors>(), isNotNull);
  });

  test('AppBar ağır gölge taşımaz (zeminle bütünleşir)', () {
    expect(light.appBarTheme.elevation, 0);
    expect(light.appBarTheme.backgroundColor, light.scaffoldBackgroundColor);
  });
}
