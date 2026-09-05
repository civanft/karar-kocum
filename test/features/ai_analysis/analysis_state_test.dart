import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/mock_ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/retry_directive.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İstenen sonucu senkron döndüren/atan test client'ı.
class _StubClient implements AiAnalysisClient {
  _StubClient(this._result);
  final Object _result; // AiAnalysis | AiAnalysisFailure

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    if (_result is AiAnalysisFailure) throw _result;
    return _result as AiAnalysis;
  }
}

void main() {
  // İş Paketi 2: controller bekleyen requestId'yi SharedPreferences'ta tutar.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer make(AiAnalysisClient client) {
    final container = ProviderContainer(
      overrides: [aiAnalysisClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('başlangıç durumu Idle (boş durum)', () {
    final c = make(_StubClient(AiAnalysis.mock()));
    expect(c.read(analysisControllerProvider('d1')), isA<AnalysisIdle>());
  });

  test('analyze: Idle → Loading → Success (callable sonucu)', () async {
    final c = make(_StubClient(AiAnalysis.mock()));
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

  test('retryable hata → AnalysisError(retryable: true)', () async {
    final c = make(
      _StubClient(
        const AiAnalysisFailure(
          kind: AnalysisFailureKind.retryable,
          message: 'servis kesintisi',
          retry: RetryDirective.sameRequest,
        ),
      ),
    );
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    final state = c.read(analysisControllerProvider('d1'));
    expect(state, isA<AnalysisError>());
    expect((state as AnalysisError).retryable, isTrue);
    expect(state.message, 'servis kesintisi');
  });

  test('nonRetryable hata → AnalysisError(retryable: false)', () async {
    final c = make(
      _StubClient(
        const AiAnalysisFailure(
          kind: AnalysisFailureKind.nonRetryable,
          message: 'Bu içerik analiz edilemiyor.',
          retry: RetryDirective.none,
        ),
      ),
    );
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    final state = c.read(analysisControllerProvider('d1'));
    expect((state as AnalysisError).retryable, isFalse);
  });

  test('kota bitti → AnalysisQuotaExceeded(totalCredits)', () async {
    final c = make(
      _StubClient(
        const AiAnalysisFailure(
          kind: AnalysisFailureKind.quotaExceeded,
          message: 'bitti',
          retry: RetryDirective.none,
          totalCredits: 5,
        ),
      ),
    );
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    final state = c.read(analysisControllerProvider('d1'));
    expect(state, isA<AnalysisQuotaExceeded>());
    expect((state as AnalysisQuotaExceeded).totalCredits, 5);
  });

  test('beklenmedik istisna → güvenli retryable hata', () async {
    final c = make(_ThrowingClient());
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    await c.read(analysisControllerProvider('d1').notifier).analyze();

    final state = c.read(analysisControllerProvider('d1'));
    expect(state, isA<AnalysisError>());
    expect((state as AnalysisError).retryable, isTrue);
  });

  test('çift istek koruması: Loading iken ikinci analyze yok sayılır',
      () async {
    final c = make(
      MockAiAnalysisClient(delay: const Duration(milliseconds: 50)),
    );
    final sub = c.listen(analysisControllerProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    final notifier = c.read(analysisControllerProvider('d1').notifier);
    final first = notifier.analyze();
    final second = notifier.analyze(); // loading'de — anında dönmeli
    await Future.wait([first, second]);

    expect(
      c.read(analysisControllerProvider('d1')),
      isA<AnalysisSuccess>(),
    );
  });
}

class _ThrowingClient implements AiAnalysisClient {
  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async =>
      throw StateError('beklenmedik');
}
