import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/firebase_bootstrap.dart';

/// KVKK consent kapısı — varsayılan KAPALI (opt-in). Sprint 6 onboarding'i
/// kullanıcıya sorar ve kalıcılaştırır; o güne dek analytics sessizdir.
final analyticsConsentProvider = StateProvider<bool>((_) => false);

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

  Future<void> setUserProperties({String? plan, int? decisionsTotal});
}

class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService([FirebaseAnalytics? analytics])
      : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  Future<void> _log(String name, [Map<String, Object>? params]) =>
      _analytics.logEvent(name: name, parameters: params);

  @override
  Future<void> logDecisionCreated({required String source}) =>
      _log('decision_created', {'source': source});

  @override
  Future<void> logTemplateSelected({required String templateId}) =>
      _log('template_selected', {'template_id': templateId});

  @override
  Future<void> logOptionsCompleted({required int optionCount}) =>
      _log('options_completed', {'option_count': optionCount});

  @override
  Future<void> logCriteriaCompleted({
    required int criterionCount,
    required int aiSuggestedCount,
  }) =>
      _log('criteria_completed', {
        'criterion_count': criterionCount,
        'ai_suggested_count': aiSuggestedCount,
      });

  @override
  Future<void> logCriterionSuggestionAccepted({required String origin}) =>
      _log('criterion_suggestion_accepted', {'origin': origin});

  @override
  Future<void> logScoringCompleted() => _log('scoring_completed');

  @override
  Future<void> logResultViewed() => _log('result_viewed');

  @override
  Future<void> logAnalysisRequested({required String tier}) =>
      _log('analysis_requested', {'tier': tier});

  @override
  Future<void> logAnalysisCompleted({
    required String tier,
    required int latencyMs,
    required bool cached,
  }) =>
      _log('analysis_completed', {
        'tier': tier,
        'latency_ms': latencyMs,
        'cached': cached ? 1 : 0,
      });

  @override
  Future<void> logAnalysisFeedback({required bool thumbsUp}) =>
      _log('analysis_feedback', {'thumbs': thumbsUp ? 'up' : 'down'});

  @override
  Future<void> logResultShared({
    required String channel,
    required String format,
  }) =>
      _log('result_shared', {'channel': channel, 'format': format});

  @override
  Future<void> logPaywallViewed({required String source}) =>
      _log('paywall_viewed', {'source': source});

  @override
  Future<void> setUserProperties({String? plan, int? decisionsTotal}) async {
    if (plan != null) {
      await _analytics.setUserProperty(name: 'plan', value: plan);
    }
    if (decisionsTotal != null) {
      // Kovalanmış değer (PRD §10): kesin sayı değil segment.
      final bucket = decisionsTotal <= 2
          ? '1-2'
          : decisionsTotal <= 5
              ? '3-5'
              : '6+';
      await _analytics.setUserProperty(name: 'decisions_total', value: bucket);
    }
  }
}

/// Yerel mod / consent yok: tüm çağrılar sessiz.
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
  Future<void> setUserProperties({String? plan, int? decisionsTotal}) async {}
}

/// Seçim kuralı saf fonksiyon — testlenebilir (KVKK: consent şart).
bool analyticsEnabled(FirebaseStatus status, {required bool consent}) =>
    status == FirebaseStatus.ready && consent;

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final status = ref.watch(firebaseStatusProvider);
  final consent = ref.watch(analyticsConsentProvider);
  return analyticsEnabled(status, consent: consent)
      ? FirebaseAnalyticsService()
      : const NoopAnalyticsService();
});
