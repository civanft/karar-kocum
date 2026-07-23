import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/data/dtos/decision_firestore_mapper.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/firestore_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';

/// SPRINT C.2 — Firestore eşlemesi ve MİGRATION GÜVENLİĞİ.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreDecisionRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FirestoreDecisionRepository(firestore, uid: 'u1');
  });

  DocumentReference<Map<String, dynamic>> doc(String id) =>
      firestore.collection('users').doc('u1').collection('decisions').doc(id);

  test('ESKİ karar (alan hiç yok) sorunsuz okunur — migration gerekmez',
      () async {
    // Sprint C.2 öncesi yazılmış bir belge: checkIn alanları YOK.
    await doc('eski').set({
      'ownerUid': 'u1',
      'title': 'Eski karar',
      'options': <dynamic>[],
      'criteria': <dynamic>[],
      'scores': <String, dynamic>{},
      'status': 'draft',
      'isFavorite': false,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    });

    final decision = await repo.getById('eski');

    expect(decision, isNotNull);
    expect(decision!.checkInStatus, isNull);
    expect(decision.checkedInAt, isNull);
    expect(decision.hasCheckedIn, isFalse);
    expect(decision.canCheckIn, isFalse); // karar verilmemiş
  });

  test('check-in patch ikiliyi TUTARLI yazar (status + zaman damgası)',
      () async {
    final map = DecisionFirestoreMapper.patchToFirestore(
      const DecisionPatch(checkInStatus: DecisionCheckIn.regret),
    );

    expect(map['checkInStatus'], 'regret');
    expect(map['checkedInAt'], isA<FieldValue>()); // Y-4: sunucu saati
  });

  test('check-in yazılıp geri okunur (Timestamp ↔ entity)', () async {
    await doc('d1').set({
      'ownerUid': 'u1',
      'title': 'Telefon kararı',
      'options': <dynamic>[],
      'criteria': <dynamic>[],
      'scores': <String, dynamic>{},
      'status': 'draft',
      'isFavorite': false,
      'decisionStatus': 'decided',
      'chosenOptionId': 'a',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
    });

    await repo.applyPatch(
      'd1',
      const DecisionPatch(checkInStatus: DecisionCheckIn.happy),
    );

    final decision = await repo.getById('d1');
    expect(decision!.checkInStatus, DecisionCheckIn.happy);
    expect(decision.checkedInAt, isNotNull);
    expect(decision.hasCheckedIn, isTrue);
    // Taahhüt alanları BOZULMADI:
    expect(decision.isDecided, isTrue);
    expect(decision.chosenOptionId, 'a');
  });

  test('check-in patch başka alanları EZMEZ (alan bazlı yazım)', () async {
    await doc('d2').set({
      'ownerUid': 'u1',
      'title': 'Korunacak başlık',
      'options': <dynamic>[],
      'criteria': <dynamic>[],
      'scores': <String, dynamic>{},
      'status': 'draft',
      'isFavorite': true,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
    });

    await repo.applyPatch(
      'd2',
      const DecisionPatch(checkInStatus: DecisionCheckIn.neutral),
    );

    final decision = await repo.getById('d2');
    expect(decision!.title, 'Korunacak başlık');
    expect(decision.isFavorite, isTrue);
  });

  test('bildirim TERCİHİ Firestore belgesine sızmaz', () async {
    final decision = Decision(
      id: 'd3',
      ownerUid: 'u1',
      title: 'Telefon kararı',
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
    );

    final map = DecisionFirestoreMapper.toFirestore(decision, 'u1');

    // Cihazda kalması gereken hiçbir şey belgeye yazılmamalı:
    expect(map.keys, isNot(contains('followUpOptedIn')));
    expect(map.keys, isNot(contains('notificationId')));
    expect(map.keys, isNot(contains('scheduledAt')));
  });
}
