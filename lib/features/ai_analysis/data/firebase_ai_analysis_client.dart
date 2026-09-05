import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/ai_analysis.dart';
import '../domain/repositories/ai_analysis_client.dart';
import '../domain/retry_directive.dart';

/// `analyzeDecision` callable'ını çağırır ve Firebase hatalarını
/// ürün-anlamlı [AiAnalysisFailure]'a eşler (Firebase tipleri burada kalır).
///
/// App Check: fonksiyon consumeAppCheckToken ister → limitedUseAppCheckToken
/// açık (her çağrı tek-kullanımlık token üretir, replay koruması).
class FirebaseAiAnalysisClient implements AiAnalysisClient {
  const FirebaseAiAnalysisClient(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    final callable = _functions.httpsCallable(
      'analyzeDecision',
      options: HttpsCallableOptions(limitedUseAppCheckToken: true),
    );
    try {
      final result = await callable.call<Map<Object?, Object?>>(
        // Payload sunucuda STRICT doğrulanır: fazladan alan reddedilir.
        <String, Object?>{'decisionId': decisionId, 'requestId': requestId},
      );
      final analysis = result.data['analysis'];
      if (analysis is! Map) {
        // Sunucu 200 döndü ama gövde beklenen biçimde değil: iş büyük
        // olasılıkla TAMAMLANDI, aynı anahtar saklanan sonucu getirir.
        throw const AiAnalysisFailure(
          kind: AnalysisFailureKind.retryable,
          message: 'Analiz alınamadı, lütfen tekrar dene.',
          retry: RetryDirective.sameRequest,
        );
      }
      return AiAnalysis.fromMap(analysis);
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  /// Backend hata taksonomisi → AiAnalysisFailure.
  ///
  /// `details.appCode`, `e.code`'dan daha kesindir (quota/rate/daily hepsi
  /// resource-exhausted döner ama appCode ayırır). `details.retry` ise
  /// sunucunun AÇIK yönergesidir: journal durumunu yalnız sunucu bilir.
  AiAnalysisFailure _mapError(FirebaseFunctionsException e) {
    final details =
        e.details is Map ? e.details as Map : const <Object?, Object?>{};
    final appCode = details['appCode'] as String? ?? e.code;
    final retry = retryDirectiveFor(
      appCode,
      serverDirective: details['retry'] as String?,
    );
    // Backend mesajı kullanıcı-dostu ve TR (errors.ts); güvenle gösterilir.
    final message = e.message?.isNotEmpty == true
        ? e.message!
        : 'Analiz şu an yapılamadı, birazdan tekrar dene.';

    if (appCode == 'quota-exceeded') {
      return AiAnalysisFailure(
        kind: AnalysisFailureKind.quotaExceeded,
        message: message,
        retry: retry,
        totalCredits: (details['initial'] as num?)?.toInt() ?? 5,
      );
    }

    return AiAnalysisFailure(
      // Retry SUNULUP sunulmayacağı artık tek kaynaktan gelir: yönerge.
      kind: retry == RetryDirective.none
          ? AnalysisFailureKind.nonRetryable
          : AnalysisFailureKind.retryable,
      message: message,
      retry: retry,
    );
  }
}
