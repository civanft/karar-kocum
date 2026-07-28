import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_palette.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';

/// Görsel Dilim 4A — commit sheet + PromiseView sunum/erişilebilirlik.
/// Davranış sözleşmeleri (tie önseçim, failure, follow-up) commit_result_test,
/// result_tie_test, promise_screen_test'te; burada YENİ görsel/a11y doğrusu.
void main() {
  late ProviderContainer container;

  Future<String> pump(
    WidgetTester tester, {
    required List<String> options,
    required List<int> scores,
    bool commit = false,
    bool openSheet = true,
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(1000, 2000),
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
      title: 'Karar',
      initialCriteria: const [(name: 'Bütçe', weight: 6)],
      initialOptions: options,
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    final sub =
        container.listen(decisionEditorProvider(decision.id), (_, __) {});
    addTearDown(sub.close);
    final editor = container.read(decisionEditorProvider(decision.id).notifier);
    await container.read(decisionEditorProvider(decision.id).future);
    final crit = decision.criteria.first.id;
    for (final (i, o) in decision.options.indexed) {
      editor.setScore(o.id, crit, scores[i]);
    }
    await editor.flushPendingWrites();
    if (commit) await editor.commitDecision(decision.options.last.id);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ResultScreen(decisionId: decision.id),
        ),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, __) => const Scaffold(body: Text('EDIT')),
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
    if (openSheet) {
      await tester.tap(find.text(commit ? 'Değiştir' : 'Kararımı Verdim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
    return decision.id;
  }

  // Sheet arkasındaki ana gövde (rank tile) ile çakışmayı önlemek için
  // bulguları modal sheet alt ağacına kısıtla.
  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(BottomSheet), matching: f);

  group('commit sheet — görsel', () {
    testWidgets('non-tie: başlık bloğu + destek + "Önerilen" rozeti (ikon)',
        (tester) async {
      await pump(
        tester,
        options: const ['iPhone', 'Samsung'],
        scores: const [9, 5],
      );
      expect(find.text('Son adım'), findsOneWidget);
      expect(find.text('Hangisini seçtin?'), findsOneWidget);
      expect(
        find.text('Öneriyi değiştirebilirsin; son karar sana ait.'),
        findsOneWidget,
      );
      // Rozet: ikon + metin, emoji yıldız YOK (sheet içinde):
      expect(inSheet(find.text('Önerilen')), findsOneWidget);
      expect(inSheet(find.byIcon(Icons.star_outline_rounded)), findsOneWidget);
      expect(find.textContaining('⭐'), findsNothing);
    });

    testWidgets('tie: başa baş destek metni + "Önerilen" yok + CTA pasif',
        (tester) async {
      await pump(tester, options: const ['A', 'B'], scores: const [7, 7]);
      expect(
        find.text('Seçenekler başa baş. Son seçimi kendi önceliklerine '
            'göre yap.'),
        findsOneWidget,
      );
      expect(find.text('Önerilen'), findsNothing);
      final cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Bu kararı veriyorum'),
      );
      expect(cta.onPressed, isNull);
    });

    testWidgets(
        'tie + 2 kısa seçenek, 390x844, textScale 1.0: iki kart ilk açılışta '
        'tam görünür, CTA üstünde, taşma yok', (tester) async {
      await pump(
        tester,
        options: const ['Deniz tatili', 'Dağ tatili'],
        scores: const [7, 7],
        size: const Size(390, 844),
      );
      // Regresyon: modal varsayılan yükseklik sınırı ikinci kartı kırpıyordu.
      expect(tester.takeException(), isNull);
      // İki radyo (seçili değil) da sheet içinde render olur:
      expect(
        inSheet(find.byIcon(Icons.radio_button_unchecked)),
        findsNWidgets(2),
      );

      final ctaTop = tester
          .getRect(find.widgetWithText(FilledButton, 'Bu kararı veriyorum'))
          .top;
      for (final title in const ['Deniz tatili', 'Dağ tatili']) {
        final card = find
            .ancestor(
              of: inSheet(find.text(title)),
              matching: find.byType(InkWell),
            )
            .first;
        final rect = tester.getRect(card);
        // Kartın alt sınırı CTA'nın üstünde ve viewport içinde → tam görünür.
        expect(rect.bottom, lessThanOrEqualTo(ctaTop));
        expect(rect.bottom, lessThanOrEqualTo(844));
        expect(rect.top, greaterThanOrEqualTo(0));
      }

      // CTA seçim yapılmadan pasif:
      final cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Bu kararı veriyorum'),
      );
      expect(cta.onPressed, isNull);
    });

    testWidgets('tam kart dokunulabilir: başlığa dokununca seçim değişir',
        (tester) async {
      final id = await pump(
        tester,
        options: const ['iPhone', 'Samsung'],
        scores: const [9, 5], // iPhone önseçili
      );
      // Samsung başlığına (radio dışı alan) dokun → seçim değişir:
      await tester.tap(find.text('Samsung').last);
      await tester.pump();
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(
        d.options.firstWhere((o) => o.id == d.chosenOptionId).title,
        'Samsung',
      );
    });

    testWidgets('seçenek kartı dokunma alanı ≥ 48dp', (tester) async {
      await pump(
        tester,
        options: const ['iPhone', 'Samsung'],
        scores: const [9, 5],
      );
      final card = find
          .ancestor(
            of: inSheet(find.text('iPhone')),
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
    });

    testWidgets('decided: "Kararı geri al" görünür', (tester) async {
      await pump(
        tester,
        options: const ['iPhone', 'Samsung'],
        scores: const [9, 5],
        commit: true,
      );
      expect(find.text('Kararı geri al'), findsOneWidget);
    });

    testWidgets('10 seçenek + textScale 1.3: liste kaydırılabilir, taşma yok',
        (tester) async {
      await pump(
        tester,
        options: const [
          'Çok uzun bir seçenek adı taşma kontrolü için bir',
          'Seçenek iki uzun ad',
          'Seçenek üç',
          'Seçenek dört',
          'Seçenek beş',
          'Seçenek altı',
          'Seçenek yedi',
          'Seçenek sekiz',
          'Seçenek dokuz',
          'Seçenek on',
        ],
        scores: const [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
        size: const Size(360, 800),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
      expect(find.text('Hangisini seçtin?'), findsOneWidget);
    });

    testWidgets('dark render crash yok', (tester) async {
      await pump(
        tester,
        options: const ['iPhone', 'Samsung'],
        scores: const [9, 5],
        theme: AppTheme.dark,
      );
      expect(find.text('Hangisini seçtin?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PromiseView — görsel', () {
    Future<void> reachPromise(WidgetTester tester, {ThemeData? theme}) async {
      await pump(
        tester,
        options: const ['iPhone', 'Samsung'],
        scores: const [9, 5],
        theme: theme,
      );
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('mühür: success check + destek + aksiyonlar', (tester) async {
      await reachPromise(tester);
      expect(find.text('Kararın kaydedildi.'), findsOneWidget);
      // Rank tile "Seçildi" de check_circle_outline kullanır → sheet'e kısıtla.
      expect(inSheet(find.byIcon(Icons.check_circle_outline)), findsOneWidget);
      expect(
        find.text('1 hafta sonra nasıl gittiğini sorayım mı?'),
        findsOneWidget,
      );
      expect(
        find.text('İstersen kararını birlikte takip ederiz.'),
        findsOneWidget,
      );
      expect(find.text('Evet, sor'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.text('Şimdi değil'), findsOneWidget);
    });

    testWidgets('success ikonu semantic.success rengini kullanır',
        (tester) async {
      await reachPromise(tester);
      final icon = tester.widget<Icon>(
        inSheet(find.byIcon(Icons.check_circle_outline)),
      );
      expect(icon.color, AppSemanticColors.light.success);
    });

    testWidgets('dark render crash yok', (tester) async {
      await reachPromise(tester, theme: AppTheme.dark);
      expect(find.text('Kararın kaydedildi.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
