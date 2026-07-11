import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/widgets/analysis_card.dart';

/// 5 durumun görsel sözleşmesi — repo'nun ilk widget testleri.
void main() {
  Future<void> pump(
    WidgetTester tester,
    AnalysisState state, {
    VoidCallback? onAnalyze,
    VoidCallback? onRetry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalysisStateView(
              state: state,
              onAnalyze: onAnalyze ?? () {},
              onRetry: onRetry ?? () {},
              onReanalyze: () {},
              onFeedback: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(AppTokensDur.med); // AnimatedSwitcher otursun
  }

  testWidgets('1. boş durum: başlık, açıklama ve CTA butonu', (tester) async {
    var tapped = false;
    await pump(
      tester,
      const AnalysisIdle(),
      onAnalyze: () => tapped = true,
    );

    expect(find.text('AI Analizi'), findsOneWidget);
    expect(find.text('AI Analizini Başlat'), findsOneWidget);

    await tester.tap(find.text('AI Analizini Başlat'));
    expect(tapped, isTrue);
  });

  testWidgets('1b. bos durum: kalan kredi sayaci (6C-2)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AnalysisStateView(
            state: const AnalysisIdle(),
            remainingCredits: 3,
            onAnalyze: () {},
          ),
        ),
      ),
    );
    await tester.pump(AppTokensDur.med);
    expect(find.text('Kalan ücretsiz analiz: 3'), findsOneWidget);
  });

  testWidgets('2. loading: spinner + iskelet + süre ipucu', (tester) async {
    await pump(tester, const AnalysisLoading());

    expect(find.text('Kararın analiz ediliyor…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('10 saniyeden kısa'), findsOneWidget);
  });

  testWidgets('3. başarı: öneri bandı, üç bölüm, güven rozeti, geri bildirim',
      (tester) async {
    await pump(tester, AnalysisSuccess(AiAnalysis.mock()));

    expect(find.textContaining('Veriler İstanbul'), findsOneWidget); // öneri
    expect(find.text('Güçlü yönler'), findsOneWidget);
    expect(find.text('Zayıf yönler'), findsOneWidget);
    expect(find.text('Riskler'), findsOneWidget);
    expect(find.text('Orta güven'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.text('Yeniden analiz et'), findsOneWidget);
    expect(
      find.textContaining('karar destek aracıdır'), // sorumluluk çerçevesi
      findsOneWidget,
    );
  });

  testWidgets('4. hata: mesaj + tekrar dene (retryable)', (tester) async {
    var retried = false;
    await pump(
      tester,
      const AnalysisError(message: 'Bağlantı sorunu.', retryable: true),
      onRetry: () => retried = true,
    );

    expect(find.text('Analiz yapılamadı'), findsOneWidget);
    expect(find.text('Bağlantı sorunu.'), findsOneWidget);

    await tester.tap(find.text('Tekrar Dene'));
    expect(retried, isTrue);
  });

  testWidgets('4b. hata retryable=false: buton görünmez', (tester) async {
    await pump(
      tester,
      const AnalysisError(message: 'Kalıcı hata.', retryable: false),
    );
    expect(find.text('Tekrar Dene'), findsNothing);
  });

  testWidgets('5. kota: limit metni + skorların açık kaldığı bilgisi',
      (tester) async {
    await pump(tester, const AnalysisQuotaExceeded(totalCredits: 5));

    expect(find.text('Ücretsiz analiz hakkın bitti'), findsOneWidget);
    expect(find.textContaining('5 ücretsiz AI analizinin'), findsOneWidget);
    // Kredi modeli (6C-2): yenilenme vaadi OLMAMALI
    expect(find.textContaining('yenilenecek'), findsNothing);
    expect(
      find.textContaining('her zaman kullanılabilir'),
      findsOneWidget,
    );
  });
}

/// Test yardımcı sabiti (tokens'taki durMed'in test kopyası).
abstract final class AppTokensDur {
  static const med = Duration(milliseconds: 300);
}
