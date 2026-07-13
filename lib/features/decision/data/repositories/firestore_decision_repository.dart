import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';
import '../dtos/decision_firestore_mapper.dart';

/// Firestore karar deposu — FIRESTORE-VERI-MODELI.md §2.
///
/// K-2 uyumu:
///  - watchAll/watchById: Firestore snapshot akışları (abonelikte anlık
///    değer SDK garantisi; offline cache + latency compensation dahil)
///  - applyPatch: yalnız değişen alanlar yazılır; updatedAt her yazımda
///    serverTimestamp (Y-4) — cihaz saatinden bağımsız sıralama
///  - upsert yalnız oluşturmada kullanılır (sözleşme notu arayüzde)
///
/// Emulator uyumluluğu: sınıf [FirebaseFirestore] örneğini dışarıdan alır;
/// bootstrap'ta `instance.useFirestoreEmulator(host, port)` çağrılması
/// yeterlidir — bu sınıfta özel durum yoktur.
class FirestoreDecisionRepository implements DecisionRepository {
  FirestoreDecisionRepository(this._firestore, {required String uid})
      : _uid = uid;

  final FirebaseFirestore _firestore;
  final String _uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _firestore.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> get _collection =>
      _userDoc.collection('decisions');

  @override
  Stream<List<Decision>> watchAll() {
    debugPrint('WATCHALL START UID=$_uid');

    return _collection
        .orderBy('updatedAt', descending: true)
        .snapshots(includeMetadataChanges: false)
        .map((query) {
      debugPrint('WATCHALL SNAPSHOT docs=${query.docs.length}');
      return [
        for (final doc in query.docs)
          DecisionFirestoreMapper.fromFirestore(doc),
      ];
    });
  }

  @override
  Stream<Decision?> watchById(String id) => _collection.doc(id).snapshots().map(
        (doc) => doc.exists ? DecisionFirestoreMapper.fromFirestore(doc) : null,
      );

  @override
  Future<Decision?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    return doc.exists ? DecisionFirestoreMapper.fromFirestore(doc) : null;
  }

  /// Oluşturma: karar + kullanıcı karar sayacı TEK BATCH'te (hotfix madde 5).
  /// Sayacı rules ±1 ile koruyor; cap kontrolü create rule'ında get() ile.
  /// Yeni belge değilse sayaç artırılmaz (idempotent — upsert oluşturma için).
  @override
  Future<void> upsert(Decision decision) async {
    final docRef = _collection.doc(decision.id);
    final exists = (await docRef.get()).exists;
    final batch = _firestore.batch()
      ..set(docRef, DecisionFirestoreMapper.toFirestore(decision, _uid));
    if (!exists) {
      final userExists = (await _userDoc.get()).exists;

      batch.set(
        _userDoc,
        {
          if (!userExists) 'plan': 'free',
          'decisionCount': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }
    debugPrint('UPSERT UID=$_uid');
    debugPrint('UPSERT DOC=${decision.id}');
    debugPrint('COMMIT START');

    try {
      await batch.commit();
      debugPrint('COMMIT OK');
    } catch (e) {
      debugPrint('COMMIT ERROR: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async {
    if (patch.isEmpty) return;
    try {
      await _collection
          .doc(id)
          .update(DecisionFirestoreMapper.patchToFirestore(patch));
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        throw StateError('Karar bulunamadı: $id');
      }
      rethrow;
    }
  }

  /// Silme: karar + sayaç azaltımı TEK BATCH'te. Belge yoksa sayaca dokunma.
  @override
  Future<void> delete(String id) async {
    final docRef = _collection.doc(id);
    final exists = (await docRef.get()).exists;
    if (!exists) return;
    await (_firestore.batch()
          ..delete(docRef)
          ..set(
            _userDoc,
            {'decisionCount': FieldValue.increment(-1)},
            SetOptions(merge: true),
          ))
        .commit();
  }
}
