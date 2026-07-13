import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../../core/services/id_generator.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/firestore_decision_repository.dart';
import '../../data/repositories/in_memory_decision_repository.dart';
import '../../domain/entities/decision.dart';
import '../../domain/repositories/decision_repository.dart';
import '../../domain/usecases/compute_result.dart';
import '../../domain/usecases/create_decision.dart';

/// Arayüz → implementasyon bağlama noktası (Sprint 2):
/// Firebase hazır + oturum açık → Firestore; aksi halde in-memory yerel mod.
///
/// NOT: Yerel moddan Firestore'a geçişte in-memory veri TAŞINMAZ —
/// bootstrap anonim oturumu açılışta kurduğundan bu geçiş normal akışta
/// yaşanmaz (yalnız ilk açılış çevrimdışıysa); taşıma Sprint 4 kapsamında.
/// Test edilebilirlik: testlerde FakeFirebaseFirestore ile override edilir.
final firestoreInstanceProvider =
    Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);

final decisionRepositoryProvider = Provider<DecisionRepository>((ref) {
  final firebaseReady =
      ref.watch(firebaseStatusProvider) == FirebaseStatus.ready;
  // select: yalnız uid DEĞİŞİNCE yeniden kur — AsyncLoading→AsyncData
  // geçişi repo'yu boşuna yeniden yaratıp in-memory veriyi düşürmesin.
  final uid = ref.watch(authStateProvider.select((s) => s.valueOrNull?.uid));
  debugPrint('REPO firebaseReady=$firebaseReady uid=$uid');
  if (firebaseReady && uid != null) {
    return FirestoreDecisionRepository(
      ref.watch(firestoreInstanceProvider),
      uid: uid,
    );
  }
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

/// Oturum uid'i; yerel modda sabit kimlik.
final currentUidProvider = Provider<String>(
  (ref) =>
      ref.watch(authStateProvider.select((s) => s.valueOrNull?.uid)) ??
      'local-user',
);

/// Ana ekran listesi.
final decisionListProvider = StreamProvider<List<Decision>>(
  (ref) => ref.watch(decisionRepositoryProvider).watchAll(),
);
