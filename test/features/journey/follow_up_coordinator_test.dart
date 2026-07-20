import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_coordinator.dart';

/// SPRINT C.1 — bildirim politikası (saf birim, plugin'e inilmez).
void main() {
  late InMemoryFollowUpPreferences prefs;
  late RecordingFollowUpScheduler scheduler;
  late FollowUpCoordinator coordinator;

  // Sabit saat: +7 gün beklentisi belirleyici olsun.
  final now = DateTime.utc(2026, 7, 21, 9);

  setUp(() {
    prefs = InMemoryFollowUpPreferences();
    scheduler = RecordingFollowUpScheduler();
    coordinator = FollowUpCoordinator(
      preferences: prefs,
      scheduler: scheduler,
      clock: () => now,
    );
  });

  Future<void> promise({required bool optIn}) => coordinator.answerPromise(
        decisionId: 'd1',
        decisionTitle: 'Telefon kararı',
        optIn: optIn,
      );

  test('"Evet, sor" → tam +7 gün sonrasına planlanır', () async {
    await promise(optIn: true);

    expect(scheduler.scheduled['d1'], DateTime.utc(2026, 7, 28, 9));
    expect(await prefs.isOptedIn('d1'), isTrue);
  });

  test('"Şimdi değil" → planlanmaz, varsa iptal edilir', () async {
    await promise(optIn: true);
    await promise(optIn: false);

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains('d1'));
    expect(await prefs.isOptedIn('d1'), isFalse);
  });

  test('revert → bildirim iptal, ama TERCİH korunur', () async {
    await promise(optIn: true);
    await coordinator.onReverted('d1');

    expect(scheduler.scheduled, isEmpty);
    // Tercih duruyor ki tekrar karar verilince yeniden sorulmasın:
    expect(await prefs.isOptedIn('d1'), isTrue);
  });

  test('revert → yeniden taahhüt → vade YENİ taahhütten başlar', () async {
    await promise(optIn: true);
    await coordinator.onReverted('d1');

    // Kullanıcı 2 gün sonra tekrar karar veriyor:
    final later = now.add(const Duration(days: 2));
    final c2 = FollowUpCoordinator(
      preferences: prefs,
      scheduler: scheduler,
      clock: () => later,
    );
    await c2.onCommitted(decisionId: 'd1', decisionTitle: 'Telefon kararı');

    expect(scheduler.scheduled['d1'], later.add(const Duration(days: 7)));
  });

  test('söz verilmemiş kararda taahhüt bildirim planlamaz', () async {
    await coordinator.onCommitted(decisionId: 'd9', decisionTitle: 'X');

    expect(scheduler.scheduled, isEmpty);
  });

  test('silme → bildirim iptal + tercih temizlenir (yetim kayıt yok)',
      () async {
    await promise(optIn: true);
    await coordinator.onDeleted('d1');

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains('d1'));
    expect(await prefs.isOptedIn('d1'), isFalse);
  });

  test('aynı karar için yeniden planlama tek kayıt bırakır (idempotent)',
      () async {
    await promise(optIn: true);
    await promise(optIn: true);

    expect(scheduler.scheduled.length, 1);
  });

  test('bildirim kimliği karar kimliğinden kararlı ve pozitif türetilir', () {
    final a = LocalNotificationFollowUpScheduler.notificationIdFor('abc');
    expect(a, LocalNotificationFollowUpScheduler.notificationIdFor('abc'));
    expect(a, greaterThanOrEqualTo(0));
    expect(
      a,
      isNot(LocalNotificationFollowUpScheduler.notificationIdFor('abd')),
    );
  });
}
