import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../../core/services/id_generator.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../journey/data/follow_up_aware_decision_repository.dart';
import '../../../journey/presentation/providers/journey_providers.dart';
import '../../data/repositories/firestore_decision_repository.dart';
import '../../data/repositories/in_memory_decision_repository.dart';
import '../../data/repositories/unavailable_decision_repository.dart';
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
  final status = ref.watch(firebaseStatusProvider);
  // Stream henüz yayınlamadıysa senkron currentUser'a düşer (yarış koruması).
  final uid = ref.watch(resolvedUidProvider);
  final DecisionRepository base;
  if (status == FirebaseStatus.ready && uid != null) {
    base = FirestoreDecisionRepository(
      ref.watch(firestoreInstanceProvider),
      uid: uid,
    );
  } else if (status != FirebaseStatus.localMode) {
    // FAIL-CLOSED: unavailable VE "ready ama UID yok" — in-memory depo
    // kullanıcıya kalıcı sanacağı karar yazdırırdı.
    base = const UnavailableDecisionRepository();
  } else {
    final repo = InMemoryDecisionRepository();
    ref.onDispose(repo.dispose);
    base = repo;
  }
  // Sprint C.1: silinen kararın takip bildirimi deponun kendi davranışı
  // olarak iptal edilir — hiçbir silme yolu kancayı atlayamaz.
  return FollowUpAwareDecisionRepository(
    base,
    ref.watch(followUpCoordinatorProvider),
  );
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
/// Sahiplik kimliği.
///
/// `local-user` YALNIZ [FirebaseStatus.localMode]'da kullanılır. ready ya da
/// unavailable durumunda gerçek UID yoksa boş dize döner: sahte bir kimlikle
/// veri yazılmasını engeller (depolar zaten fail-closed davranır).
final currentUidProvider = Provider<String>((ref) {
  final uid = ref.watch(resolvedUidProvider);
  if (uid != null) return uid;
  return ref.watch(firebaseStatusProvider) == FirebaseStatus.localMode
      ? 'local-user'
      : '';
});

/// Ana ekran listesi.
final decisionListProvider = StreamProvider<List<Decision>>(
  (ref) => ref.watch(decisionRepositoryProvider).watchAll(),
);
