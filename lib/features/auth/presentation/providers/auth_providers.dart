import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final status = ref.watch(firebaseStatusProvider);
  return status == FirebaseStatus.ready
      ? FirebaseAuthRepository(fb.FirebaseAuth.instance)
      : const NoopAuthRepository();
});

/// Oturum akışı — anonim oturum bootstrap'ta açıldığı için Firebase hazırsa
/// bu akış pratikte hiç null kalmaz (ilk açılış çevrimdışı istisnası hariç).
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// UID çözümü — TEK MERKEZ (PR-RELEASE-1A).
///
/// Açılışta `authStateChanges` ilk değerini yayınlamadan önce kısa bir pencere
/// vardır. O pencerede stream'e bakıp "oturum yok" sonucuna varmak, Firebase
/// HAZIR olduğu hâlde yerel/in-memory depoya düşülmesine yol açıyordu.
/// Sıra: (1) stream'in yayınladığı UID, (2) senkron `currentUser` fallback.
/// Hiçbiri yoksa `null` — çağıran taraf fail-closed davranır.
final resolvedUidProvider = Provider<String?>((ref) {
  final streamed =
      ref.watch(authStateProvider.select((s) => s.valueOrNull?.uid));
  if (streamed != null) return streamed;
  return ref.watch(authRepositoryProvider).currentUser?.uid;
});
