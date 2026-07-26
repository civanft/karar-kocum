import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/core/widgets/app_empty_hint.dart';

/// SPRINT C-5 (Görsel Dilim 2A) — AppEmptyHint bileşen testleri.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(360, 800),
    VoidCallback? onAction,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SingleChildScrollView(
              child: AppEmptyHint(
                icon: Icons.alt_route_outlined,
                title: 'İlk seçeneğini ekle',
                message: 'Karşılaştırmak istediğin seçenekle başla. '
                    'Sonuç için en az 2 seçenek gerekir.',
                actionLabel: 'Seçenek ekle',
                onAction: onAction ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('light render: başlık + mesaj + CTA', (tester) async {
    await pump(tester);
    expect(find.text('İlk seçeneğini ekle'), findsOneWidget);
    expect(find.textContaining('en az 2 seçenek'), findsOneWidget);
    expect(find.text('Seçenek ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark render crash yok', (tester) async {
    await pump(tester, theme: AppTheme.dark);
    expect(find.text('İlk seçeneğini ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CTA tetiklenir', (tester) async {
    var tapped = false;
    await pump(tester, onAction: () => tapped = true);
    await tester.tap(find.text('Seçenek ekle'));
    expect(tapped, isTrue);
  });

  testWidgets('dar ekran (320) + textScale 1.3 taşma yok', (tester) async {
    await pump(tester, size: const Size(320, 700), textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Seçenek ekle'), findsOneWidget);
  });
}
