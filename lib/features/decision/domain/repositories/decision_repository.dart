import '../entities/decision.dart';

/// Karar deposu sözleşmesi — TEKNIK-MIMARI.md §4.1
/// Sprint 1: InMemoryDecisionRepository
/// Sprint 2: FirestoreDecisionRepository (aynı arayüz, offline persistence)
abstract interface class DecisionRepository {
  /// Tüm kararlar, updatedAt azalan. Abone olunca mevcut durum HEMEN gelir.
  Stream<List<Decision>> watchAll();

  /// Tek kararın canlı akışı (audit K-2): abone olunca mevcut durum hemen
  /// gelir; harici yazımlar (ikinci cihaz, Functions) emisyon üretir.
  /// Karar silinirse null yayımlanır.
  Stream<Decision?> watchById(String id);

  Future<Decision?> getById(String id);
  Future<void> upsert(Decision decision);
  Future<void> delete(String id);
}
