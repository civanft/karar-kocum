import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';

/// Sprint B — sonuç ekranı "Kararımı Verdim" akışı (widget).
/// Kural: pumpAndSettle YOK — sınırlı pump (modal sheet dersi A1).
void main() {
  late ProviderContainer container;

  Future<String> pumpResult(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    // 2 seçenek × 1 kriter, tam puanlı → sonuç ekranı açılır.
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Telefon kararı',
      initialCriteria: const [(name: 'Fiyat', weight: 8)],
      initialOptions: const ['iPhone', 'Samsung'],
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    final editor = container.read(decisionEditorProvider(decision.id).notifier);
    await container.read(decisionEditorProvider(decision.id).future);
    for (final o in decision.options) {
      editor.setScore(o.id, decision.criteria.first.id, 7);
    }
    // DİKKAT: burada `await Future.delayed(...)` KULLANILMAZ — testWidgets
    // FakeAsync zone'unda çalışır, Future.delayed bir TIMER'dır ve sahte
    // saat yalnız tester.pump() ile ilerler; pump'tan önce await etmek
    // kalıcı deadlock üretir (--timeout bile kesemez). setScore state'i
    // zaten senkron günceller; bekleyen debounce yazımını aşağıdaki
    // pumpWidget + pump akışı flush eder.

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ResultScreen(decisionId: decision.id),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return decision.id;
  }

  testWidgets('"Kararımı Verdim" → seçim → decided + vurgu (✓) görünür',
      (tester) async {
    final id = await pumpResult(tester);

    // Başta CTA var, decided değil:
    expect(find.text('Kararımı Verdim'), findsOneWidget);

    await tester.tap(find.text('Kararımı Verdim'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sheet açıldı; Samsung'u seç. NOT: 'Samsung' hem sıralama barında
    // hem sheet'te var → .last ile sheet'teki (sonra eklenen) hedeflenir.
    await tester.tap(find.text('Samsung').last);
    await tester.pump();
    await tester.tap(find.text('Bu kararı veriyorum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // decided oldu:
    final d = container.read(decisionEditorProvider(id)).requireValue;
    expect(d.isDecided, isTrue);
    expect(
      d.options.firstWhere((o) => o.id == d.chosenOptionId).title,
      'Samsung',
    );

    // Alt bar "Değiştir" + vurgu check_circle görünür:
    expect(find.text('Değiştir'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('Değiştir → geri al: decided → open', (tester) async {
    final id = await pumpResult(tester);

    // Önce UI üzerinden commit (test 1 ile aynı gerçek akış — programatik
    // commit FakeAsync/stream zamanlamasıyla harness'ta güvenilir değil).
    await tester.tap(find.text('Kararımı Verdim'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Bu kararı veriyorum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(decisionEditorProvider(id)).requireValue.isDecided,
      isTrue,
    );

    // SPRINT C: sheet artık kapanmıyor, SÖZ fazına geçiyor. Alt bara
    // ulaşmak için önce sözü geçmek gerekiyor.
    await tester.tap(find.text('Şimdi değil'));
    await tester.pump();
    // Sheet kapanma animasyonu bitmeden alt bar hit-test almaz.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Değiştir'), findsOneWidget);

    // Şimdi geri al:
    await tester.tap(find.text('Değiştir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Kararı geri al'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(decisionEditorProvider(id)).requireValue.isDecided,
      isFalse,
    );
    expect(find.text('Kararımı Verdim'), findsOneWidget);
  });
}
