import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/widgets/criterion_suggestion_strip.dart';

/// Chip şeridi widget testleri (SPRINT-A §4.3). Modal/sheet YOK — düz
/// widget; yine de A1 dersi gereği settle yerine sınırlı pump kullanılır.
void main() {
  late ProviderContainer container;

  Future<String> makeDecision(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        // Mevcut editor-test kalıbı: debounce sıfır — bekleyen yazım
        // zamanlayıcısı testin sonunda 'pending timers' üretmesin.
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'iPhone mu Samsung mu?',
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    await container.read(decisionEditorProvider(decision.id).future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CriterionSuggestionStrip(decisionId: decision.id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return decision.id;
  }

  testWidgets('chip dokunuşu kriteri ekler ve chip listeden düşer',
      (tester) async {
    final id = await makeDecision(tester);

    expect(find.text('Fiyat'), findsOneWidget);

    await tester.tap(find.text('Fiyat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 50));

    // Chip düştü (öneri artık "mevcut"):
    expect(find.text('Fiyat'), findsNothing);
    // Kriter gerçekten eklendi, aiSuggested kaynaklı, ağırlık 5:
    final decision = container.read(decisionEditorProvider(id)).requireValue;
    final added = decision.criteria.single;
    expect(added.name, 'Fiyat');
    expect(added.weight, CriterionSuggestionStrip.defaultWeight);
    expect(added.source.name, 'aiSuggested');
  });

  testWidgets('✕ şeridi gizler', (tester) async {
    await makeDecision(tester);
    expect(find.text('Önerilen kriterler'), findsOneWidget);

    await tester.tap(find.byTooltip('Önerileri gizle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // zero-timer flush

    expect(find.text('Önerilen kriterler'), findsNothing);
  });

  testWidgets('6 kriterli kararda şerit render edilmez', (tester) async {
    final id = await makeDecision(tester);
    final editor = container.read(decisionEditorProvider(id).notifier);
    for (final name in ['K1', 'K2', 'K3', 'K4', 'K5', 'K6']) {
      await editor.addCriterion(name, 5);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Önerilen kriterler'), findsNothing);
  });
}
