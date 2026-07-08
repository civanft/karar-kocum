import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Açılışta FirebaseBootstrap sonucu ile override edilir (main.dart).
/// Varsayılan localMode: testler ve önizleme Firebase'siz çalışır.
final firebaseStatusProvider =
    Provider<FirebaseStatus>((_) => FirebaseStatus.localMode);

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
