import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';

/// SPRINT C — taahhüt sonrası SÖZ EKRANI.
/// Kural (A1 dersi): pumpAndSettle YOK, sınırlı pump; testWidgets içinde
/// Future.delayed await EDİLMEZ (FakeAsync deadlock'u).
void main() {
  late ProviderContainer container;
  late InMemoryFollowUpPreferences prefs;
  late RecordingFollowUpScheduler scheduler;

  Future<String> pumpResult(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    prefs = InMemoryFollowUpPreferences();
    scheduler = RecordingFollowUpScheduler();
    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
        followUpPreferencesProvider.overrideWithValue(prefs),
        // Gerçek eklentiye İNİLMEZ — plugin kanalı testte yok.
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
    // Belirgin kazanan (NON-TIE): söz akışı önerilen-önseçili normal commit
    // üzerinden ilerler (eşitlikte önseçim olmaz — o ayrı test dosyasında).
    const scores = [9, 5];
    for (final (i, o) in decision.options.indexed) {
      editor.setScore(o.id, decision.criteria.first.id, scores[i]);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ResultScreen(decisionId: decision.id)),
      ),
    );
    await tester.pump();
    return decision.id;
  }

  Future<void> commitViaSheet(WidgetTester tester) async {
    await tester.tap(find.text('Kararımı Verdim'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Bu kararı veriyorum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('taahhüt sonrası SÖZ ekranı görünür (sheet kapanmaz)',
      (tester) async {
    await pumpResult(tester);
    await commitViaSheet(tester);

    // Mühür + seçim + söz sorusu:
    expect(find.text('Kararın kaydedildi.'), findsOneWidget);
    expect(
      find.text('1 hafta sonra nasıl gittiğini sorayım mı?'),
      findsOneWidget,
    );
    expect(find.text('Evet, sor'), findsOneWidget);
    expect(find.text('Şimdi değil'), findsOneWidget);
    // Seçim fazı kapandı:
    expect(find.text('Hangisini seçtin?'), findsNothing);
  });

  testWidgets('"Evet, sor" → tercih CİHAZDA kaydedilir, sheet kapanır',
      (tester) async {
    final id = await pumpResult(tester);
    await commitViaSheet(tester);

    await tester.tap(find.text('Evet, sor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await prefs.isOptedIn(id), isTrue);
    // SPRINT C.1: söz artık gerçekten planlanıyor — yaklaşık +7 gün.
    final at = scheduler.scheduled[id];
    expect(at, isNotNull);
    expect(
      at!.difference(DateTime.now()).inHours,
      closeTo(const Duration(days: 7).inHours, 1),
    );
    expect(find.text('Kararın kaydedildi.'), findsNothing); // sheet kapandı
    // Karar yine de verilmiş durumda:
    expect(
      container.read(decisionEditorProvider(id)).requireValue.isDecided,
      isTrue,
    );
  });

  testWidgets('"Şimdi değil" → tercih kaydedilmez ama karar VERİLMİŞ kalır',
      (tester) async {
    final id = await pumpResult(tester);
    await commitViaSheet(tester);

    await tester.tap(find.text('Şimdi değil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await prefs.isOptedIn(id), isFalse);
    expect(scheduler.scheduled, isEmpty); // bildirim planlanmadı
    expect(
      container.read(decisionEditorProvider(id)).requireValue.isDecided,
      isTrue,
    );
    expect(find.text('Değiştir'), findsOneWidget); // alt bar decided durumda
  });

  testWidgets('söz verildi → "Değiştir" ile geri al → bildirim İPTAL',
      (tester) async {
    final id = await pumpResult(tester);
    await commitViaSheet(tester);

    await tester.tap(find.text('Evet, sor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(scheduler.scheduled.containsKey(id), isTrue);

    // Kararı geri al:
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
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains(id));
    // Tercih korunur → tekrar karar verilirse yeniden planlanabilir.
    expect(await prefs.isOptedIn(id), isTrue);
  });
}
