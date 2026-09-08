import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/decision_edit_screen.dart';

/// İŞ PAKETİ 4 — TEK ÇIKIŞ KAPISI ve LIFECYCLE FLUSH.
///
/// "Sonucu Gör" için kurulan flush koruması tek yoldu; sistem geri hareketi,
/// Android back ve AppBar back bekleyen yazımı beklemeden ekranı kapatıyordu.
/// Uygulama arka plana alındığında da bekleyen debounce yazımı kayboluyordu.
class _GateRepository implements DecisionRepository {
  _GateRepository(this._decision);
  Decision _decision;
  bool failNextPatch = false;
  int patchCalls = 0;

  @override
  Future<Decision?> getById(String id) async => _decision;

  @override
  Stream<Decision?> watchById(String id) => const Stream.empty();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
    patchCalls++;
    if (failNextPatch) {
      failNextPatch = false;
      throw StateError('offline');
    }
    _decision = _decision.copyWith(updatedAt: DateTime.now());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Decision _complete() => Decision(
      id: 'd1',
      ownerUid: 'u1',
      title: 'Tamamlanmış karar',
      options: const [
        Option(id: 'o1', title: 'A'),
        Option(id: 'o2', title: 'B'),
      ],
      criteria: const [Criterion(id: 'c1', name: 'Fiyat', weight: 8)],
      scores: const {
        'o1': {'c1': CellScore(value: 4)},
        'o2': {'c1': CellScore(value: 3)},
      },
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Navigasyonu SAYAR: "tek navigasyon" iddiası ancak sayılırsa kanıtlanır.
class _CountingObserver extends NavigatorObserver {
  int pops = 0;
  int pushes = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

const _errorText =
    'Değişiklik kaydedilemedi. Bağlantını kontrol edip tekrar dene.';

void main() {
  late _GateRepository repo;
  late ProviderContainer container;
  late _CountingObserver nav;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repo = _GateRepository(_complete());
    container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
        // Debounce kendiliğinden tetiklenmesin: flush'ı biz tetikleyeceğiz.
        autosaveDebounceProvider.overrideWithValue(const Duration(minutes: 5)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(decisionEditorProvider('d1').future);
    final sub = container.listen(decisionEditorProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    nav = _CountingObserver();
    final router = GoRouter(
      observers: [nav],
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME ROUTE')),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, __) => const DecisionEditScreen(decisionId: 'd1'),
            ),
          ],
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
    router.go('/home/edit');
    await tester.pumpAndSettle();
    nav.pops = 0;
    nav.pushes = 0;
  }

  void makeDirty() => container
      .read(decisionEditorProvider('d1').notifier)
      .setCriterionWeight('c1', 5);

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  group('lifecycle flush', () {
    testWidgets('paused: bekleyen yazım FLUSH edilir', (tester) async {
      await pump(tester);
      makeDirty();
      expect(repo.patchCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(repo.patchCalls, 1);
      expect(container.read(decisionSaveStateProvider('d1')), isA<SaveIdle>());
    });

    testWidgets('inactive de flush tetikler', (tester) async {
      await pump(tester);
      makeDirty();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();

      expect(repo.patchCalls, 1);
    });

    testWidgets('flush BAŞARISIZ ise hata görünür, niyet KAYBOLMAZ',
        (tester) async {
      await pump(tester);
      makeDirty();
      repo.failNextPatch = true;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull); // unhandled async yok
      expect(
        container.read(decisionSaveStateProvider('d1')),
        isA<SaveFailed>(),
      );
      expect(find.text(_errorText), findsOneWidget);

      // Niyet kuyrukta: retry aynı niyeti yazar.
      await container.read(decisionEditorProvider('d1').notifier).retrySave();
      expect(container.read(decisionSaveStateProvider('d1')), isA<SaveIdle>());
    });

    testWidgets('YİNELENEN lifecycle olayları TEK yazım üretir',
        (tester) async {
      await pump(tester);
      makeDirty();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(repo.patchCalls, 1);
    });

    testWidgets(
        'arka plan → ön plan → arka plan: İKİNCİ yazım YOK '
        '(kuyruk gerçekten boşaltılmış olmalı)', (tester) async {
      await pump(tester);
      makeDirty();

      // 1. tur: yazım TAMAMEN bitene kadar bekle.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 1);

      // 2. tur: yeni değişiklik YOK → yazacak bir şey de yok.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(
        repo.patchCalls,
        1,
        reason: 'kuyruk boşaltılmamış',
      );

      // 3. tur: GERÇEK yeni değişiklik ise yazılmalı (kapı kilitlenmemeli).
      makeDirty();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 2);
    });

    testWidgets('bekleyen yazım yokken lifecycle YAZIM YAPMAZ', (tester) async {
      await pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(repo.patchCalls, 0);
    });
  });

  group('geri navigasyon kapısı', () {
    testWidgets('sistem geri: flush BAŞARILI → TEK kez çıkılır',
        (tester) async {
      await pump(tester);
      makeDirty();

      await systemBack(tester);

      expect(repo.patchCalls, 1);
      expect(nav.pops, 1);
      expect(find.text('HOME ROUTE'), findsOneWidget);
    });

    testWidgets('sistem geri: flush BAŞARISIZ → ÇIKILMAZ, hata görünür',
        (tester) async {
      await pump(tester);
      makeDirty();
      repo.failNextPatch = true;

      await systemBack(tester);

      expect(find.text('HOME ROUTE'), findsNothing);
      expect(find.text(_errorText), findsOneWidget);
    });

    testWidgets('ÇİFT geri hareketi TEK flush ve TEK navigasyon üretir',
        (tester) async {
      await pump(tester);
      makeDirty();

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(repo.patchCalls, 1);
      expect(nav.pops, 1, reason: 'tam olarak BİR navigasyon');
      expect(find.text('HOME ROUTE'), findsOneWidget);
    });

    testWidgets('ÇİFT "Sonucu Gör" dokunuşu TEK push üretir', (tester) async {
      await pump(tester);
      makeDirty();

      // Aradaki pump olmadan iki dokunuş: ikincisi kapı meşgulken gelir.
      await tester.tap(find.text('Sonucu Gör'), warnIfMissed: false);
      await tester.tap(find.text('Sonucu Gör'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repo.patchCalls, 1);
      expect(nav.pushes, 1, reason: 'tam olarak BİR navigasyon');
      expect(find.text('RESULT ROUTE'), findsOneWidget);
    });

    testWidgets('AppBar geri butonu AYNI kapıyı kullanır', (tester) async {
      await pump(tester);
      makeDirty();
      repo.failNextPatch = true;

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('HOME ROUTE'), findsNothing);
      expect(find.text(_errorText), findsOneWidget);
    });

    testWidgets('"Sonucu Gör" ile geri AYNI tek kapıyı paylaşır',
        (tester) async {
      await pump(tester);
      makeDirty();
      repo.failNextPatch = true;

      await tester.tap(find.text('Sonucu Gör'));
      await tester.pumpAndSettle();

      expect(find.text('RESULT ROUTE'), findsNothing);
      expect(find.text(_errorText), findsOneWidget);
      expect(repo.patchCalls, 1);
    });
  });
}
