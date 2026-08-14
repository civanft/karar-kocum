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

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _firestore.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> get _collection =>
      _userDoc.collection('decisions');

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

  /// CREATE-ONLY oluşturma (latency fix): karar + kullanıcı sayacı TEK
  /// BATCH'te, varlık ÖN-OKUMASI YOK — "Devam Et" artık tek sunucu turu.
  ///
  /// Sözleşme: tek çağıran CreateDecision her seferinde TAZE id üretir;
  /// bu yüzden decision-belgesi exists kontrolü gereksizdi (eski hâli
  /// 3 ardışık tura mal oluyordu — uzun spinner'ın kök nedeni).
  ///
  /// plan:'free' YALNIZ user belgesinin varlığı bilinmiyorken gönderilir
  /// (repo-örneği başına en fazla 1 okuma, sonrası önbellekli):
  ///  - belge yoksa create kuralı plan'ı zorunlu kılar → gönderilir
  ///  - belge varsa plan GÖNDERİLMEZ → premium planı ezme/rules
  ///    plan-diff reddi imkânsız (testli: PREMIUM GÜVENLİĞİ)
  bool _userDocKnownToExist = false;

  @override
  Future<void> upsert(Decision decision) async {
    final batch = _firestore.batch()
      ..set(
        _collection.doc(decision.id),
        DecisionFirestoreMapper.toFirestore(decision, _uid),
      );

    var includePlan = false;
    if (!_userDocKnownToExist) {
      // Oturum başına tek tur: sonraki create'ler 1 RTT'ye iner.
      includePlan = !(await _userDoc.get()).exists;
    }
    batch.set(
      _userDoc,
      {
        if (includePlan) 'plan': 'free',
        'decisionCount': FieldValue.increment(1),
        // SECURITY: sayaç mutasyonunu bu batch'teki gerçek karar
        // create'ine bağlayan eşleme alanı — rules doğrular.
        'decisionCountMutationId': decision.id,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    _userDocKnownToExist = true; // commit user belgesini garantiledi
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
            {
              'decisionCount': FieldValue.increment(-1),
              // SECURITY: azaltımı bu batch'teki gerçek silmeye bağlar.
              'decisionCountMutationId': id,
            },
            SetOptions(merge: true),
          ))
        .commit();
  }
}
