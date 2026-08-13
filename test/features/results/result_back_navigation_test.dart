import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/home_screen.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';
import 'package:karar_veriyorum/features/journey/presentation/screens/check_in_screen.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';

/// SPRINT C-4.1 — check-in sonrası ResultScreen geri navigation düzeltmesi.
/// Gerçek Firebase yok; in-memory repo + provider override. Router gerçek.
void main() {
  late ProviderContainer container;
  late String? lastLoc;

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          autosaveDebounceProvider.overrideWithValue(Duration.zero),
          followUpPreferencesProvider
              .overrideWithValue(InMemoryFollowUpPreferences()),
          followUpSchedulerProvider
              .overrideWithValue(RecordingFollowUpScheduler()),
        ],
      );

  /// Puanlaması tam bir karar oluşturur; [commit] ise decided yapar.
  Future<String> seedDecision(
    ProviderContainer c, {
    bool commit = false,
  }) async {
    final result = await c.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Karar',
      initialCriteria: const [(name: 'Fiyat', weight: 8)],
      initialOptions: const ['A', 'B'],
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    final editor = c.read(decisionEditorProvider(decision.id).notifier);
    await c.read(decisionEditorProvider(decision.id).future);
    // autoDispose imha timer'ını engelle: kurulum boyunca izlemeyi canlı tut.
    final sub = c.listen(decisionEditorProvider(decision.id), (_, __) {});
    addTearDown(sub.close);
    for (final o in decision.options) {
      editor.setScore(o.id, decision.criteria.first.id, 7);
    }
    if (commit) await editor.commitDecision(decision.options.last.id);
    return decision.id;
  }

  GoRouter buildRouter(String initialLocation) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, s) {
            lastLoc = s.uri.toString();
            return const Scaffold(body: Text('HOME SCREEN'));
          },
        ),
        GoRoute(
          path: '/decision/:id/check-in',
          builder: (_, s) {
            lastLoc = s.uri.toString();
            return CheckInScreen(decisionId: s.pathParameters['id']!);
          },
        ),
        GoRoute(
          path: '/decision/:id/result',
          builder: (_, s) {
            lastLoc = s.uri.toString();
            return ResultScreen(
              decisionId: s.pathParameters['id']!,
              returnHomeOnBack: s.uri.queryParameters['source'] == 'check-in',
            );
          },
        ),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, s) {
            lastLoc = s.uri.toString();
            return const Scaffold(body: Text('EDIT SCREEN'));
          },
        ),
      ],
    );
  }

  /// Android sistem geri hareketini taklit eder.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('1) check-in başarılı → result URL source=check-in taşır',
      (tester) async {
    // seed için ayrı container gerekiyor; pumpApp kendi container'ını kurar.
    // Bu test seed'i pumpApp container'ında yapmak için elle kuruyoruz:
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = makeContainer();
    addTearDown(container.dispose);
    final id = await seedDecision(container, commit: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: buildRouter('/decision/$id/check-in'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Memnunum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(lastLoc, '/decision/$id/result?source=check-in');
  });

  testWidgets('2) check-in kaynaklı result: görünür geri butonu → /home',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = makeContainer();
    addTearDown(container.dispose);
    final id = await seedDecision(container, commit: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: buildRouter('/decision/$id/result?source=check-in'),
        ),
      ),
    );
    await tester.pump();

    // Görünür geri butonu var:
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(lastLoc, '/home');
    expect(find.text('HOME SCREEN'), findsOneWidget); // uygulama kapanmadı
  });

  testWidgets('3) check-in kaynaklı result: sistem geri → /home, çift nav yok',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = makeContainer();
    addTearDown(container.dispose);
    final id = await seedDecision(container, commit: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: buildRouter('/decision/$id/result?source=check-in'),
        ),
      ),
    );
    await tester.pump();

    await systemBack(tester);

    expect(lastLoc, '/home');
    expect(find.text('HOME SCREEN'), findsOneWidget);
    // Çift navigation olmadığının kanıtı: hâlâ tek Home var, hata yok.
    expect(tester.takeException(), isNull);
  });

  testWidgets('4) cold-start benzeri stack: check-in → result → geri → home',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = makeContainer();
    addTearDown(container.dispose);
    final id = await seedDecision(container, commit: true);

    // Stack altında Home YOK — başlangıç doğrudan check-in.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: buildRouter('/decision/$id/check-in'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Memnunum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(lastLoc, '/decision/$id/result?source=check-in');

    await systemBack(tester);
    expect(lastLoc, '/home');
    expect(find.text('HOME SCREEN'), findsOneWidget);
  });

  testWidgets(
      '6) normal result (source yok): geri önceki rotaya pop, home değil',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = makeContainer();
    addTearDown(container.dispose);
    final id = await seedDecision(container); // decided değil de olur

    // Normal akış: edit → result (push, source YOK).
    final router = buildRouter('/decision/$id/edit');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    // push Future'ı rota pop edilene kadar tamamlanmaz → await ETME.
    unawaited(router.push('/decision/$id/result'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // returnHomeOnBack false → görünür özel geri butonu YOK (otomatik pop olabilir)
    // Sistem geri: önceki rotaya (edit) döner, Home'a zorlanmaz.
    await systemBack(tester);
    expect(find.text('EDIT SCREEN'), findsOneWidget);
    expect(find.text('HOME SCREEN'), findsNothing);
  });

  testWidgets(
      '5) Home kartı → check-in → cevap → result → geri → Home; kart kaybolur',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // +8 gün saat: seed edilen decided karar due olur → koç kartı görünür.
    final now8 = DateTime.now().add(const Duration(days: 8));
    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
        followUpPreferencesProvider
            .overrideWithValue(InMemoryFollowUpPreferences()),
        followUpSchedulerProvider
            .overrideWithValue(RecordingFollowUpScheduler()),
        journeyClockProvider.overrideWithValue(() => now8),
      ],
    );
    addTearDown(container.dispose);
    await seedDecision(container, commit: true);

    // Gerçek HomeScreen kullanan router (canlı decisionListProvider stream'i).
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/decision/:id/check-in',
          builder: (_, s) => CheckInScreen(decisionId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/decision/:id/result',
          builder: (_, s) => ResultScreen(
            decisionId: s.pathParameters['id']!,
            returnHomeOnBack: s.uri.queryParameters['source'] == 'check-in',
          ),
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Koç kartı görünür:
    expect(find.text('Kontrol et'), findsOneWidget);

    // Karta bas → check-in → cevap:
    await tester.tap(find.text('Kontrol et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Memnunum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Result ekranındayız (check-in kaynaklı):
    expect(find.byType(BackButton), findsOneWidget);

    // Geri → Home; yeniden başlatma YOK. Geçiş animasyonunu bitir (aksi halde
    // giden/gelen sayfa bir an birlikte bulunur).
    await systemBack(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Karar Koçum'), findsOneWidget); // Home (marka satırı)
    // Cevaplanmış kararın koç kartı artık görünmüyor:
    expect(find.text('Kontrol et'), findsNothing);
    expect(find.text('Bir kararını kontrol edelim'), findsNothing);
  });
}
