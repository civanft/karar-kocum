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

/// İŞ PAKETİ 4 / DİLİM D — "Sonucu Gör" navigasyon kapısı (widget seviyesi).
///
/// Flush BAŞARISIZSA rota DEĞİŞMEZ ve hata yüzeyi görünür kalır; başarılıysa
/// rota TAM BİR KEZ değişir.
class _GateRepository implements DecisionRepository {
  _GateRepository(this._decision);
  Decision _decision;
  bool failNextPatch = false;

  @override
  Future<Decision?> getById(String id) async => _decision;

  @override
  Stream<Decision?> watchById(String id) => const Stream.empty();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
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

void main() {
  late _GateRepository repo;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repo = _GateRepository(_complete());
    container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
        autosaveDebounceProvider.overrideWithValue(const Duration(minutes: 5)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(decisionEditorProvider('d1').future);
    final sub = container.listen(decisionEditorProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, __) => const DecisionEditScreen(decisionId: 'd1'),
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
    await tester.pumpAndSettle();
  }

  testWidgets('flush BAŞARISIZ → rota DEĞİŞMEZ, hata yüzeyi görünür',
      (tester) async {
    await pump(tester);
    // Bekleyen bir niyet oluştur ve yazımı çökert.
    container
        .read(decisionEditorProvider('d1').notifier)
        .setCriterionWeight('c1', 5);
    repo.failNextPatch = true;

    await tester.tap(find.text('Sonucu Gör'));
    await tester.pumpAndSettle();

    expect(find.text('RESULT ROUTE'), findsNothing);
    expect(
      find.text(
        'Değişiklik kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('flush BAŞARILI → rota TAM BİR KEZ değişir', (tester) async {
    await pump(tester);
    container
        .read(decisionEditorProvider('d1').notifier)
        .setCriterionWeight('c1', 5);

    await tester.tap(find.text('Sonucu Gör'));
    await tester.pumpAndSettle();

    expect(find.text('RESULT ROUTE'), findsOneWidget);
  });

  testWidgets('flush sürerken ÇİFT DOKUNMA ikinci navigasyon üretmez',
      (tester) async {
    await pump(tester);
    container
        .read(decisionEditorProvider('d1').notifier)
        .setCriterionWeight('c1', 5);

    await tester.tap(find.text('Sonucu Gör'));
    await tester.pump(); // flush sürüyor
    // İkinci dokunuş: buton devre dışı, ikinci akış başlamaz.
    await tester.tap(find.text('Sonucu Gör'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('RESULT ROUTE'), findsOneWidget);
  });
}
