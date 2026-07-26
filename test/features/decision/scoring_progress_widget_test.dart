import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/decision_edit_screen.dart';

/// PR-A3 widget testleri (SPRINT-A §4.3) — pumpAndSettle YOK (A1 dersi):
/// tüm beklemeler sınırlı pump. Slider'a jest simülasyonu yerine notifier
/// üzerinden setScore (kırılgan tap-koordinatı varsayımından kaçınma).
void main() {
  late ProviderContainer container;

  Future<String> pumpEditScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Puanlama ilerlemesi',
      initialCriteria: const [(name: 'K1', weight: 5), (name: 'K2', weight: 5)],
      initialOptions: const ['A', 'B'],
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    await container.read(decisionEditorProvider(decision.id).future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DecisionEditScreen(decisionId: decision.id),
        ),
      ),
    );
    await tester.pump();
    return decision.id;
  }

  Future<void> openScoresTab(WidgetTester tester) async {
    await tester.tap(find.text('Puanlar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sekme geçişi
  }

  testWidgets('başlık 0/4 ile başlar; setScore sonrası 1/4 ve rozet güncel',
      (tester) async {
    final id = await pumpEditScreen(tester);
    await openScoresTab(tester);

    expect(find.text('Puanlama: 0/4 tamamlandı (%0)'), findsOneWidget);

    final d = container.read(decisionEditorProvider(id)).requireValue;
    container
        .read(decisionEditorProvider(id).notifier)
        .setScore(d.options[0].id, d.criteria[0].id, 7);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Puanlama: 1/4 tamamlandı (%25)'), findsOneWidget);
    // A seçeneği rozeti 1/2, B hâlâ 0/2:
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
  });

  testWidgets(
      'P3 uçtan uca: eksik hücre mesajı niceliksel; matris dolunca '
      '"Sonucu Gör" aktifleşir ve tamam durumu görünür', (tester) async {
    final id = await pumpEditScreen(tester);
    await openScoresTab(tester);

    // Alt bar niceliksel engel mesajı:
    expect(find.text('Puanlama: 0/4 — 4 hücre kaldı'), findsOneWidget);

    // "Sonucu Gör" pasif:
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sonucu Gör'),
    );
    expect(button.onPressed, isNull);

    // Matrisi doldur (notifier üzerinden):
    final d = container.read(decisionEditorProvider(id)).requireValue;
    final editor = container.read(decisionEditorProvider(id).notifier);
    for (final o in d.options) {
      for (final c in d.criteria) {
        editor.setScore(o.id, c.id, 6);
      }
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tamam durumu + aktif buton:
    expect(find.text('Puanlama tamam 4/4'), findsOneWidget);
    expect(find.text('Puanlama: 0/4 — 4 hücre kaldı'), findsNothing);
    final activeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Sonucu Gör'),
    );
    expect(activeButton.onPressed, isNotNull);
  });

  testWidgets('Puanlar sekme rozeti kalan sayısını gösterir ve dolunca düşer',
      (tester) async {
    final id = await pumpEditScreen(tester);

    // Sekme etiketinde kalan rozeti (4):
    expect(find.text('4'), findsOneWidget);

    final d = container.read(decisionEditorProvider(id)).requireValue;
    final editor = container.read(decisionEditorProvider(id).notifier);
    for (final o in d.options) {
      for (final c in d.criteria) {
        editor.setScore(o.id, c.id, 6);
      }
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('4'), findsNothing); // rozet düştü
  });
}
