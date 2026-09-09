import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../data/firestore_ai_consent_repository.dart';
import '../../domain/entities/ai_consent.dart';
import '../../domain/repositories/ai_consent_repository.dart';

/// İzin deposu bağlama noktası — FAIL CLOSED.
///
/// Firebase hazır değilse ya da oturum yoksa Firestore yolu KURULMAZ ve
/// izin "yok" sayılır. Yerel modda AI aktarımı zaten mock'tur.
final aiConsentRepositoryProvider = Provider<AiConsentRepository>((ref) {
  final status = ref.watch(firebaseStatusProvider);
  final uid = ref.watch(currentUidProvider);
  if (status != FirebaseStatus.ready || uid == null) {
    return const UnavailableAiConsentRepository();
  }
  return FirestoreAiConsentRepository(
    firestore: FirebaseFirestore.instance,
    uid: uid,
  );
});

/// Canlı izin kaydı (`null` = hiç sorulmadı).
final aiConsentProvider = StreamProvider<AiConsent?>(
  (ref) => ref.watch(aiConsentRepositoryProvider).watch(),
);

/// AKTARIM KAPISI — tek doğruluk kaynağı.
///
/// FAIL CLOSED: yalnız yüklenmiş VE güncel sürümü karşılayan bir onay
/// `true` döner. Yükleniyor, hata ve kayıt yok durumlarının hepsi `false`
/// — "okuyamadım" asla "izin var" demek değildir.
final aiTransferAllowedProvider = Provider<bool>((ref) {
  final consent = ref.watch(aiConsentProvider);
  return consent.maybeWhen(
    data: (value) => value?.isSatisfied ?? false,
    orElse: () => false,
  );
});
