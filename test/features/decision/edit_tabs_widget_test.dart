import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
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
          theme: AppTheme.light,
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

  // ---- Görsel Dilim 2A ----

  /// Router'lı harness — Sonucu Gör navigasyonu için /result stub'ı.
  Future<String> pumpEditRouter(
    WidgetTester tester, {
    required List<String> options,
    bool withScores = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [autosaveDebounceProvider.overrideWithValue(Duration.zero)],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Sekme testleri',
      initialCriteria: const [(name: 'Fiyat', weight: 8)],
      initialOptions: options,
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    final editor = container.read(decisionEditorProvider(decision.id).notifier);
    await container.read(decisionEditorProvider(decision.id).future);
    if (withScores) {
      for (final o in decision.options) {
        editor.setScore(o.id, decision.criteria.first.id, 7);
      }
    }
    final sub =
        container.listen(decisionEditorProvider(decision.id), (_, __) {});
    addTearDown(sub.close);

    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, __) => DecisionEditScreen(decisionId: decision.id),
        ),
        GoRoute(
          path: '/decision/:id/result',
          builder: (_, __) => const Scaffold(body: Text('RESULT ROUTE')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    return decision.id;
  }

  group('Görsel Dilim 2A', () {
    testWidgets('boş seçenek: AppEmptyHint + TEK ekleme CTA', (tester) async {
      await pumpEditRouter(tester, options: const []);
      // Boş durum rehberi + tek CTA:
      expect(find.text('İlk seçeneğini ekle'), findsOneWidget);
      expect(find.text('Seçenek ekle'), findsOneWidget); // yalnız 1 tane
      // Tekrarlayan ikinci ekleme butonu YOK:
      expect(find.textContaining('Seçenek ekle ('), findsNothing);
    });

    testWidgets('boş durum CTA ekleme diyaloğunu açar', (tester) async {
      await pumpEditRouter(tester, options: const []);
      await tester.tap(find.text('Seçenek ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Yeni Seçenek'), findsOneWidget); // AlertDialog
    });

    testWidgets('seçenek kartı: hem silme hem genişleme affordance',
        (tester) async {
      await pumpEditRouter(tester, options: const ['A', 'B']);
      // Silme ikonu (title satırında):
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      // Genişleme: karta dokun → Artılar/Eksiler görünür:
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Artılar'), findsOneWidget);
      expect(find.text('Eksiler'), findsOneWidget);
    });

    testWidgets('silme ikonu kapalı VE genişletilmiş durumda nötr kalır',
        (tester) async {
      await pumpEditRouter(tester, options: const ['A', 'B']);
      final neutral = AppTheme.light.colorScheme.onSurfaceVariant;

      IconButton firstDelete() => tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline).first,
          );

      // Kapalı: nötr.
      expect(firstDelete().color, neutral);

      // A kartını genişlet:
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Artılar'), findsOneWidget);

      // Genişletilmiş: hâlâ nötr (primary'e dönmedi).
      expect(firstDelete().color, neutral);
    });

    testWidgets('favori toggle: yıldız dolar', (tester) async {
      final id = await pumpEditRouter(tester, options: const ['A', 'B']);
      expect(
        container.read(decisionEditorProvider(id)).requireValue.isFavorite,
        isFalse,
      );
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pump();
      expect(
        container.read(decisionEditorProvider(id)).requireValue.isFavorite,
        isTrue,
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('eksik puanlama: blocker mesajı + Sonucu Gör DISABLED',
        (tester) async {
      await pumpEditRouter(tester, options: const ['A', 'B']); // skor yok
      expect(find.textContaining('Puanlama:'), findsOneWidget);
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sonucu Gör'),
      );
      expect(btn.onPressed, isNull); // disabled
    });

    testWidgets('tamamlanınca Sonucu Gör ENABLED → /result', (tester) async {
      await pumpEditRouter(tester, options: const ['A', 'B'], withScores: true);
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sonucu Gör'),
      );
      expect(btn.onPressed, isNotNull); // enabled
      await tester.tap(find.text('Sonucu Gör'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('RESULT ROUTE'), findsOneWidget);
    });

    testWidgets('üç sekme korunur', (tester) async {
      await pumpEditRouter(tester, options: const ['A', 'B']);
      expect(find.text('Seçenekler'), findsOneWidget);
      expect(find.text('Kriterler'), findsOneWidget);
      expect(find.text('Puanlar'), findsOneWidget);
    });
  });
}
