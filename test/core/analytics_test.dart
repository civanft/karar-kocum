import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/services/analytics/analytics_service.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:mocktail/mocktail.dart';

/// Olayları sayan sahte servis.
class RecordingAnalytics extends NoopAnalyticsService {
  final List<String> events = [];
  final Map<String, Object?> lastParams = {};

  @override
  Future<void> logOptionsCompleted({required int optionCount}) async {
    events.add('options_completed');
    lastParams['option_count'] = optionCount;
  }

  @override
  Future<void> logCriteriaCompleted({
    required int criterionCount,
    required int aiSuggestedCount,
  }) async {
    events.add('criteria_completed');
    lastParams['criterion_count'] = criterionCount;
  }

  @override
  Future<void> logScoringCompleted() async {
    events.add('scoring_completed');
  }
}

class MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  group('FirebaseAnalyticsService — olay adı ve parametre şeması', () {
    late MockFirebaseAnalytics mock;
    late FirebaseAnalyticsService service;
    final logged = <(String, Map<String, Object>?)>[];

    setUp(() {
      mock = MockFirebaseAnalytics();
      logged.clear();
      when(
        () => mock.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        ),
      ).thenAnswer((inv) async {
        logged.add(
          (
            inv.namedArguments[#name] as String,
            inv.namedArguments[#parameters] as Map<String, Object>?,
          ),
        );
      });
      when(
        () => mock.setUserProperty(
          name: any(named: 'name'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      service = FirebaseAnalyticsService(mock);
    });

    test('tüm huni ve AI olayları şemadaki adlarla loglanır', () async {
      await service.logDecisionCreated(source: 'template');
      await service.logOptionsCompleted(optionCount: 3);
      await service.logCriteriaCompleted(
        criterionCount: 2,
        aiSuggestedCount: 1,
      );
      await service.logScoringCompleted();
      await service.logResultViewed();
      await service.logAnalysisRequested(tier: 'basic');
      await service.logAnalysisCompleted(
        tier: 'basic',
        latencyMs: 4200,
        cached: true,
      );
      await service.logAnalysisFeedback(thumbsUp: true);
      await service.logResultShared(channel: 'whatsapp', format: 'card');
      await service.logPaywallViewed(source: 'quota');

      expect(logged.map((e) => e.$1), [
        'decision_created',
        'options_completed',
        'criteria_completed',
        'scoring_completed',
        'result_viewed',
        'analysis_requested',
        'analysis_completed',
        'analysis_feedback',
        'result_shared',
        'paywall_viewed',
      ]);
      // İçerik/PII taşınmadığının nokta kontrolü:
      expect(logged[6].$2, {'tier': 'basic', 'latency_ms': 4200, 'cached': 1});
      expect(logged[7].$2, {'thumbs': 'up'});
    });

    test('decisions_total kovalanır (kesin sayı sızmaz)', () async {
      await service.setUserProperties(plan: 'premium', decisionsTotal: 4);
      verify(
        () => mock.setUserProperty(name: 'plan', value: 'premium'),
      ).called(1);
      verify(
        () => mock.setUserProperty(name: 'decisions_total', value: '3-5'),
      ).called(1);
    });
  });

  group('analyticsEnabled (KVKK kapısı)', () {
    test('yalnız Firebase hazır + consent TRUE iken açık', () {
      expect(
        analyticsEnabled(FirebaseStatus.ready, consent: true),
        isTrue,
      );
      expect(
        analyticsEnabled(FirebaseStatus.ready, consent: false),
        isFalse,
      );
      expect(
        analyticsEnabled(FirebaseStatus.localMode, consent: true),
        isFalse,
      );
    });

    test('varsayılan provider: consent kapalı → Noop (opt-in)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(analyticsServiceProvider),
        isA<NoopAnalyticsService>(),
      );
    });
  });

  group('aktivasyon hunisi — editor eşik geçişleri', () {
    late RecordingAnalytics analytics;
    late InMemoryDecisionRepository repo;
    late ProviderContainer container;

    setUp(() async {
      analytics = RecordingAnalytics();
      repo = InMemoryDecisionRepository();
      await repo.upsert(
        Decision(
          id: 'd1',
          ownerUid: 'u',
          title: 'Test kararı',
          createdAt: DateTime(2026, 7, 8),
          updatedAt: DateTime(2026, 7, 8),
        ),
      );
      container = ProviderContainer(
        overrides: [
          decisionRepositoryProvider.overrideWithValue(repo),
          analyticsServiceProvider.overrideWithValue(analytics),
          autosaveDebounceProvider
              .overrideWithValue(const Duration(minutes: 1)),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(repo.dispose);
      final sub = container.listen(decisionEditorProvider('d1'), (_, __) {});
      addTearDown(sub.close);
      await container.read(decisionEditorProvider('d1').future);
    });

    DecisionEditor editor() =>
        container.read(decisionEditorProvider('d1').notifier);

    test('2. seçenekte options_completed TEK KEZ ateşlenir', () async {
      final e = editor();
      await e.addOption('A');
      expect(analytics.events, isEmpty); // henüz eşik geçilmedi

      await e.addOption('B');
      expect(analytics.events, ['options_completed']);
      expect(analytics.lastParams['option_count'], 2);

      await e.addOption('C'); // eşik zaten geçildi — yeniden ateşlenmez
      expect(
        analytics.events.where((e) => e == 'options_completed'),
        hasLength(1),
      );
    });

    test('ilk kriterde criteria_completed ateşlenir', () async {
      final e = editor();
      await e.addCriterion('Fiyat', 5);
      expect(analytics.events, contains('criteria_completed'));
      expect(analytics.lastParams['criterion_count'], 1);
    });

    test('matris tamamlanınca scoring_completed (debounce yolundan)', () async {
      final e = editor();
      await e.addOption('A');
      await e.addOption('B');
      await e.addCriterion('Fiyat', 5);
      analytics.events.clear();

      final d = container.read(decisionEditorProvider('d1')).requireValue;
      e.setScore(d.options[0].id, d.criteria.single.id, 7);
      expect(analytics.events, isEmpty); // matris hâlâ eksik

      e.setScore(d.options[1].id, d.criteria.single.id, 4);
      expect(analytics.events, ['scoring_completed']); // geçiş anı

      e.setScore(d.options[1].id, d.criteria.single.id, 9);
      expect(analytics.events, hasLength(1)); // tamamken tekrar ateşlenmez
    });
  });
}
