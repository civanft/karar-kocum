import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
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
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    scheduler = RecordingFollowUpScheduler();
    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
        followUpPreferencesProvider
            .overrideWithValue(InMemoryFollowUpPreferences()),
        followUpSchedulerProvider.overrideWithValue(scheduler),
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

    lastRoute = '/decision/${decision.id}/check-in';
    final router = GoRouter(
      initialLocation: lastRoute,
      routes: [
        GoRoute(
          path: '/decision/:id/check-in',
          builder: (_, s) =>
              CheckInScreen(decisionId: s.pathParameters['id']!),
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
        child: MaterialApp.router(routerConfig: router),
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
}
