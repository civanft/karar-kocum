import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../data/repositories/firestore_credits_repository.dart';
import '../../domain/repositories/credits_repository.dart';

/// Depo seçimi karar deposuyla aynı kural: Firebase hazır + oturum →
/// Firestore; aksi halde yerel sabit (uid select'i gereksiz yeniden
/// kurulumu önler — bkz. decision_providers'daki aynı desen).
final creditsRepositoryProvider = Provider<CreditsRepository>((ref) {
  final firebaseReady =
      ref.watch(firebaseStatusProvider) == FirebaseStatus.ready;
  final uid = ref.watch(authStateProvider.select((s) => s.valueOrNull?.uid));

  if (firebaseReady && uid != null) {
    return FirestoreCreditsRepository(
      ref.watch(firestoreInstanceProvider),
      uid: uid,
    );
  }
  return LocalCreditsRepository();
});

/// Kalan ücretsiz analiz kredisi — UI bunu izler (idle kartındaki sayaç,
/// kota kartı). Sunucu düşümü Firestore'a yansıdığı anda otomatik günceller.
final remainingCreditsProvider = StreamProvider<int>(
  (ref) => ref.watch(creditsRepositoryProvider).watchRemaining(),
);
