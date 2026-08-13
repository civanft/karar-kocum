import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_coordinator.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';
import 'package:karar_veriyorum/features/results/presentation/screens/result_screen.dart';
import 'package:karar_veriyorum/features/results/presentation/widgets/result_winner_panel.dart';

/// Result eşitlik (tie) deneyimi — yalnız sunum. scoring/domain değişmez.
/// Kural: pumpAndSettle YOK — sınırlı pump.
void main() {
  late ProviderContainer container;

  Future<String> pumpTie(
    WidgetTester tester, {
    required List<String> options,
    required List<int> scores, // seçenek başına (tek kriter)
    bool commitLast = false,
    DecisionRepository? repo,
    FollowUpCoordinator? coordinator,
    String title = 'Hangi tatil planı?',
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(1000, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    container = ProviderContainer(
      overrides: [
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
        if (repo != null) decisionRepositoryProvider.overrideWithValue(repo),
        if (coordinator != null)
          followUpCoordinatorProvider.overrideWithValue(coordinator),
      ],
    );
    addTearDown(container.dispose);
    final result = await container.read(createDecisionProvider)(
      ownerUid: 'u1',
      title: title,
      initialCriteria: const [(name: 'Bütçe', weight: 6)],
      initialOptions: options,
    );
    final decision =
        result.when(ok: (d) => d, err: (_) => fail('karar oluşmadı'));
    // Önce dinle: autoDispose timer'ı zamanlanmasın.
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
    if (commitLast) await editor.commitDecision(decision.options.last.id);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => ResultScreen(decisionId: decision.id),
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
    return decision.id;
  }

  group('tie — panel & sıralama', () {
    testWidgets('1) iki eşit: başa baş paneli, kazanan yok, iki rank 1',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTie(
        tester,
        options: const ['Deniz tatili', 'Dağ tatili'],
        scores: const [7, 7],
      );
      // Tarafsız panel:
      expect(find.text('Başa baş sonuç'), findsOneWidget);
      expect(find.text('Karar sende'), findsOneWidget);
      expect(find.text('Eşit puan'), findsWidgets); // panel + tile'lar
      // Hiçbir "Önerilen" yok:
      expect(find.text('Önerilen'), findsNothing);
      // İki seçenek de rank 1:
      expect(find.text('1'), findsNWidgets(2));
      // İki tile da eşit lider semantiği taşır:
      expect(find.bySemanticsLabel(RegExp('eşit lider')), findsNWidgets(2));
      handle.dispose();
    });

    testWidgets('2) üç seçenek, ilk ikisi eşit: rank 1,1,3', (tester) async {
      await pumpTie(
        tester,
        options: const ['A', 'B', 'C'],
        scores: const [8, 8, 4], // A=B > C
      );
      expect(find.text('1'), findsNWidgets(2)); // A, B eşit lider
      expect(find.text('3'), findsOneWidget); // C competition ranking
      expect(find.text('2'), findsNothing);
      // C tied leader değil:
      expect(find.text('Eşit puan'), findsNWidgets(3)); // panel + A + B
    });

    testWidgets('3) non-tie: kazanan paneli + tek "Önerilen" + rank 1,2',
        (tester) async {
      await pumpTie(
        tester,
        options: const ['A', 'B'],
        scores: const [9, 4], // belirgin kazanan
      );
      expect(find.text('Öne çıkan seçenek'), findsOneWidget);
      expect(find.text('Karar sende'), findsNothing);
      expect(find.text('Önerilen'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byType(ResultWinnerPanel), findsOneWidget);
    });
  });

  group('tie — commit sheet', () {
    testWidgets(
        '4) open+tie: önseçim yok, "önerilen ⭐" yok, buton pasif → seçince '
        'aktif → commit → PromiseView', (tester) async {
      final id = await pumpTie(
        tester,
        options: const ['Deniz tatili', 'Dağ tatili'],
        scores: const [7, 7],
      );

      await tester.tap(find.text('Kararımı Verdim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Başlangıçta seçili radio yok, "önerilen ⭐" yok:
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
      expect(find.textContaining('önerilen'), findsNothing);

      // Commit butonu pasif:
      FilledButton commitBtn() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Bu kararı veriyorum'),
          );
      expect(commitBtn().onPressed, isNull);

      // Bir seçenek seç → buton aktifleşir:
      await tester.tap(find.text('Dağ tatili').last);
      await tester.pump();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(commitBtn().onPressed, isNotNull);

      // Commit → decided (seçilen id) + PromiseView:
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final d = container.read(decisionEditorProvider(id)).requireValue;
      expect(d.isDecided, isTrue);
      expect(
        d.options.firstWhere((o) => o.id == d.chosenOptionId).title,
        'Dağ tatili',
      );
      expect(find.text('Kararın kaydedildi.'), findsOneWidget);
    });

    testWidgets('5) decided+tie: chosen seçili + "Seçildi"; "Önerilen" yok',
        (tester) async {
      await pumpTie(
        tester,
        options: const ['Deniz tatili', 'Dağ tatili'],
        scores: const [7, 7],
        commitLast: true, // Dağ tatili seçildi
      );
      // Sıralamada seçilen "Seçildi" etiketi taşır, "Önerilen" yok:
      expect(find.text('Seçildi'), findsOneWidget);
      expect(find.text('Önerilen'), findsNothing);
      // Alt bar decided:
      expect(find.textContaining('seçildi'), findsOneWidget);
      expect(find.text('Değiştir'), findsOneWidget);
      // Panel hâlâ tarafsız:
      expect(find.text('Karar sende'), findsOneWidget);
    });

    testWidgets(
        '6) tie + commit failure: rollback + Snackbar + retry; follow-up yok',
        (tester) async {
      final repo = _ControllableRepository();
      final coordinator = _SpyFollowUpCoordinator();
      final id = await pumpTie(
        tester,
        options: const ['Deniz tatili', 'Dağ tatili'],
        scores: const [7, 7],
        repo: repo,
        coordinator: coordinator,
      );

      await tester.tap(find.text('Kararımı Verdim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Dağ tatili').last);
      await tester.pump();

      repo.failApplyPatch = true;
      await tester.tap(find.text('Bu kararı veriyorum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(decisionEditorProvider(id)).requireValue.isDecided,
        isFalse,
      );
      expect(find.text('Kararın kaydedildi.'), findsNothing);
      expect(find.text('Kaydedilemedi — tekrar dene.'), findsOneWidget);
      expect(find.text('Bu kararı veriyorum'), findsOneWidget); // retry
      expect(coordinator.committed, 0);
    });
  });

  testWidgets('7) tie dar ekran (320) + textScale 1.3 taşma yok',
      (tester) async {
    await pumpTie(
      tester,
      title: 'Uzun bir karar başlığı eşitlik taşma kontrolü için yazıldı',
      options: const [
        'Çok uzun bir seçenek adı eşitlik taşma kontrolü',
        'İkinci uzun seçenek adı',
      ],
      scores: const [7, 7],
      size: const Size(320, 900),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Karar sende'), findsOneWidget);
  });
}

/// applyPatch'i istenildiğinde başarısızlaştıran in-memory repo.
class _ControllableRepository extends InMemoryDecisionRepository {
  bool failApplyPatch = false;

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) {
    if (failApplyPatch) {
      throw Exception('simülasyon: applyPatch başarısız');
    }
    return super.applyPatch(id, patch);
  }
}

/// onCommitted/onReverted çağrı sayısını sayan casus.
class _SpyFollowUpCoordinator extends FollowUpCoordinator {
  _SpyFollowUpCoordinator()
      : super(
          preferences: InMemoryFollowUpPreferences(),
          scheduler: RecordingFollowUpScheduler(),
        );

  int committed = 0;
  int reverted = 0;

  @override
  Future<void> onCommitted({
    required String decisionId,
    required String decisionTitle,
  }) async {
    committed++;
  }

  @override
  Future<void> onReverted(String decisionId) async {
    reverted++;
  }
}
