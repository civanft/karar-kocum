import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/id_generator.dart';
import '../../data/repositories/in_memory_decision_repository.dart';
import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';
import '../../domain/usecases/compute_result.dart';
import '../../domain/usecases/create_decision.dart';

/// Arayüz → implementasyon bağlama noktası.
/// Sprint 2: override ile FirestoreDecisionRepository'ye geçilir.
final decisionRepositoryProvider = Provider<DecisionRepository>((ref) {
  final repo = InMemoryDecisionRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final idGeneratorProvider = Provider<IdGenerator>((_) => IdGenerator());

final createDecisionProvider = Provider<CreateDecision>(
  (ref) => CreateDecision(
    ref.watch(decisionRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final computeResultProvider = Provider<ComputeResult>(
  (_) => const ComputeResult(),
);

/// Sprint 2'de gerçek auth uid'e bağlanır; Sprint 1'de sabit yerel kimlik.
final currentUidProvider = Provider<String>((_) => 'local-user');

/// Ana ekran listesi.
final decisionListProvider = StreamProvider<List<Decision>>(
  (ref) => ref.watch(decisionRepositoryProvider).watchAll(),
);
