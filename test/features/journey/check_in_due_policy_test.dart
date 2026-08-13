import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/journey/domain/check_in_due_policy.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_coordinator.dart';

/// SPRINT C-4 — Home koç kartı due politikası (saf domain).
void main() {
  const policy = CheckInDuePolicy();
  const delay = FollowUpCoordinator.followUpDelay; // tek kaynak: 7 gün
  final decidedAt = DateTime.utc(2026, 7, 1, 9);
  final dueAt = decidedAt.add(delay);

  Decision make({
    String id = 'd1',
    DecisionCommitStatus status = DecisionCommitStatus.decided,
    DateTime? decidedAt,
    DecisionCheckIn? checkInStatus,
  }) =>
      Decision(
        id: id,
        ownerUid: 'u1',
        title: 'Karar $id',
        decisionStatus: status,
        chosenOptionId: status == DecisionCommitStatus.decided ? 'a' : null,
        decidedAt: decidedAt,
        checkInStatus: checkInStatus,
        checkedInAt: checkInStatus != null ? decidedAt : null,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );

  test('1) karar verilmemiş → due değil', () {
    final d = make(status: DecisionCommitStatus.open, decidedAt: null);
    expect(policy.isDue(d, dueAt), isFalse);
  });

  test('2) decidedAt == null → due değil', () {
    final d = make(decidedAt: null);
    expect(policy.isDue(d, dueAt), isFalse);
    expect(policy.dueAt(d), isNull);
  });

  test('3) 6 gün 23:59:59 geçmiş → due değil', () {
    final d = make(decidedAt: decidedAt);
    final now = dueAt.subtract(const Duration(seconds: 1));
    expect(policy.isDue(d, now), isFalse);
  });

  test('4) tam 7 gün geçmiş → due', () {
    final d = make(decidedAt: decidedAt);
    expect(policy.isDue(d, dueAt), isTrue);
    expect(policy.dueAt(d), dueAt);
  });

  test('5) 7 günden fazla geçmiş → due', () {
    final d = make(decidedAt: decidedAt);
    final now = dueAt.add(const Duration(days: 3));
    expect(policy.isDue(d, now), isTrue);
  });

  test('6) check-in cevaplanmış → due değil', () {
    final d = make(decidedAt: decidedAt, checkInStatus: DecisionCheckIn.happy);
    expect(policy.isDue(d, dueAt.add(const Duration(days: 10))), isFalse);
  });

  test('7) karar geri alınmış (open) → due değil', () {
    final d = make(status: DecisionCommitStatus.open, decidedAt: null);
    expect(policy.isDue(d, dueAt), isFalse);
  });

  test('8) birden fazla due → en eski decidedAt önce', () {
    final eski = make(id: 'eski', decidedAt: DateTime.utc(2026, 6, 20, 9));
    final yeni = make(id: 'yeni', decidedAt: DateTime.utc(2026, 6, 25, 9));
    final now = DateTime.utc(2026, 7, 10, 9); // ikisi de due
    final result = policy.dueDecisions([yeni, eski], now);
    expect(result.map((d) => d.id).toList(), ['eski', 'yeni']);
  });

  test('9) aynı decidedAt → id ile deterministik sıralama', () {
    final b = make(id: 'b', decidedAt: decidedAt);
    final a = make(id: 'a', decidedAt: decidedAt);
    final c = make(id: 'c', decidedAt: decidedAt);
    final result = policy.dueDecisions([b, c, a], dueAt);
    expect(result.map((d) => d.id).toList(), ['a', 'b', 'c']);
  });

  test('due olmayanlar listeden ayıklanır', () {
    final due = make(id: 'due', decidedAt: decidedAt);
    final open = make(id: 'open', status: DecisionCommitStatus.open);
    final answered = make(
      id: 'answered',
      decidedAt: decidedAt,
      checkInStatus: DecisionCheckIn.neutral,
    );
    final result = policy.dueDecisions([due, open, answered], dueAt);
    expect(result.map((d) => d.id).toList(), ['due']);
  });
}
