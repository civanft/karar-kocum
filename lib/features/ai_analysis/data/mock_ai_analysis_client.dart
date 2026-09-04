import '../domain/entities/ai_analysis.dart';
import '../domain/repositories/ai_analysis_client.dart';

/// Yerel mod (Firebase yok) ve testler için sahte istemci.
/// Gerçek callable deploy edilene dek uygulama yerel modda AI'ı bununla
/// gösterir; senaryo enjekte edilerek her durum test edilebilir.
enum MockAnalysisScenario { success, retryableError, nonRetryable, quota }

class MockAiAnalysisClient implements AiAnalysisClient {
  MockAiAnalysisClient({
    this.scenario = MockAnalysisScenario.success,
    this.delay = const Duration(milliseconds: 1400),
  });

  final MockAnalysisScenario scenario;
  final Duration delay;

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    await Future<void>.delayed(delay);
    return switch (scenario) {
      MockAnalysisScenario.success => AiAnalysis.mock(),
      MockAnalysisScenario.retryableError => throw const AiAnalysisFailure(
          kind: AnalysisFailureKind.retryable,
          message: 'Analiz şu an yapılamadı. İnternet bağlantını kontrol '
              'edip tekrar deneyebilirsin.',
        ),
      MockAnalysisScenario.nonRetryable => throw const AiAnalysisFailure(
          kind: AnalysisFailureKind.nonRetryable,
          message: 'Bu içerik analiz edilemiyor.',
        ),
      MockAnalysisScenario.quota => throw const AiAnalysisFailure(
          kind: AnalysisFailureKind.quotaExceeded,
          message: 'Ücretsiz analiz hakkın bitti.',
          totalCredits: 5,
        ),
    };
  }
}
