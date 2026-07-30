import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';
import 'package:karar_veriyorum/features/journey/presentation/screens/check_in_screen.dart';

/// SPRINT C.2 — 1 hafta kontrol ekranı.
/// Kural (A1 dersi): pumpAndSettle YOK, sınırlı pump.
void main() {
  late ProviderContainer container;
  late RecordingFollowUpScheduler scheduler;
  late String lastRoute;

  Future<String> pumpCheckIn(
    WidgetTester tester, {
    bool decided = true,
    DecisionCheckIn? alreadyAnswered,
    DecisionRepository? repo,
    bool useInvalidId = false,
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(1000, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    scheduler = RecordingFollowUpScheduler();
    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
        followUpPreferencesProvider
            .overrideWithValue(InMemoryFollowUpPreferences()),
        followUpSchedulerProvider.overrideWithValue(scheduler),
        // Gönderim yazımını kontrol/geciktirmek için (kaydediliyor/başarısız).
        if (repo != null) decisionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

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
    if (decided) {
      await editor.commitDecision(decision.options.last.id); // Samsung
    }
    if (alreadyAnswered != null) {
      await editor.submitCheckIn(alreadyAnswered);
    }

    final screenId = useInvalidId ? 'boyle-bir-karar-yok' : decision.id;
    lastRoute = '/decision/$screenId/check-in';
    final router = GoRouter(
      initialLocation: lastRoute,
      routes: [
        GoRoute(
          path: '/decision/:id/check-in',
          builder: (_, s) => CheckInScreen(decisionId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/decision/:id/result',
          builder: (_, s) {
            lastRoute = '/decision/${s.pathParameters['id']}/result';
            return const Scaffold(body: Text('SONUÇ EKRANI'));
          },
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) {
            lastRoute = '/home';
            return const Scaffold(body: Text('HOME'));
          },
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
    // Riverpod autoDispose, kurulum penceresinde (editör okundu ama henüz
    // hiçbir widget izlemiyorken) bir imha Timer'ı kurar. Ekran artık
    // izliyor; bekleyeni burada boşaltmazsak test sonunda "Timer is still
    // pending" olarak patlar.
    await tester.pump(const Duration(milliseconds: 1));
    return decision.id;
  }

  testWidgets('seçilen seçenek ve soru gösterilir', (tester) async {
    await pumpCheckIn(tester);

    expect(find.textContaining('Samsung kararının üzerinden'), findsOneWidget);
    expect(find.text('Nasıl gidiyor?'), findsOneWidget);
    expect(find.text('Memnunum'), findsOneWidget);
    expect(find.text('Kararsızım'), findsOneWidget);
    expect(find.text('Pişmanım'), findsOneWidget);
  });

  testWidgets('"Pişmanım" → checkInStatus + checkedInAt yazılır', (t) async {
    final id = await pumpCheckIn(t);

    await t.tap(find.text('Pişmanım'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    final d = container.read(decisionEditorProvider(id)).requireValue;
    expect(d.checkInStatus, DecisionCheckIn.regret);
    expect(d.checkedInAt, isNotNull);
    expect(d.hasCheckedIn, isTrue);
    // Taahhüt bozulmadı:
    expect(d.isDecided, isTrue);
  });

  testWidgets('cevap sonrası bildirim temizlenir ve sonuca yönlenir',
      (tester) async {
    final id = await pumpCheckIn(tester);

    await tester.tap(find.text('Memnunum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scheduler.cancelled, contains(id));
    expect(lastRoute, '/decision/$id/result');
    expect(find.text('SONUÇ EKRANI'), findsOneWidget);
  });

  testWidgets('zaten cevaplanmışsa soru TEKRAR sorulmaz (tek kayıt)',
      (tester) async {
    await pumpCheckIn(tester, alreadyAnswered: DecisionCheckIn.happy);

    expect(find.text('Bu kararın kontrolünü zaten yaptın.'), findsOneWidget);
    expect(find.text('Memnunum'), findsNothing);
  });

  testWidgets('karar geri alınmışsa kontrol sorulmaz', (tester) async {
    await pumpCheckIn(tester, decided: false);

    expect(find.text('Bu karar henüz verilmiş değil.'), findsOneWidget);
    expect(find.text('Memnunum'), findsNothing);
  });

  testWidgets('cevap iki kez yazılmaya çalışılırsa ikincisi düşer',
      (tester) async {
    final id = await pumpCheckIn(tester);
    final editor = container.read(decisionEditorProvider(id).notifier);

    await editor.submitCheckIn(DecisionCheckIn.happy);
    await editor.submitCheckIn(DecisionCheckIn.regret); // yok sayılmalı

    expect(
      container.read(decisionEditorProvider(id)).requireValue.checkInStatus,
      DecisionCheckIn.happy,
    );
  });

  // ---- Gönderim flaşı düzeltmesi (cihaz testinde gözlenen UI kusuru) ----

  testWidgets('gönderim sürerken KAYDEDİLİYOR görünür, _AlreadyDone GÖRÜNMEZ',
      (tester) async {
    final repo = _GatedRepo(InMemoryDecisionRepository());
    addTearDown(repo.dispose);
    await pumpCheckIn(tester, repo: repo);

    // Sonraki yazımı (check-in) askıya al:
    final gate = repo.gateNextPatch();
    await tester.tap(find.text('Memnunum'));
    await tester
        .pump(); // _saving=true, iyimser güncelleme, applyPatch beklemede

    // Kararlı kaydediliyor görünümü:
    expect(find.text('Cevabın kaydediliyor…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Flaş YOK:
    expect(find.text('Bu kararın kontrolünü zaten yaptın.'), findsNothing);
    // İkinci gönderim yapılamaz (seçenekler render edilmiyor):
    expect(find.text('Memnunum'), findsNothing);
    expect(find.text('Pişmanım'), findsNothing);

    // Yazım tamamlanınca sonuç ekranına gidilir, flaş hiç görünmedi:
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('SONUÇ EKRANI'), findsOneWidget);
    expect(find.text('Bu kararın kontrolünü zaten yaptın.'), findsNothing);
  });

  testWidgets(
      'başarılı yazım → sonuç rotasına gider, _AlreadyDone hiç görünmez',
      (tester) async {
    final repo = _GatedRepo(InMemoryDecisionRepository());
    addTearDown(repo.dispose);
    final id = await pumpCheckIn(tester, repo: repo);

    await tester.tap(find.text('Memnunum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(lastRoute, '/decision/$id/result');
    expect(find.text('SONUÇ EKRANI'), findsOneWidget);
    expect(find.text('Bu kararın kontrolünü zaten yaptın.'), findsNothing);
    // Kayıt gerçekten yazıldı:
    expect(
      container.read(decisionEditorProvider(id)).requireValue.checkInStatus,
      DecisionCheckIn.happy,
    );
  });

  testWidgets(
      'yazım başarısız → kaydediliyor kalkar, seçenekler döner, snackbar',
      (tester) async {
    final repo = _GatedRepo(InMemoryDecisionRepository());
    addTearDown(repo.dispose);
    final id = await pumpCheckIn(tester, repo: repo);

    repo.failNext = true;
    await tester.tap(find.text('Pişmanım'));
    await tester.pump(); // _saving=true
    await tester.pump(); // applyPatch fırlatır → rollback → _saving=false
    await tester.pump(const Duration(milliseconds: 50));

    // Kaydediliyor kalktı, seçenekler geri geldi:
    expect(find.text('Cevabın kaydediliyor…'), findsNothing);
    expect(find.text('Memnunum'), findsOneWidget);
    expect(find.text('Pişmanım'), findsOneWidget);
    // Hata snackbar'ı:
    expect(find.text('Kaydedilemedi, tekrar dener misin?'), findsOneWidget);
    // Sonuç ekranına GİTMEDİ + kayıt yazılmadı (rollback):
    expect(find.text('SONUÇ EKRANI'), findsNothing);
    expect(
      container.read(decisionEditorProvider(id)).requireValue.hasCheckedIn,
      isFalse,
    );
  });

  // ---- Görsel Dilim 4B — sıcak koç dili ----

  group('Görsel Dilim 4B', () {
    testWidgets('koç paneli + destek metinleri; emoji YOK, ikonlar VAR',
        (tester) async {
      await pumpCheckIn(tester);

      // Koç bölümü + kilitli metinler:
      expect(find.text('Koçundan'), findsOneWidget);
      expect(find.text('Nasıl gidiyor?'), findsOneWidget);
      expect(
        find.textContaining('Samsung kararının üzerinden'),
        findsOneWidget,
      );
      // Kart destek metinleri:
      expect(find.text('Kararımdan memnunum.'), findsOneWidget);
      expect(find.text('Biraz daha zamana ihtiyacım var.'), findsOneWidget);
      expect(find.text('Farklı bir seçim yapmak isterdim.'), findsOneWidget);
      // Emoji tamamen kalktı:
      expect(find.textContaining('😌'), findsNothing);
      expect(find.textContaining('😐'), findsNothing);
      expect(find.textContaining('😣'), findsNothing);
      // Semantik ikonlar:
      expect(find.byIcon(Icons.sentiment_satisfied_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_neutral_outlined), findsOneWidget);
      expect(
        find.byIcon(Icons.sentiment_dissatisfied_outlined),
        findsOneWidget,
      );
      // Güven notu sıcak yüzeyde:
      expect(
        find.textContaining('Cevabın yalnız sana ait'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('kart yüzeyi tam dokunulabilir: destek metnine dokun → enum',
        (tester) async {
      final id = await pumpCheckIn(tester);

      // Label'a değil DESTEK metnine dokun (kartın tamamı dokunulabilir):
      await tester.tap(find.text('Biraz daha zamana ihtiyacım var.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(decisionEditorProvider(id)).requireValue.checkInStatus,
        DecisionCheckIn.neutral,
      );
    });

    testWidgets('her kartın dokunma hedefi ≥48dp', (tester) async {
      await pumpCheckIn(tester);
      for (final label in const ['Memnunum', 'Kararsızım', 'Pişmanım']) {
        final card = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        expect(
          tester.getSize(card).height,
          greaterThanOrEqualTo(48),
          reason: '$label kartı 48dp altında',
        );
      }
    });

    testWidgets('Semantics: button niteliği + anlaşılır label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCheckIn(tester);
      expect(
        find.bySemanticsLabel(RegExp('Memnunum. Kararımdan memnunum.')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Pişmanım. Farklı bir seçim')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('AlreadyDone: AppEmptyHint + Tamam → Home', (tester) async {
      await pumpCheckIn(tester, alreadyAnswered: DecisionCheckIn.happy);

      expect(find.text('Bu kararın kontrolünü zaten yaptın.'), findsOneWidget);
      expect(
        find.text('Bu karar için kontrol yanıtın kaydedildi.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);

      await tester.tap(find.text('Tamam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(lastRoute, '/home');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('not-decided: AppEmptyHint + Tamam → Home', (tester) async {
      await pumpCheckIn(tester, decided: false);

      expect(find.text('Bu karar henüz verilmiş değil.'), findsOneWidget);
      expect(
        find.text('Kontrol yapabilmek için önce kararını vermelisin.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Tamam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(lastRoute, '/home');
    });

    testWidgets('geçersiz ID: ham exception görünmez, güvenli metin + Home CTA',
        (tester) async {
      await pumpCheckIn(tester, useInvalidId: true);
      // Provider error state'e düşene dek sınırlı pump:
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bu karar açılamadı'), findsOneWidget);
      expect(
        find.text('Karar silinmiş veya artık erişilebilir olmayabilir.'),
        findsOneWidget,
      );
      // Ham exception ayrıntısı YOK:
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.textContaining('Yüklenemedi'), findsNothing);
      expect(find.textContaining('bulunamadı'), findsNothing);

      await tester.tap(find.text('Ana sayfaya dön'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(lastRoute, '/home');
    });

    testWidgets('dark render crash yok', (tester) async {
      await pumpCheckIn(tester, theme: AppTheme.dark);
      expect(find.text('Nasıl gidiyor?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320dp + textScale 1.3: taşma yok, kaydırılabilir',
        (tester) async {
      await pumpCheckIn(
        tester,
        size: const Size(320, 700),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
      expect(find.text('Nasıl gidiyor?'), findsOneWidget);
    });
  });
}

/// applyPatch'i test kontrolünde askıya alabilen/başarısız kılabilen sarmalayıcı.
/// Diğer tüm çağrılar iç in-memory depoya iletilir.
class _GatedRepo implements DecisionRepository {
  _GatedRepo(this._inner);

  final InMemoryDecisionRepository _inner;
  Completer<void>? _gate;
  bool failNext = false;

  /// Sonraki applyPatch'i, dönen completer tamamlanana kadar askıya alır.
  Completer<void> gateNextPatch() => _gate = Completer<void>();

  void dispose() => _inner.dispose();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      await gate.future;
    }
    if (failNext) {
      failNext = false;
      throw Exception('yazım başarısız (test)');
    }
    return _inner.applyPatch(id, patch);
  }

  @override
  Stream<List<Decision>> watchAll() => _inner.watchAll();

  @override
  Stream<Decision?> watchById(String id) => _inner.watchById(id);

  @override
  Future<Decision?> getById(String id) => _inner.getById(id);

  @override
  Future<void> upsert(Decision decision) => _inner.upsert(decision);

  @override
  Future<void> delete(String id) => _inner.delete(id);
}
