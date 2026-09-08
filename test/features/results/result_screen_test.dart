import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/widgets/analysis_card.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';
import 'package:karar_veriyorum/features/results/presentation/widgets/result_rank_tile.dart';
import 'package:karar_veriyorum/features/results/presentation/widgets/result_winner_panel.dart';

/// Görsel Dilim 3 — ResultScreen sunum hiyerarşisi testleri.
/// Kural: pumpAndSettle YOK — sınırlı pump.
void main() {
  _loadErrorContract();

  late ProviderContainer container;

  Future<String> pumpScreen(
    WidgetTester tester, {
    bool commit = false,
    bool incomplete = false,
    String title = 'Telefon kararı',
    List<String> options = const ['iPhone', 'Samsung'],
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(1000, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: [autosaveDebounceProvider.overrideWithValue(Duration.zero)],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: title,
      initialCriteria: const [(name: 'Fiyat', weight: 8)],
      initialOptions: options,
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    // İLK erişim dinleme olsun: .notifier/.future okumaları autoDispose
    // timer'ı (mayNeedDispose) zamanlamasın diye önce bir dinleyici kur.
    final sub =
        container.listen(decisionEditorProvider(decision.id), (_, __) {});
    addTearDown(sub.close);
    final editor = container.read(decisionEditorProvider(decision.id).notifier);
    await container.read(decisionEditorProvider(decision.id).future);
    if (!incomplete) {
      for (final o in decision.options) {
        editor.setScore(o.id, decision.criteria.first.id, 7);
      }
      // Debounce timer'ını deterministik boşalt (bekleyen timer bırakma).
      await editor.flushPendingWrites();
    }
    if (commit) await editor.commitDecision(decision.options.last.id);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ResultScreen(decisionId: decision.id),
        ),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, __) => const Scaffold(body: Text('EDIT SCREEN')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
    return decision.id;
  }

  testWidgets('AppBar karar başlığını gösterir (statik "Sonuç" değil)',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('Telefon kararı'), findsOneWidget);
    expect(find.text('Sonuç'), findsNothing);
  });

  testWidgets('yeni hiyerarşi: winner paneli + "Puan dağılımı" + sahiplik + AI',
      (tester) async {
    await pumpScreen(tester);
    expect(find.byType(ResultWinnerPanel), findsOneWidget);
    expect(find.text('Analizin hazır'), findsOneWidget);
    expect(find.text('Puan dağılımı'), findsOneWidget);
    expect(find.text('Bu bir öneri; son karar senin.'), findsOneWidget);
    expect(find.byType(AnalysisSection), findsOneWidget);
  });

  testWidgets('tüm seçenekler puan dağılımında listelenir', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(ResultRankTile), findsNWidgets(2));
  });

  testWidgets('undecided: "Kararımı Verdim" CTA korunur', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Kararımı Verdim'), findsOneWidget);
  });

  testWidgets('decided: "X seçildi" + "Değiştir" korunur', (tester) async {
    await pumpScreen(tester, commit: true);
    expect(find.textContaining('seçildi'), findsOneWidget);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(find.text('Kararımı Verdim'), findsNothing);
  });

  testWidgets(
      'eksik matris: AppEmptyHint (başlık + ikon) + korunan metin/route',
      (tester) async {
    await pumpScreen(tester, incomplete: true);
    // AppBar karar başlığını gösterir (statik "Sonuç" değil):
    expect(find.text('Telefon kararı'), findsOneWidget);
    // Tasarım diliyle hizalı boş-durum:
    expect(find.text('Puanlama tamamlanmadı'), findsOneWidget);
    expect(
      find.text('Sonuç için önce tüm puanlamayı tamamla.'),
      findsOneWidget,
    );
    expect(find.text('Puanlamaya Dön'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    // Yeni hiyerarşi bileşenleri bu durumda görünmez:
    expect(find.byType(ResultWinnerPanel), findsNothing);

    // CTA doğru /edit rotasına gider:
    await tester.tap(find.text('Puanlamaya Dön'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('EDIT SCREEN'), findsOneWidget);
  });

  testWidgets('eksik matris: dar ekran (360) + textScale 1.3 taşma yok',
      (tester) async {
    await pumpScreen(
      tester,
      incomplete: true,
      title: 'Uzun bir karar başlığı eksik puanlama taşma testi için yazıldı',
      size: const Size(360, 800),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Puanlama tamamlanmadı'), findsOneWidget);
  });

  testWidgets('dark render crash yok', (tester) async {
    await pumpScreen(tester, theme: AppTheme.dark);
    expect(find.text('Analizin hazır'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dar ekran (360) + textScale 1.3 taşma yok', (tester) async {
    await pumpScreen(
      tester,
      title: 'Uzun bir karar başlığı taşma testi için buraya yazıldı',
      options: const [
        'Çok uzun bir seçenek adı taşma testi için',
        'İkinci seçenek',
      ],
      size: const Size(360, 800),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Puan dağılımı'), findsOneWidget);
  });
}

/// İŞ PAKETİ 4 / DİLİM D — yükleme hatası ham exception SIZDIRMAZ.
void _loadErrorContract() {
  testWidgets('load error güvenli mesaj gösterir, raw exception göstermez',
      (tester) async {
    // Depo hata fırlatır → editör AsyncError'a düşer → ekran hata dalı.
    final container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(_ThrowingRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ResultScreen(decisionId: 'yok')),
      ),
    );
    await tester.pump();

    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(
      find.text('Sonuç yüklenemedi. Bağlantını kontrol edip tekrar dene.'),
      findsOneWidget,
    );
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });
}

/// Yükleme hatası üreten depo — ham mesaj UI'a SIZMAMALI.
class _ThrowingRepository implements DecisionRepository {
  @override
  Future<Decision?> getById(String id) async =>
      throw StateError('firestore permission-denied users/u1');

  @override
  Stream<Decision?> watchById(String id) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
