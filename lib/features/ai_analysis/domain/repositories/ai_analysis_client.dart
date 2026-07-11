import '../entities/ai_analysis.dart';

/// AI analiz sözleşmesi — istemci `analyzeDecision` callable'ını çağırır.
/// Saf domain: Firebase tipleri data katmanında kalır; başarısızlık
/// [AiAnalysisFailure] olarak fırlatılır (presentation onu duruma çevirir).
abstract interface class AiAnalysisClient {
  /// Kararı analiz eder; sonuç [AiAnalysis], hata [AiAnalysisFailure].
  Future<AiAnalysis> analyze(String decisionId);
}

/// Analiz başarısızlığının ürün-anlamlı sınıflandırması.
enum AnalysisFailureKind {
  /// Tekrar denemenin işe yarayabileceği geçici hata (ağ, servis, rate).
  retryable,

  /// Tekrar denemenin bugün işe yaramayacağı hata (moderasyon, geçersiz,
  /// günlük global limit).
  nonRetryable,

  /// Kullanıcının ücretsiz + ödül kredisi bitti.
  quotaExceeded,
}

class AiAnalysisFailure implements Exception {
  const AiAnalysisFailure({
    required this.kind,
    required this.message,
    this.totalCredits,
  });

  final AnalysisFailureKind kind;
  final String message;

  /// quotaExceeded için toplam ücretsiz kredi (kart metni için).
  final int? totalCredits;
}
