import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/widgets/analysis_card.dart';

/// İŞ PAKETİ 5 / DİLİM D — ÇALIŞMA ANI AI BİLDİRİMİ.
///
/// Kullanıcı AI'nin ne zaman devrede olduğunu ve çıktının sınırlarını
/// ekranda görmelidir; ikon TEK BAŞINA anlam taşımaz ve bildirimler dar
/// ekran, dark mode ve yüksek text scale altında da okunur kalır.
void main() {
  Future<void> pump(
    WidgetTester tester,
    AnalysisState state, {
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    Size size = const Size(1000, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisStateView(state: state, onAnalyze: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String texts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join(' | ');

  group('CTA', () {
    testWidgets('boş durumda "AI ile oluşturulur" işareti VAR', (tester) async {
      await pump(tester, const AnalysisIdle());
      expect(find.text('AI ile oluşturulur'), findsOneWidget);
    });

    testWidgets('yarım kalan analizde de işaret KORUNUR', (tester) async {
      await pump(tester, const AnalysisResumable());
      expect(find.text('AI ile oluşturulur'), findsOneWidget);
    });
  });

  group('sonuç kartı', () {
    final success = AnalysisSuccess(AiAnalysis.mock());

    testWidgets('KALICI "AI tarafından oluşturuldu, hata içerebilir" bildirimi',
        (tester) async {
      await pump(tester, success);
      final all = texts(tester);
      expect(all, contains('AI tarafından oluşturuldu'));
      expect(all.toLowerCase(), contains('hata içerebilir'));
    });

    testWidgets('profesyonel tavsiye SINIRI gösterilir', (tester) async {
      await pump(tester, success);
      final all = texts(tester).toLowerCase();
      expect(all, contains('profesyonel'));
      // Sağlık/hukuk/finans gibi yüksek etkili alanlar açıkça anılır.
      expect(all, contains('sağlık'));
      expect(all, contains('hukuk'));
      expect(all, contains('finans'));
    });

    testWidgets('AI çıktısı KESİN GERÇEK gibi sunulmaz', (tester) async {
      await pump(tester, success);
      final all = texts(tester).toLowerCase();
      for (final claim in [
        'kesin sonuç',
        'teşhis',
        'hukuki görüş',
        'yatırım tavsiyesi',
        'garanti',
      ]) {
        expect(all.contains(claim), isFalse, reason: 'aşırı iddia: $claim');
      }
    });

    testWidgets('bildirim erişilebilir: ikon tek başına anlam taşımaz',
        (tester) async {
      await pump(tester, success);
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('AI tarafından oluşturuldu')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('yüksek text scale + dar ekran + dark: TAŞMA YOK',
        (tester) async {
      await pump(
        tester,
        success,
        textScale: 2.0,
        brightness: Brightness.dark,
        size: const Size(320, 2400),
      );
      expect(tester.takeException(), isNull);
      expect(texts(tester), contains('AI tarafından oluşturuldu'));
    });
  });
}
