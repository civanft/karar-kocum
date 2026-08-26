import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DORMANT SÖZLEŞME — v1'de HİÇBİR analitik veri toplanmaz (PR-STORE-2).
///
/// `firebase_analytics` bağımlılığı v1 production yüzeyinden ÇIKARILDI:
/// consent ekranı olmadan SDK'yı binary'de tutmak, toplanmayan veri için
/// mağaza beyanı ve gizlilik manifesti yükümlülüğü doğuruyordu.
///
/// Arayüz ve çağrı noktaları KORUNUR: ileride consent akışıyla birlikte
/// gerçek bir uygulama takılabilsin diye. Bugün tek uygulama
/// [NoopAnalyticsService]'tir ve platform kanalına hiçbir şey gitmez.
///
/// Olay şeması — TEKNIK-MIMARI.md §9.1 / AI-ANALIZ-TASARIMI.md §9.
/// KURAL: parametrelerde karar içeriği/PII ASLA taşınmaz (yalnız sayısal
/// meta ve enum'lar). Yeni olay eklerken önce şema dokümanını güncelle.
abstract interface class AnalyticsService {
  // Aktivasyon hunisi
  Future<void> logDecisionCreated({required String source}); // blank|template
  Future<void> logTemplateSelected({
    required String templateId,
  }); // A1 sheet CTA
  Future<void> logOptionsCompleted({required int optionCount});
  Future<void> logCriteriaCompleted({
    required int criterionCount,
    required int aiSuggestedCount,
  });
  Future<void> logCriterionSuggestionAccepted({
    required String origin,
  }); // A2 chip: template|keyword|generic
  Future<void> logScoringCompleted();
  Future<void> logResultViewed(); // v1 aktivasyon olayı (yerel skor)

  // AI kullanım metrikleri (ekran PR #6'da bağlanır)
  Future<void> logAnalysisRequested({required String tier});
  Future<void> logAnalysisCompleted({
    required String tier,
    required int latencyMs,
    required bool cached,
  });
  Future<void> logAnalysisFeedback({required bool thumbsUp});

  // Paylaşım & gelir hunisi
  Future<void> logResultShared({
    required String channel,
    required String format,
  });
  Future<void> logPaywallViewed({required String source});

  /// Mağaza zorunlusu yasal sayfa açıldı (PR-LEGAL-1).
  /// [document]: privacy|terms|support — içerik/PII taşımaz.
  Future<void> logLegalLinkOpened({required String document});

  Future<void> setUserProperties({String? plan, int? decisionsTotal});
}

/// v1'in TEK uygulaması: her çağrı sessizce tamamlanır.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> noSuchMethod(Invocation invocation) async {}

  @override
  Future<void> logDecisionCreated({required String source}) async {}

  @override
  Future<void> logTemplateSelected({required String templateId}) async {}
  @override
  Future<void> logOptionsCompleted({required int optionCount}) async {}
  @override
  Future<void> logCriteriaCompleted({
    required int criterionCount,
    required int aiSuggestedCount,
  }) async {}

  @override
  Future<void> logCriterionSuggestionAccepted({
    required String origin,
  }) async {}
  @override
  Future<void> logScoringCompleted() async {}
  @override
  Future<void> logResultViewed() async {}
  @override
  Future<void> logAnalysisRequested({required String tier}) async {}
  @override
  Future<void> logAnalysisCompleted({
    required String tier,
    required int latencyMs,
    required bool cached,
  }) async {}
  @override
  Future<void> logAnalysisFeedback({required bool thumbsUp}) async {}
  @override
  Future<void> logResultShared({
    required String channel,
    required String format,
  }) async {}
  @override
  Future<void> logPaywallViewed({required String source}) async {}
  @override
  Future<void> logLegalLinkOpened({required String document}) async {}
  @override
  Future<void> setUserProperties({String? plan, int? decisionsTotal}) async {}
}

/// v1 sözleşmesi: Firebase hazır olsun ya da olmasın analytics KAPALIDIR.
/// Saf fonksiyon — testte doğrulanabilir, ileride consent parametresi alacak
/// yere hazır bir seam bırakır.
bool analyticsEnabledInV1() => false;

/// Daima [NoopAnalyticsService]. Testler bu provider'ı override edebilir.
final analyticsServiceProvider = Provider<AnalyticsService>(
  (_) => const NoopAnalyticsService(),
);
