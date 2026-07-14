import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/decision_edit_screen.dart';

/// Seçenekler/Kriterler sekmelerinin temel akış testleri (A3 kapsam
/// genişlemesiyle enstrümantasyona giren gövdeler). Kural: pumpAndSettle
/// YOK — sınırlı pump; diyalog kapanışları navigasyonla bittiği için
/// güvenli (A1'deki açık-sheet tuzağı burada yok).
void main() {
  late ProviderContainer container;

  Future<String> pumpEdit(WidgetTester tester) async {
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
      title: 'Sekme testleri',
      initialCriteria: const [(name: 'Fiyat', weight: 8)],
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

  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    // Sekme animasyonu 300ms + IgnorePointer'ın kalkması için pay:
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Seçenekler sekmesi', () {
    testWidgets('kartlar render olur; silme seçeneği düşürür', (tester) async {
      final id = await pumpEdit(tester);

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);

      await tester.tap(find.byTooltip('Seçeneği sil').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.options, hasLength(1));
    });

    testWidgets('ekleme diyaloğu: başlık girilir, seçenek listeye eklenir',
        (tester) async {
      final id = await pumpEdit(tester);

      await tester.tap(find.textContaining('Seçenek ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField).last, 'C seçeneği');
      await tester.pump();
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.options.map((o) => o.title), contains('C seçeneği'));
    });
  });

  group('Kriterler sekmesi', () {
    testWidgets('kart + ağırlık render; silme kriteri düşürür', (tester) async {
      final id = await pumpEdit(tester);
      await goTab(tester, 'Kriterler');

      expect(find.text('Fiyat'), findsOneWidget);
      expect(find.textContaining('Önem: 8/10'), findsOneWidget);

      await tester.tap(find.byTooltip('Kriteri sil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.criteria, isEmpty);
    });

    testWidgets('ekleme diyaloğu: ad girilir, kriter eklenir', (tester) async {
      final id = await pumpEdit(tester);
      await goTab(tester, 'Kriterler');

      await tester.tap(find.text('Kriter ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField).last, 'Konfor');
      await tester.pump();
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.criteria.map((c) => c.name), contains('Konfor'));
    });

    testWidgets('ağırlık slider sürüklemesi ağırlığı değiştirir',
        (tester) async {
      final id = await pumpEdit(tester);
      await goTab(tester, 'Kriterler');

      // Drag, TabBarView yatay swipe'ıyla yarışıyor — divisions'lı
      // slider'da sağ uca TAP değeri doğrudan zıplatır (onChanged+End).
      final slider = find.byType(Slider).first;
      final right = tester.getTopRight(slider);
      await tester.tapAt(Offset(right.dx - 24, right.dy + 24));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.criteria.single.weight, greaterThan(8));
    });
  });
}
