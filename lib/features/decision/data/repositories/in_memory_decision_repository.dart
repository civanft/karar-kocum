import 'dart:async';

import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';

/// Sprint 1 deposu: bellek içi, akış tabanlı.
/// Sprint 2'de FirestoreDecisionRepository aynı arayüzle yer değiştirir;
/// testlerde fake olarak yaşamaya devam eder.
class InMemoryDecisionRepository implements DecisionRepository {
  final Map<String, Decision> _store = {};
  final StreamController<List<Decision>> _controller =
      StreamController.broadcast();

  List<Decision> get _snapshot {
    final list = _store.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  void _emit() => _controller.add(_snapshot);

  @override
  Stream<List<Decision>> watchAll() async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<Decision?> getById(String id) async => _store[id];

  @override
  Future<void> upsert(Decision decision) async {
    _store[decision.id] = decision;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
    _emit();
  }

  void dispose() => _controller.close();
}
