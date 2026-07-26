import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/decision_edit_screen.dart';
import 'package:karar_veriyorum/features/decision/presentation/widgets/criteria_tab.dart';
import 'package:karar_veriyorum/features/decision/presentation/widgets/scores_tab.dart';

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
      expect(find.text('8/10'), findsOneWidget); // ağırlık rozeti

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

  // ---- Görsel Dilim 2B (Kriterler + Puanlar) ----

  /// Esnek harness — kriter/seçenek sayısı, ekran boyutu, ölçek ve tema
  /// parametrik. AppTheme uygulanır (AppSemanticColors uzantısı için).
  Future<String> pumpEditCustom(
    WidgetTester tester, {
    required List<({String name, int weight})> criteria,
    required List<String> options,
    Size size = const Size(1000, 2000),
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [autosaveDebounceProvider.overrideWithValue(Duration.zero)],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Sekme testleri',
      initialCriteria: criteria,
      initialOptions: options,
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    await container.read(decisionEditorProvider(decision.id).future);
    final sub =
        container.listen(decisionEditorProvider(decision.id), (_, __) {});
    addTearDown(sub.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: DecisionEditScreen(decisionId: decision.id),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
    return decision.id;
  }

  /// Sekme içeriğini TEK BAŞINA pompalar (kabuk TabBar'ı hariç) — içerik
  /// taşma dayanıklılığını, ilgisiz kabuk TabBar taşmasından yalıtarak
  /// ölçmek için. DefaultTabController boş-durum CTA gezinmesi için var.
  Future<void> pumpSingleTab(
    WidgetTester tester, {
    required Widget Function(String id) builder,
    required List<({String name, int weight})> criteria,
    required List<String> options,
    Size size = const Size(320, 800),
    double textScale = 1.3,
    bool withScores = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [autosaveDebounceProvider.overrideWithValue(Duration.zero)],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: 'Sekme testleri',
      initialCriteria: criteria,
      initialOptions: options,
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    // Önce dinle: autoDispose timer'ı (mayNeedDispose) zamanlanmasın.
    final sub =
        container.listen(decisionEditorProvider(decision.id), (_, __) {});
    addTearDown(sub.close);
    await container.read(decisionEditorProvider(decision.id).future);
    if (withScores) {
      final d =
          container.read(decisionEditorProvider(decision.id)).requireValue;
      final editor =
          container.read(decisionEditorProvider(decision.id).notifier);
      for (final o in d.options) {
        for (final c in d.criteria) {
          editor.setScore(o.id, c.id, 6);
        }
      }
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: DefaultTabController(
            length: 3,
            child: Scaffold(body: builder(decision.id)),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('Görsel Dilim 2B — Kriterler', () {
    testWidgets('boş: AppEmptyHint + tek CTA', (tester) async {
      await pumpEditCustom(tester, criteria: const [], options: const ['A']);
      await goTab(tester, 'Kriterler');
      expect(find.text('İlk kriterini ekle'), findsOneWidget);
      expect(find.text('Kriter ekle'), findsOneWidget);
      expect(find.text('Kriterlerin'), findsOneWidget); // rehber başlığı
      // Rehber ile tekrar etmeyen sadeleştirilmiş boş-durum mesajı:
      expect(
        find.text('Her kriterin etkisini 1–10 arasında ayarlayabilirsin.'),
        findsOneWidget,
      );
    });

    testWidgets('boş durum CTA ekleme diyaloğunu açar', (tester) async {
      await pumpEditCustom(tester, criteria: const [], options: const ['A']);
      await goTab(tester, 'Kriterler');
      await tester.tap(find.text('Kriter ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Yeni Kriter'), findsOneWidget);
    });

    testWidgets('kriter kartı: ağırlık rozeti "N/10" + nötr silme',
        (tester) async {
      await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A', 'B'],
      );
      await goTab(tester, 'Kriterler');
      expect(find.text('8/10'), findsOneWidget);

      final neutral = AppTheme.light.colorScheme.onSurfaceVariant;
      final delete = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline).first,
      );
      expect(delete.color, neutral);
    });

    testWidgets('ağırlık slider sürüklemesi ağırlığı değiştirir',
        (tester) async {
      final id = await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A', 'B'],
      );
      await goTab(tester, 'Kriterler');
      final slider = find.byType(Slider).first;
      final right = tester.getTopRight(slider);
      await tester.tapAt(Offset(right.dx - 24, right.dy + 24));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.criteria.single.weight, greaterThan(8));
    });

    testWidgets('içerik dar ekran (320) + textScale 1.3 + uzun ad: taşma yok',
        (tester) async {
      await pumpSingleTab(
        tester,
        builder: (id) => CriteriaTab(decisionId: id),
        criteria: const [
          (name: 'Uzun soluklu bir kriter adı taşma testi için', weight: 6),
        ],
        options: const ['A', 'B'],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark render crash yok', (tester) async {
      await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A', 'B'],
        theme: AppTheme.dark,
      );
      await goTab(tester, 'Kriterler');
      expect(find.text('Fiyat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Görsel Dilim 2B — Puanlar', () {
    testWidgets(
        'ön koşul (seçenek eksik): "Seçeneklere git" → Seçenekler sekmesi',
        (tester) async {
      await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A'], // < 2 seçenek
      );
      await goTab(tester, 'Puanlar');
      expect(find.text('Puanlamaya hazırlan'), findsOneWidget);
      // Yönlendirme CTA'sı: metin + ok ikonu (add değil):
      expect(find.text('Seçeneklere git'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

      await tester.tap(find.text('Seçeneklere git'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Seçenekler sekmesine geçti + gerçek ekleme butonu görünür:
      expect(find.text('Seçeneklerin'), findsOneWidget);
      expect(find.textContaining('Seçenek ekle'), findsOneWidget);
    });

    testWidgets('ön koşul (kriter eksik): "Kriterlere git" → Kriterler sekmesi',
        (tester) async {
      await pumpEditCustom(
        tester,
        criteria: const [],
        options: const ['A', 'B'], // 2 seçenek var, kriter yok
      );
      await goTab(tester, 'Puanlar');
      expect(find.text('Puanlamaya hazırlan'), findsOneWidget);
      expect(find.text('Kriterlere git'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

      await tester.tap(find.text('Kriterlere git'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Kriterler sekmesine geçti + gerçek ekleme akışı görünür:
      expect(find.text('Kriterlerin'), findsOneWidget);
      expect(find.text('Kriter ekle'), findsOneWidget);
    });

    testWidgets(
        'varsayılan 5 ama hücre "—"; setScore değer + ilerleme günceller',
        (tester) async {
      final id = await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A', 'B'],
      );
      await goTab(tester, 'Puanlar');

      // Başlangıç: 0/2, iki dolmamış hücre "—":
      expect(find.text('Puanlama: 0/2 tamamlandı (%0)'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      container
          .read(decisionEditorProvider(id).notifier)
          .setScore(d.options[0].id, d.criteria[0].id, 7);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Puanlama: 1/2 tamamlandı (%50)'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // dolan hücre değeri
      expect(find.text('—'), findsOneWidget); // kalan tek dolmamış hücre
    });

    testWidgets('tamamlanınca "Puanlama tamam" + badge tam', (tester) async {
      final id = await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A', 'B'],
      );
      await goTab(tester, 'Puanlar');
      final d = container.read(decisionEditorProvider(id)).requireValue;
      final editor = container.read(decisionEditorProvider(id).notifier);
      for (final o in d.options) {
        editor.setScore(o.id, d.criteria[0].id, 6);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Puanlama tamam 2/2'), findsOneWidget);
      expect(find.text('1/1'), findsNWidgets(2)); // her kart tam
    });

    testWidgets(
        'içerik dar ekran (320) + textScale 1.3 + uzun adlar: taşma yok',
        (tester) async {
      await pumpSingleTab(
        tester,
        builder: (id) => ScoresTab(decisionId: id),
        criteria: const [
          (name: 'Uzun bir kriter adı puanlama taşma testi', weight: 6),
        ],
        options: const [
          'Çok uzun bir seçenek adı taşma testi için',
          'İkinci seçenek',
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark render crash yok', (tester) async {
      await pumpEditCustom(
        tester,
        criteria: const [(name: 'Fiyat', weight: 8)],
        options: const ['A', 'B'],
        theme: AppTheme.dark,
      );
      await goTab(tester, 'Puanlar');
      expect(find.text('A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
