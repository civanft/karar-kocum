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

  testWidgets('varsayılan aksiyon ikonu Icons.add', (tester) async {
    await pump(tester);
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    // FilledButton.icon → içinde Icon(Icons.add) render eder.
    expect(
      find.descendant(
        of: find.byWidget(btn),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
  });

  testWidgets('özel actionIcon verilince o gösterilir', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppEmptyHint(
            icon: Icons.tune_outlined,
            title: 'Puanlamaya hazırlan',
            message: 'Önce seçenekleri ekle.',
            actionLabel: 'Seçeneklere git',
            actionIcon: Icons.arrow_forward_rounded,
            onAction: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
