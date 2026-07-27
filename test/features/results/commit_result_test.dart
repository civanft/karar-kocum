import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_coordinator.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';

/// Sprint B — sonuç ekranı "Kararımı Verdim" akışı (widget).
/// Kural: pumpAndSettle YOK — sınırlı pump (modal sheet dersi A1).
///
/// Bugfix (fix(results)): taahhüt/geri-alma yazımı BAŞARISIZ olduğunda
/// PromiseView'a geçilmemeli, sheet kapanmamalı, follow-up çağrılmamalı ve
/// kullanıcı-dostu hata gösterilmeli. Aşağıdaki test double'lar bu yolu
/// kontrol eder (production repository/provider mimarisi DEĞİŞMEZ).
void main() {
  late ProviderContainer container;

  Future<String> pumpResult(
    WidgetTester tester, {
    DecisionRepository? repo,
    FollowUpCoordinator? coordinator,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
        if (repo != null) decisionRepositoryProvider.overrideWithValue(repo),
        if (coordinator != null)
          followUpCoordinatorProvider.overrideWithValue(coordinator),
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
    // Belirgin kazanan (NON-TIE): bu testler önerilen-önseçili normal commit
    // akışını doğrular; eşitlik ayrı bir test dosyasında kapsanır.
    const scores = [9, 5];
    for (final (i, o) in decision.options.indexed) {
      editor.setScore(o.id, decision.criteria.first.id, scores[i]);
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

  // ---- Bugfix: taahhüt/geri-alma yazım hatası yolu ----

  group('yazım hatası', () {
    testWidgets(
        'commit başarısız: open kalır, PromiseView yok, hata görünür, '
        'follow-up çağrılmaz', (tester) async {
      final repo = _ControllableRepository();
      final coordinator = _SpyFollowUpCoordinator();
      final id = await pumpResult(tester, repo: repo, coordinator: coordinator);

      await tester.tap(find.text('Kararımı Verdim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bir sonraki yazım (commit) başarısız olsun:
      repo.failApplyPatch = true;
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Karar open kaldı (iyimser state rollback):
      expect(
        container.read(decisionEditorProvider(id)).requireValue.isDecided,
        isFalse,
      );
      // PromiseView'a GEÇİLMEDİ; sheet açık, submit tekrar denenebilir:
      expect(find.text('Kararın kaydedildi.'), findsNothing);
      expect(find.text('Bu kararı veriyorum'), findsOneWidget);
      // Kullanıcı-dostu hata (ham exception değil):
      expect(find.text('Kaydedilemedi — tekrar dene.'), findsOneWidget);
      // Follow-up başarısız karara rağmen çağrılmadı:
      expect(coordinator.committed, 0);
    });

    testWidgets(
        'ilk commit başarısız → ikinci deneme başarılı: PromiseView yalnız '
        'başarıda, follow-up bir kez', (tester) async {
      final repo = _ControllableRepository();
      final coordinator = _SpyFollowUpCoordinator();
      final id = await pumpResult(tester, repo: repo, coordinator: coordinator);

      await tester.tap(find.text('Kararımı Verdim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. deneme: başarısız.
      repo.failApplyPatch = true;
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Kararın kaydedildi.'), findsNothing);
      expect(
        container.read(decisionEditorProvider(id)).requireValue.isDecided,
        isFalse,
      );
      expect(coordinator.committed, 0);

      // 2. deneme: başarılı.
      repo.failApplyPatch = false;
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(decisionEditorProvider(id)).requireValue.isDecided,
        isTrue,
      );
      // PromiseView yalnız başarıdan sonra göründü:
      expect(find.text('Kararın kaydedildi.'), findsOneWidget);
      // Follow-up tam olarak bir kez (başarılı denemede):
      expect(coordinator.committed, 1);
    });

    testWidgets(
        'revert başarısız: decided kalır, sheet kapanmaz, hata görünür, '
        'follow-up çağrılmaz', (tester) async {
      final repo = _ControllableRepository();
      final coordinator = _SpyFollowUpCoordinator();
      final id = await pumpResult(tester, repo: repo, coordinator: coordinator);

      // Önce başarılı commit (flag kapalı):
      await tester.tap(find.text('Kararımı Verdim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Söz fazını geç, alt bara dön:
      await tester.tap(find.text('Şimdi değil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        container.read(decisionEditorProvider(id)).requireValue.isDecided,
        isTrue,
      );

      // Sheet'i tekrar aç, revert yazımını başarısızlaştır:
      await tester.tap(find.text('Değiştir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      repo.failApplyPatch = true;
      await tester.tap(find.text('Kararı geri al'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Karar decided kaldı (rollback); sheet kapanmadı (buton hâlâ görünür):
      expect(
        container.read(decisionEditorProvider(id)).requireValue.isDecided,
        isTrue,
      );
      expect(find.text('Kararı geri al'), findsOneWidget);
      expect(find.text('Kaydedilemedi — tekrar dene.'), findsOneWidget);
      // Geri-alma follow-up'ı çağrılmadı:
      expect(coordinator.reverted, 0);
    });
  });
}

/// applyPatch'i istenildiğinde başarısızlaştıran in-memory repo. Kurulum
/// (createDecision + setScore flush) sırasında bayrak kapalı → başarılı;
/// commit/revert anında test bayrağı açar.
class _ControllableRepository extends InMemoryDecisionRepository {
  bool failApplyPatch = false;

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) {
    if (failApplyPatch) {
      throw Exception('simülasyon: applyPatch başarısız');
    }
    return super.applyPatch(id, patch);
  }
}

/// onCommitted/onReverted çağrı sayısını sayan casus. Süper sınıfa zararsız
/// in-memory bağımlılıklar verilir; answerPromise (söz) süperden çalışır.
class _SpyFollowUpCoordinator extends FollowUpCoordinator {
  _SpyFollowUpCoordinator()
      : super(
          preferences: InMemoryFollowUpPreferences(),
          scheduler: RecordingFollowUpScheduler(),
        );

  int committed = 0;
  int reverted = 0;

  @override
  Future<void> onCommitted({
    required String decisionId,
    required String decisionTitle,
  }) async {
    committed++;
  }

  @override
  Future<void> onReverted(String decisionId) async {
    reverted++;
  }
}
