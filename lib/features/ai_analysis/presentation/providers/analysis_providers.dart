import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/ai_analysis.dart';

/// Analiz durum makinesi — kartın 5 durumu (PR #6D-1).
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

/// 6D-1 mock senaryosu: gerçek istemci (6D-2) gelene dek kontrolcünün
/// hangi sonucu döndüreceğini belirler. Testler/galeri override eder.
enum MockScenario { success, error, quotaExceeded }

final mockScenarioProvider =
    Provider<MockScenario>((_) => MockScenario.success);

/// Mock gecikme — gerçek çağrı hissi; testlerde Duration.zero.
final mockAnalysisDelayProvider =
    Provider<Duration>((_) => const Duration(milliseconds: 1400));

/// Karar başına analiz durumu. 6D-2'de gövde gerçek callable çağrısıyla
/// değişecek; ARAYÜZ (state + analyze/reset) aynı kalacak.
class AnalysisController
    extends AutoDisposeFamilyNotifier<AnalysisState, String> {
  @override
  AnalysisState build(String arg) => const AnalysisIdle();

  Future<void> analyze() async {
    if (state is AnalysisLoading) return; // çift istek koruması (6B kararı)
    state = const AnalysisLoading();

    await Future<void>.delayed(ref.read(mockAnalysisDelayProvider));

    state = switch (ref.read(mockScenarioProvider)) {
      MockScenario.success => AnalysisSuccess(AiAnalysis.mock()),
      MockScenario.error => const AnalysisError(
          message: 'Analiz şu an yapılamadı. İnternet bağlantını kontrol '
              'edip tekrar deneyebilirsin.',
          retryable: true,
        ),
      MockScenario.quotaExceeded =>
        const AnalysisQuotaExceeded(totalCredits: 5),
    };
  }

  /// "Yeniden analiz et" onayından sonra çağrılır.
  Future<void> reanalyze() {
    state = const AnalysisIdle();
    return analyze();
  }

  /// 👍/👎 — 6D-2'de analytics'e bağlanır (analysis_feedback olayı).
  void sendFeedback({required bool thumbsUp}) {}
}

final analysisControllerProvider = NotifierProvider.autoDispose
    .family<AnalysisController, AnalysisState, String>(AnalysisController.new);
