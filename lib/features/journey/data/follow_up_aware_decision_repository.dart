import '../../decision/domain/entities/decision.dart';
import '../../decision/domain/repositories/decision_repository.dart';
import '../domain/follow_up_coordinator.dart';

/// Silinen kararın takip bildirimini temizleyen sarmalayıcı (Sprint C.1).
///
/// NEDEN DECORATOR: iptali silme çağrısının YANINA koymak yerine deponun
/// önüne koyuyoruz — böylece ileride eklenecek herhangi bir silme yolu
/// (liste ekranı, toplu temizlik, hesap silme) kancayı atlayamaz. Bildirim
/// iptali unutulabilir bir adım olmaktan çıkıp deponun davranışı olur.
///
/// Diğer tüm çağrılar dokunulmadan iletilir.
class FollowUpAwareDecisionRepository implements DecisionRepository {
  FollowUpAwareDecisionRepository(this._inner, this._coordinator);

  final DecisionRepository _inner;
  final FollowUpCoordinator _coordinator;

  /// Sarmalanan asıl depo — hangi arka ucun seçildiğini doğrulamak isteyen
  /// testler için (sarmalayıcı somut tipi gizliyor).
  DecisionRepository get inner => _inner;

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _coordinator.onDeleted(id);
  }

  @override
  Stream<List<Decision>> watchAll() => _inner.watchAll();

  @override
  Stream<Decision?> watchById(String id) => _inner.watchById(id);

  @override
  Future<Decision?> getById(String id) => _inner.getById(id);

  @override
  Future<void> upsert(Decision decision) => _inner.upsert(decision);

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) =>
      _inner.applyPatch(id, patch);
}
