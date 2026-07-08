import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';
import 'timestamp_converter.dart';

/// Decision ↔ Firestore belge eşlemesi — FIRESTORE-VERI-MODELI.md §2 şeması.
/// Entity'nin JSON'u (json_serializable) temel alınır; tarih alanları
/// Timestamp'e, updatedAt yazımda serverTimestamp'e çevrilir (Y-4).
abstract final class DecisionFirestoreMapper {
  static const _dates = TimestampConverter();

  /// Sunucunun sahiplendiği, entity'de karşılığı olmayan/istemcinin
  /// yazamayacağı alanlar — okuma yönünde ayıklanır.
  static const _serverOnlyFields = {'latestAnalysisId'};

  static Decision fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = Map<String, dynamic>.from(snapshot.data()!);
    for (final field in _serverOnlyFields) {
      data.remove(field);
    }
    data.remove('searchTokens'); // türetilmiş alan, entity'de yok
    data['id'] = snapshot.id;
    data['createdAt'] = _dates.fromJson(data['createdAt']).toIso8601String();
    data['updatedAt'] = _dates.fromJson(data['updatedAt']).toIso8601String();
    return Decision.fromJson(data);
  }

  /// Tam belge yazımı (yalnız oluşturma — K-2).
  /// [ownerUid] parametresi entity'deki değeri EZER: rules Y-5 gereği
  /// belge sahibi her zaman yazan kullanıcıdır.
  static Map<String, dynamic> toFirestore(Decision decision, String ownerUid) {
    final json = decision.toJson()
      ..remove('id') // belge kimliği yol üzerinde
      ..['ownerUid'] = ownerUid
      ..['createdAt'] = _dates.toJson(decision.createdAt)
      ..['updatedAt'] = FieldValue.serverTimestamp()
      ..['searchTokens'] = searchTokens(decision.title);
    return json;
  }

  /// Alan bazlı güncelleme haritası (K-2): yalnız patch'te dolu alanlar.
  static Map<String, dynamic> patchToFirestore(DecisionPatch patch) {
    assert(!patch.isEmpty, 'Boş patch yazımı çağıran taraf engellemeli');
    return {
      if (patch.title != null) ...{
        'title': patch.title,
        'searchTokens': searchTokens(patch.title!),
      },
      if (patch.options != null)
        'options': [for (final o in patch.options!) o.toJson()],
      if (patch.criteria != null)
        'criteria': [for (final c in patch.criteria!) c.toJson()],
      if (patch.scores != null)
        'scores': {
          for (final e in patch.scores!.entries)
            e.key: {
              for (final cell in e.value.entries) cell.key: cell.value.toJson(),
            },
        },
      if (patch.isFavorite != null) 'isFavorite': patch.isFavorite,
      if (patch.status != null) 'status': patch.status!.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Başlıktan arama token'ları: küçük harf kelimeler, tekrarsız, ≤ 20.
  /// (FIRESTORE-VERI-MODELI.md §2 — prefix arama v1 kapsamı dışında.)
  static List<String> searchTokens(String title) {
    final words = title
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.length >= 2);
    return {...words}.take(20).toList();
  }
}
