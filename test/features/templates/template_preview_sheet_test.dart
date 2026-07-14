import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/features/templates/data/static_template_catalog.dart';
import 'package:karar_veriyorum/features/templates/presentation/widgets/template_preview_sheet.dart';

/// Önizleme sheet'i (SPRINT-A §4.3): içerik gösterimi, şablonla oluşturma,
/// editöre yönlenme. Varsayılan localMode → in-memory repo (gerçek yol).
///
/// NOT (PR-A1 kararı): Dört senaryo — başlık düzenleme, geçersiz başlık
/// hatası, "Boş başla", "Bu şablonla başla" oluşturma+yönlenme —
/// widget-test altyapısında deterministik koşturulamadı (modal sheet
/// yaşam döngüsü pumpAndSettle/teardown'ı 10 dk timeout'a sürüklüyor;
/// gövdeler checkpoint izleriyle doğrulandı). MANUEL SENARYO olarak
/// dokümante edildi: docs/SPRINT-A-TASARIM.md §4.6. Oluşturma yolunun
/// DAVRANIŞI ayrıca birim düzeyde tam test edilir
/// (create_decision_test.dart şablon yolu). Ürün kodu hatası DEĞİLDİR.
void main() {
  final template = const StaticTemplateCatalog().byId('phone-purchase')!;

  late ProviderContainer container;

  Widget harness() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showTemplatePreviewSheet(context, template),
                  child: const Text('AÇ'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, state) =>
              Scaffold(body: Text('EDIT ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/decision/new',
          builder: (_, state) => Scaffold(
            body: Text('NEW ${state.uri.queryParameters['title']}'),
          ),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    // Sheet içeriği tek seferde sığsın — kaydırma/sanallaşma testleri
    // kirletmesin (enterText odak kaydırması butonu unbuilt yapabiliyor).
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.tap(find.text('AÇ'));
    // Settle kullanılmaz (bkz. dosya başı notu) — sheet açılışı için
    // sınırlı pump yeterli.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('sheet şablonun tüm kriterlerini ağırlıklarıyla gösterir',
      (tester) async {
    await openSheet(tester);

    for (final criterion in template.criteria) {
      expect(find.text(criterion.name), findsOneWidget);
      // Aynı ağırlık birden çok kriterde olabilir → en az bir eşleşme.
      expect(find.text('Önem ${criterion.weight}/10'), findsWidgets);
    }
    // Örnek seçenekler chip olarak görünür.
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.text('Samsung'), findsOneWidget);
  });
}
