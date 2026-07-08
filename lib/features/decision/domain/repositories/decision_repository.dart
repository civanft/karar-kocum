import '../entities/decision.dart';

/// Karar deposu sözleşmesi — TEKNIK-MIMARI.md §4.1
/// Sprint 1: InMemoryDecisionRepository
/// Sprint 2: FirestoreDecisionRepository (aynı arayüz, offline persistence)
abstract interface class DecisionRepository {
  Stream<List<Decision>> watchAll();
  Future<Decision?> getById(String id);
  Future<void> upsert(Decision decision);
  Future<void> delete(String id);
}
