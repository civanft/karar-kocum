import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../../core/config/firebase_environment.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../data/firebase_ai_analysis_client.dart';
import '../../data/mock_ai_analysis_client.dart';
import '../../data/unavailable_ai_analysis_client.dart';
import '../../domain/entities/ai_analysis.dart';
import '../../domain/repositories/ai_analysis_client.dart';

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

    try {
      final analysis = await ref.read(aiAnalysisClientProvider).analyze(arg);
      state = AnalysisSuccess(analysis);
      unawaited(
        ref.read(analyticsServiceProvider).logAnalysisCompleted(
              tier: 'basic',
              latencyMs: 0, // sunucu tarafı ölçüyor; istemci süresi Sprint 3+
              cached: false,
            ),
      );
    } on AiAnalysisFailure catch (f) {
      state = switch (f.kind) {
        AnalysisFailureKind.quotaExceeded =>
          AnalysisQuotaExceeded(totalCredits: f.totalCredits ?? 5),
        AnalysisFailureKind.retryable =>
          AnalysisError(message: f.message, retryable: true),
        AnalysisFailureKind.nonRetryable =>
          AnalysisError(message: f.message, retryable: false),
      };
    } catch (_) {
      // Beklenmedik istisna: güvenli, yeniden denenebilir hata.
      state = const AnalysisError(
        message: 'Analiz şu an yapılamadı, birazdan tekrar dene.',
        retryable: true,
      );
    }
  }

  /// "Yeniden analiz et" onayından sonra çağrılır.
  Future<void> reanalyze() {
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
