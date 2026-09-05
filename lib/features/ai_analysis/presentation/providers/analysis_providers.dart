import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../../core/config/firebase_environment.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../data/firebase_ai_analysis_client.dart';
import '../../data/mock_ai_analysis_client.dart';
import '../../data/pending_analysis_request_store.dart';
import '../../data/unavailable_ai_analysis_client.dart';
import '../../domain/analysis_request_id.dart';
import '../../domain/entities/ai_analysis.dart';
import '../../domain/repositories/ai_analysis_client.dart';
import '../../domain/retry_directive.dart';

/// Analiz durum makinesi — kartın 5 durumu (PR #6D-1, UI değişmedi).
sealed class AnalysisState {
  const AnalysisState();
}

/// Henüz analiz yok — CTA gösterilir.
class AnalysisIdle extends AnalysisState {
  const AnalysisIdle();
}

class AnalysisLoading extends AnalysisState {
  const AnalysisLoading();
}

class AnalysisSuccess extends AnalysisState {
  const AnalysisSuccess(this.analysis);
  final AiAnalysis analysis;
}

class AnalysisError extends AnalysisState {
  const AnalysisError({required this.message, required this.retryable});
  final String message;
  final bool retryable;
}

class AnalysisQuotaExceeded extends AnalysisState {
  const AnalysisQuotaExceeded({required this.totalCredits});

  /// Başlangıçta verilen toplam ücretsiz kredi (yenilenmez — 6C-2).
  final int totalCredits;
}

/// AI istemcisi bağlama noktası (6D-2, PR-RELEASE-1).
///
/// Mock YALNIZ localMode'da (debug/profile/test) kullanılır. Release'de
/// bağlantı kurulamadığında (`unavailable`) mock DÖNMEZ — uydurma bir analiz
/// kullanıcıya gerçek gibi görünürdü. Testler bu provider'ı override eder.
final aiAnalysisClientProvider = Provider<AiAnalysisClient>((ref) {
  return switch (ref.watch(firebaseStatusProvider)) {
    FirebaseStatus.ready => FirebaseAiAnalysisClient(
        FirebaseFunctions.instanceFor(
          region: ref.watch(functionsRegionProvider),
        ),
      ),
    FirebaseStatus.localMode => MockAiAnalysisClient(),
    FirebaseStatus.unavailable => const UnavailableAiAnalysisClient(),
  };
});

/// Karar başına analiz durumu — gövde artık gerçek callable çağırır (6D-2).
/// ARAYÜZ (analyze/reanalyze/sendFeedback + AnalysisState) DEĞİŞMEDİ.
class AnalysisController
    extends AutoDisposeFamilyNotifier<AnalysisState, String> {
  @override
  AnalysisState build(String arg) => const AnalysisIdle();

  Future<void> analyze() async {
    if (state is AnalysisLoading) return; // çift istek koruması (6B kararı)
    state = const AnalysisLoading();

    unawaited(
      ref.read(analyticsServiceProvider).logAnalysisRequested(tier: 'basic'),
    );

    // İDEMPOTENCY ANAHTARI (İş Paketi 2): tek kullanıcı eylemi için BİR kez
    // üretilir. Süreç kesintisi sonrası bekleyen anahtar geri alınır, böylece
    // retry sunucudaki journal'ı sağlayıcıyı YENİDEN ÇAĞIRMADAN finalize eder.
    final uid = ref.read(currentUidProvider);
    final store = ref.read(pendingAnalysisRequestStoreProvider);
    String requestId;
    if (uid == null) {
      // Oturum yoksa kalıcılık alanı yok; tek seferlik anahtar yeterli.
      requestId = newAnalysisRequestId();
    } else {
      requestId =
          await store.read(uid: uid, decisionId: arg) ?? newAnalysisRequestId();
      await store.write(uid: uid, decisionId: arg, requestId: requestId);
    }

    Future<void> clearPending() async {
      if (uid != null) {
        await store.clear(uid: uid, decisionId: arg);
      }
    }

    try {
      final analysis = await ref
          .read(aiAnalysisClientProvider)
          .analyze(decisionId: arg, requestId: requestId);
      await clearPending(); // terminal başarı
      state = AnalysisSuccess(analysis);
      unawaited(
        ref.read(analyticsServiceProvider).logAnalysisCompleted(
              tier: 'basic',
              latencyMs: 0, // sunucu tarafı ölçüyor; istemci süresi Sprint 3+
              cached: false,
            ),
      );
    } on AiAnalysisFailure catch (f) {
      // Bekleyen anahtarın kaderini SUNUCUNUN yönergesi belirler (2B).
      // `sameRequest` DIŞINDAKİ her durumda anahtar temizlenir: aksi halde
      // sunucuda tükenmiş bir requestId sonsuza kadar tekrar gönderilirdi.
      if (f.retry != RetryDirective.sameRequest) {
        await clearPending();
      }
      state = switch (f.kind) {
        AnalysisFailureKind.quotaExceeded =>
          AnalysisQuotaExceeded(totalCredits: f.totalCredits ?? 5),
        AnalysisFailureKind.retryable =>
          AnalysisError(message: f.message, retryable: true),
        AnalysisFailureKind.nonRetryable =>
          AnalysisError(message: f.message, retryable: false),
      };
    } catch (_) {
      // Beklenmedik istisna: çağrının sunucuya ulaşıp ulaşmadığı BİLİNMİYOR.
      // Bekleyen anahtar KORUNUR (sameRequest); iş tamamlanmışsa bir sonraki
      // deneme saklanan sonucu getirir, hiç başlamamışsa baştan çalışır.
      state = const AnalysisError(
        message: 'Analiz şu an yapılamadı, birazdan tekrar dene.',
        retryable: true,
      );
    }
  }

  /// "Yeniden analiz et" onayından sonra çağrılır.
  ///
  /// AÇIK kullanıcı eylemi → YENİ idempotency anahtarı: bekleyen anahtar
  /// silinir, böylece sunucuda yeni bir analiz üretilir.
  Future<void> reanalyze() async {
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      await ref
          .read(pendingAnalysisRequestStoreProvider)
          .clear(uid: uid, decisionId: arg);
    }
    state = const AnalysisIdle();
    return analyze();
  }

  /// 👍/👎 — analysis_feedback olayı (6D-2 bağlandı).
  void sendFeedback({required bool thumbsUp}) {
    unawaited(
      ref.read(analyticsServiceProvider).logAnalysisFeedback(
            thumbsUp: thumbsUp,
          ),
    );
  }
}

final analysisControllerProvider = NotifierProvider.autoDispose
    .family<AnalysisController, AnalysisState, String>(AnalysisController.new);
