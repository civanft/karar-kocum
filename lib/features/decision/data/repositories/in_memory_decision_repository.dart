import 'dart:async';

import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';

/// Sprint 1 deposu: bellek içi, akış tabanlı.
/// Sprint 2'de FirestoreDecisionRepository aynı arayüzle yer değiştirir;
/// bu sınıf testlerde fake olarak yaşamaya devam eder.
///
/// Akış sözleşmesi (audit O-3 düzeltmesi): her dinleyici, aboneliğin
/// kurulduğu anda mevcut durumu senkron alır — "ilk emisyon ile abonelik
/// arasındaki mutasyon kaybolur" yarış penceresi yoktur (onListen içinde
/// await yok; snapshot eklenir eklenmez değişiklik akışına abone olunur).
class InMemoryDecisionRepository implements DecisionRepository {
  final Map<String, Decision> _store = {};
  final StreamController<void> _changes = StreamController.broadcast();

  List<Decision> get _snapshot {
    final list = _store.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? changeSub;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        changeSub = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () async {
        await changeSub?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<Decision>> watchAll() => _watch(() => _snapshot);

  @override
  Stream<Decision?> watchById(String id) => _watch(() => _store[id]);

  @override
  Future<Decision?> getById(String id) async => _store[id];

  @override
  Future<void> upsert(Decision decision) async {
    _store[decision.id] = decision;
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
    _changes.add(null);
  }

  void dispose() => _changes.close();
}
