import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/ai_analysis.dart';
import '../domain/repositories/ai_analysis_client.dart';

/// `analyzeDecision` callable'ını çağırır ve Firebase hatalarını
/// ürün-anlamlı [AiAnalysisFailure]'a eşler (Firebase tipleri burada kalır).
///
/// App Check: fonksiyon consumeAppCheckToken ister → limitedUseAppCheckToken
/// açık (her çağrı tek-kullanımlık token üretir, replay koruması).
class FirebaseAiAnalysisClient implements AiAnalysisClient {
  const FirebaseAiAnalysisClient(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<AiAnalysis> analyze(String decisionId) async {
    final callable = _functions.httpsCallable(
      'analyzeDecision',
      options: HttpsCallableOptions(limitedUseAppCheckToken: true),
    );
    try {
      final result = await callable.call<Map<Object?, Object?>>(
        <String, Object?>{'decisionId': decisionId},
      );
      final analysis = result.data['analysis'];
      if (analysis is! Map) {
        throw const AiAnalysisFailure(
          kind: AnalysisFailureKind.retryable,
          message: 'Analiz alınamadı, lütfen tekrar dene.',
        );
      }
      return AiAnalysis.fromMap(analysis);
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// Backend hata taksonomisi → AiAnalysisFailure.
  /// details.appCode, e.code'dan daha kesindir (quota/rate/daily hepsi
  /// resource-exhausted döner ama appCode ayırır).
  AiAnalysisFailure _mapError(FirebaseFunctionsException e) {
    final details =
        e.details is Map ? e.details as Map : const <Object?, Object?>{};
    final appCode = details['appCode'] as String? ?? e.code;
    // Backend mesajı kullanıcı-dostu ve TR (errors.ts); güvenle gösterilir.
    final message = e.message?.isNotEmpty == true
        ? e.message!
        : 'Analiz şu an yapılamadı, birazdan tekrar dene.';

    switch (appCode) {
      case 'quota-exceeded':
        return AiAnalysisFailure(
          kind: AnalysisFailureKind.quotaExceeded,
          message: message,
          totalCredits: (details['initial'] as num?)?.toInt() ?? 5,
        );
      case 'moderated':
      case 'invalid-argument':
      case 'daily-limit':
        // Bugün tekrar denemek işe yaramaz.
        return AiAnalysisFailure(
          kind: AnalysisFailureKind.nonRetryable,
          message: message,
        );
      case 'rate-limited':
      case 'ai-unavailable':
      case 'unauthenticated':
      case 'internal':
      default:
        return AiAnalysisFailure(
          kind: AnalysisFailureKind.retryable,
          message: message,
        );
    }
  }
}
