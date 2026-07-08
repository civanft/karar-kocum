import 'package:cloud_firestore/cloud_firestore.dart';

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

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('users').doc(_uid).collection('decisions');

  @override
  Stream<List<Decision>> watchAll() => _collection
      .orderBy('updatedAt', descending: true)
      .snapshots(includeMetadataChanges: false)
      .map(
        (query) => [
          for (final doc in query.docs)
            DecisionFirestoreMapper.fromFirestore(doc),
        ],
      );

  @override
  Stream<Decision?> watchById(String id) => _collection.doc(id).snapshots().map(
        (doc) => doc.exists ? DecisionFirestoreMapper.fromFirestore(doc) : null,
      );

  @override
  Future<Decision?> getById(String id) async {
    final doc = await _collection.doc(id).get();
    return doc.exists ? DecisionFirestoreMapper.fromFirestore(doc) : null;
  }

  @override
  Future<void> upsert(Decision decision) => _collection
      .doc(decision.id)
      .set(DecisionFirestoreMapper.toFirestore(decision, _uid));

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

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();
}
