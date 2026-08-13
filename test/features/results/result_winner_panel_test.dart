import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_palette.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/results/presentation/widgets/result_winner_panel.dart';
import 'package:karar_veriyorum/features/scoring/domain/entities/scoring_types.dart';

/// Görsel Dilim 3 — ResultWinnerPanel bileşen testleri.
/// Kural: pumpAndSettle YOK; taşma testleri takeException ile.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Confidence confidence,
    String title = 'iPhone 16',
    bool isTie = false,
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(390, 844),
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
              child: ResultWinnerPanel(
                title: title,
                confidence: confidence,
                isTie: isTie,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color iconColorOf(WidgetTester tester, IconData icon) =>
      tester.widget<Icon>(find.byIcon(icon)).color!;

  testWidgets('ortak: eyebrow + bağlam + başlık', (tester) async {
    await pump(tester, confidence: Confidence.high);
    expect(find.text('Analizin hazır'), findsOneWidget);
    expect(find.text('Öne çıkan seçenek'), findsOneWidget);
    expect(find.text('iPhone 16'), findsOneWidget);
  });

  testWidgets('high: metin + success rengi + verified ikon', (tester) async {
    await pump(tester, confidence: Confidence.high);
    expect(find.text('Yüksek güven'), findsOneWidget);
    expect(
      find.text('Puanlamana göre bu seçenek belirgin biçimde öne çıkıyor.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    expect(
      iconColorOf(tester, Icons.verified_outlined),
      AppSemanticColors.light.success,
    );
  });

  testWidgets('medium: metin + warning rengi + balance ikon', (tester) async {
    await pump(tester, confidence: Confidence.medium);
    expect(find.text('Orta güven'), findsOneWidget);
    expect(
      find.text('Puanlamana göre bu seçenek öne çıkıyor.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.balance_outlined), findsOneWidget);
    expect(
      iconColorOf(tester, Icons.balance_outlined),
      AppSemanticColors.light.warning,
    );
  });

  testWidgets('low: "Yakın sonuç" + info rengi + farklı ikon; kırmızı DEĞİL',
      (tester) async {
    await pump(tester, confidence: Confidence.low);
    expect(find.text('Yakın sonuç'), findsOneWidget);
    expect(
      find.text('Sonuçlar birbirine yakın; kendi önceliklerini de düşün.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.compare_arrows_outlined), findsOneWidget);
    // "Düşük güven" gibi sert ifade YOK:
    expect(find.textContaining('Düşük'), findsNothing);

    final color = iconColorOf(tester, Icons.compare_arrows_outlined);
    // info kullanılır; error/kırmızı ASLA.
    expect(color, AppSemanticColors.light.info);
    expect(color, isNot(AppTheme.light.colorScheme.error));
  });

  testWidgets('her seviye farklı ikon kullanır', (tester) async {
    await pump(tester, confidence: Confidence.high);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    expect(find.byIcon(Icons.balance_outlined), findsNothing);
    expect(find.byIcon(Icons.compare_arrows_outlined), findsNothing);
  });

  testWidgets(
      'tie: "Başa baş sonuç" + "Karar sende" + "Eşit puan" (info, kırmızı '
      'değil); kazanan dili yok', (tester) async {
    // confidence verilse bile tie önceliklidir:
    await pump(tester, confidence: Confidence.high, isTie: true);
    expect(find.text('Başa baş sonuç'), findsOneWidget);
    expect(find.text('Karar sende'), findsOneWidget);
    expect(find.text('Eşit puan'), findsOneWidget);
    expect(
      find.textContaining('En yüksek puanı paylaşan seçenekler var'),
      findsOneWidget,
    );
    // Kazanan/önerilen dili görünmez:
    expect(find.text('Öne çıkan seçenek'), findsNothing);
    expect(find.text('Yüksek güven'), findsNothing);
    expect(find.text('iPhone 16'), findsNothing);

    final color = iconColorOf(tester, Icons.balance_outlined);
    expect(color, AppSemanticColors.light.info);
    expect(color, isNot(AppTheme.light.colorScheme.error));
  });

  testWidgets('tie dark + uzun başlık + 320 + textScale 1.3 taşma yok',
      (tester) async {
    await pump(
      tester,
      confidence: Confidence.high,
      isTie: true,
      theme: AppTheme.dark,
      size: const Size(320, 800),
      textScale: 1.3,
    );
    expect(find.text('Karar sende'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark render crash yok', (tester) async {
    await pump(tester, confidence: Confidence.medium, theme: AppTheme.dark);
    expect(find.text('Orta güven'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uzun ad + dar ekran (320) + textScale 1.3 taşma yok',
      (tester) async {
    await pump(
      tester,
      confidence: Confidence.low,
      title: 'Çok uzun bir seçenek adı taşma testi için buraya yazıldı',
      size: const Size(320, 800),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Yakın sonuç'), findsOneWidget);
  });
}
