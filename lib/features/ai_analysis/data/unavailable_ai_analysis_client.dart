import '../domain/entities/ai_analysis.dart';
import '../domain/repositories/ai_analysis_client.dart';
import '../domain/retry_directive.dart';

/// Release'de servise bağlanılamadığında kullanılan istemci (PR-RELEASE-1).
///
/// MOCK DEĞİLDİR: uydurma bir analiz döndürmez. Her çağrı, kullanıcıya
/// gösterilebilir ve TEKRAR DENENEBİLİR bir hata ile sonuçlanır — böylece
/// kullanıcı hiçbir zaman gerçek sanacağı bir sonuç görmez.
class UnavailableAiAnalysisClient implements AiAnalysisClient {
  const UnavailableAiAnalysisClient();

  static const String message =
      'Servise bağlanılamadı. Bağlantını kontrol edip tekrar dene.';

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    // Firebase hiç kurulamadı: istek sunucuya ULAŞMADI, anahtar temiz.
    throw const AiAnalysisFailure(
      kind: AnalysisFailureKind.retryable,
      message: message,
      retry: RetryDirective.sameRequest,
    );
  }
}
