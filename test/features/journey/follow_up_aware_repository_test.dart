import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/journey/data/follow_up_aware_decision_repository.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_coordinator.dart';

/// SPRINT C.1 — silme kancası deponun DAVRANIŞI mı? (decorator sözleşmesi)
void main() {
  late InMemoryDecisionRepository inner;
  late RecordingFollowUpScheduler scheduler;
  late InMemoryFollowUpPreferences prefs;
  late FollowUpAwareDecisionRepository repo;

  setUp(() {
    inner = InMemoryDecisionRepository();
    addTearDown(inner.dispose);
    scheduler = RecordingFollowUpScheduler();
    prefs = InMemoryFollowUpPreferences();
    repo = FollowUpAwareDecisionRepository(
      inner,
      FollowUpCoordinator(preferences: prefs, scheduler: scheduler),
    );
  });

  Decision sample(String id) => Decision(
        id: id,
        ownerUid: 'u1',
        title: 'Telefon kararı',
        createdAt: DateTime.utc(2026, 7, 21),
        updatedAt: DateTime.utc(2026, 7, 21),
      );

  test('delete → karar silinir VE bildirim iptal edilir', () async {
    await repo.upsert(sample('d1'));
    await prefs.setOptedIn('d1', value: true);
    await scheduler.schedule(
      decisionId: 'd1',
      decisionTitle: 'Telefon kararı',
      at: DateTime.utc(2026, 7, 28),
    );

    await repo.delete('d1');

    expect(await repo.getById('d1'), isNull);
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains('d1'));
    expect(await prefs.isOptedIn('d1'), isFalse);
  });

  test('planı olmayan kararın silinmesi patlamaz', () async {
    await repo.upsert(sample('d2'));
    await repo.delete('d2');

    expect(await repo.getById('d2'), isNull);
  });

  test('diğer çağrılar iç depoya olduğu gibi iletilir', () async {
    await repo.upsert(sample('d3'));

    expect((await repo.getById('d3'))?.title, 'Telefon kararı');
    await repo.applyPatch('d3', const DecisionPatch(title: 'Yeni başlık'));
    expect((await repo.getById('d3'))?.title, 'Yeni başlık');
    expect(await repo.watchAll().first, hasLength(1));
    expect((await repo.watchById('d3').first)?.id, 'd3');
    // Bunların hiçbiri bildirim tarafına dokunmamalı:
    expect(scheduler.cancelled, isEmpty);
  });
}
