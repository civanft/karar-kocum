import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/firestore_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';

/// Sprint B — "Kararımı Verdim": entity migration-güvenliği, mapper
/// gidiş-dönüşü, taahhüt/geri-alma patch'i.
void main() {
  final now = DateTime(2026, 7, 19, 12);

  Decision base({
    DecisionCommitStatus decisionStatus = DecisionCommitStatus.open,
    String? chosenOptionId,
    DateTime? decidedAt,
  }) =>
      Decision(
        id: 'd1',
        ownerUid: 'u1',
        title: 'Telefon seçimi',
        options: const [
          Option(id: 'a', title: 'iPhone'),
          Option(id: 'b', title: 'Samsung'),
        ],
        criteria: const [Criterion(id: 'c1', name: 'Fiyat', weight: 8)],
        decisionStatus: decisionStatus,
        chosenOptionId: chosenOptionId,
        decidedAt: decidedAt,
        createdAt: now,
        updatedAt: now,
      );

  group('migration güvenliği (eski belge bozulmaz)', () {
    test(
        'decisionStatus/chosenOptionId/decidedAt alanları OLMAYAN JSON '
        'okunabilir → open/null varsayılanları', () {
      // Sprint A öncesi bir belgenin şekli (yeni alanlar yok).
      final legacyJson = {
        'id': 'old1',
        'ownerUid': 'u1',
        'title': 'Eski karar',
        'options': [
          {'id': 'a', 'title': 'A'},
          {'id': 'b', 'title': 'B'},
        ],
        'criteria': <dynamic>[],
        'scores': <String, dynamic>{},
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final decision = Decision.fromJson(legacyJson);
      expect(decision.decisionStatus, DecisionCommitStatus.open);
      expect(decision.chosenOptionId, isNull);
      expect(decision.decidedAt, isNull);
      expect(decision.isDecided, isFalse);
    });

    test('yeni alanlar dolu JSON okunur', () {
      final json = {
        'id': 'd1',
        'ownerUid': 'u1',
        'title': 'Karar',
        'options': <dynamic>[],
        'criteria': <dynamic>[],
        'scores': <String, dynamic>{},
        'decisionStatus': 'decided',
        'chosenOptionId': 'a',
        'decidedAt': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final decision = Decision.fromJson(json);
      expect(decision.isDecided, isTrue);
      expect(decision.chosenOptionId, 'a');
      expect(decision.decidedAt, now);
    });
  });

  group('mapper gidiş-dönüş (Firestore)', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreDecisionRepository repo;
    const uid = 'u1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FirestoreDecisionRepository(firestore, uid: uid);
    });

    test(
        'taahhüt patch\'i: decisionStatus/chosenOptionId/decidedAt yazılır '
        've geri okunur', () async {
      await repo.upsert(base());
      await repo.applyPatch(
        'd1',
        const DecisionPatch(
          decisionStatus: DecisionCommitStatus.decided,
          chosenOptionId: 'b',
        ),
      );

      final raw =
          await firestore.collection('users/$uid/decisions').doc('d1').get();
      expect(raw.data()!['decisionStatus'], 'decided');
      expect(raw.data()!['chosenOptionId'], 'b');
      expect(raw.data()!['decidedAt'], isA<Timestamp>()); // Y-4 serverTimestamp

      final read = await repo.getById('d1');
      expect(read!.isDecided, isTrue);
      expect(read.chosenOptionId, 'b');
      expect(read.decidedAt, isNotNull);
    });

    test('geri alma patch\'i: alanlar temizlenir (open + null)', () async {
      await repo.upsert(
        base(
          decisionStatus: DecisionCommitStatus.decided,
          chosenOptionId: 'a',
          decidedAt: now,
        ),
      );

      await repo.applyPatch(
        'd1',
        const DecisionPatch(decisionStatus: DecisionCommitStatus.open),
      );

      final read = await repo.getById('d1');
      expect(read!.decisionStatus, DecisionCommitStatus.open);
      expect(read.chosenOptionId, isNull);
      expect(read.decidedAt, isNull);
      // Diğer alanlar korundu:
      expect(read.title, 'Telefon seçimi');
      expect(read.options, hasLength(2));
    });
  });

  group('DecisionPatch.applyTo (in-memory)', () {
    test('decided: seçim + tarih set edilir', () {
      final result = const DecisionPatch(
        decisionStatus: DecisionCommitStatus.decided,
        chosenOptionId: 'a',
      ).applyTo(base());
      expect(result.isDecided, isTrue);
      expect(result.chosenOptionId, 'a');
      expect(result.decidedAt, isNotNull);
    });

    test('open: seçim temizlenir', () {
      final result = const DecisionPatch(
        decisionStatus: DecisionCommitStatus.open,
      ).applyTo(
        base(
          decisionStatus: DecisionCommitStatus.decided,
          chosenOptionId: 'a',
          decidedAt: now,
        ),
      );
      expect(result.isDecided, isFalse);
      expect(result.chosenOptionId, isNull);
      expect(result.decidedAt, isNull);
    });
  });
}
