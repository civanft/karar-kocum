import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';

void main() {
  ProviderContainer make(MockScenario scenario) {
    final container = ProviderContainer(
      overrides: [
        mockScenarioProvider.overrideWithValue(scenario),
        mockAnalysisDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('başlangıç durumu Idle (boş durum)', () {
    final c = make(MockScenario.success);
    expect(
      c.read(analysisControllerProvider('d1')),
      isA<AnalysisIdle>(),
    );
  });

  test('analyze: Idle → Loading → Success', () async {
    final c = make(MockScenario.success);
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);
    final states = <AnalysisState>[];
    final watcher = c.listen(
      analysisControllerProvider('d1'),
      (_, next) => states.add(next),
    );
    addTearDown(watcher.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    expect(states.first, isA<AnalysisLoading>());
    expect(states.last, isA<AnalysisSuccess>());
    final success = states.last as AnalysisSuccess;
    expect(success.analysis.strengths, isNotEmpty);
    expect(success.analysis.recommendation, isNotEmpty);
  });

  test('hata senaryosu: retryable AnalysisError', () async {
    final c = make(MockScenario.error);
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    final state = c.read(analysisControllerProvider('d1'));
    expect(state, isA<AnalysisError>());
    expect((state as AnalysisError).retryable, isTrue);
  });

  test('kota senaryosu: AnalysisQuotaExceeded(limit 5)', () async {
    final c = make(MockScenario.quotaExceeded);
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    final state = c.read(analysisControllerProvider('d1'));
    expect(state, isA<AnalysisQuotaExceeded>());
    expect((state as AnalysisQuotaExceeded).monthlyLimit, 5);
  });

  test('çift istek koruması: Loading iken ikinci analyze yok sayılır',
      () async {
    final container = ProviderContainer(
      overrides: [
        mockScenarioProvider.overrideWithValue(MockScenario.success),
        mockAnalysisDelayProvider
            .overrideWithValue(const Duration(milliseconds: 50)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(analysisControllerProvider('d1').notifier);
    final first = notifier.analyze();
    final second = notifier.analyze(); // loading'de — anında dönmeli
    await Future.wait([first, second]);

    expect(
      container.read(analysisControllerProvider('d1')),
      isA<AnalysisSuccess>(),
    );
  });
}
