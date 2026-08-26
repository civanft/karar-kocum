import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/services/analytics/analytics_service.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

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

void main() {
  group('v1 production sözleşmesi (PR-STORE-2)', () {
    test('analytics v1\'de KAPALI (saf seam)', () {
      expect(analyticsEnabledInV1(), isFalse);
    });

    test('provider DAİMA Noop döner', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(analyticsServiceProvider),
        isA<NoopAnalyticsService>(),
      );
    });

    test('olay çağrıları hata üretmeden tamamlanır (platform kanalı YOK)',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(analyticsServiceProvider);

      await expectLater(
        Future.wait([
          service.logDecisionCreated(source: 'blank'),
          service.logOptionsCompleted(optionCount: 2),
          service.logScoringCompleted(),
          service.logResultViewed(),
          service.logAnalysisRequested(tier: 'basic'),
          service.logLegalLinkOpened(document: 'privacy'),
          service.setUserProperties(plan: 'free', decisionsTotal: 3),
        ]),
        completes,
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
