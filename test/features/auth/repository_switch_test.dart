import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/features/auth/domain/entities/app_user.dart';
import 'package:karar_veriyorum/features/auth/domain/repositories/auth_repository.dart';
import 'package:karar_veriyorum/features/auth/presentation/providers/auth_providers.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/firestore_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';

/// Sabit kullanıcı yayımlayan sahte auth deposu.
/// (Public: credits_test.dart de kullanır.)
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.user);
  final AppUser? user;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(user);

  @override
  AppUser? get currentUser => user;

  @override
  Future<AppUser> signInAnonymously() async => user!;

  @override
  Future<AppUser> signInWithGoogle() async => user!;

  @override
  Future<AppUser> signInWithApple() async => user!;

  @override
  Future<void> signOut() async {}
}

void main() {
  test('yerel mod: in-memory depo ve local-user kimliği', () async {
    final container = ProviderContainer(); // varsayılan: localMode
    addTearDown(container.dispose);

    expect(
      container.read(decisionRepositoryProvider),
      isA<InMemoryDecisionRepository>(),
    );
    expect(container.read(currentUidProvider), 'local-user');
  });

  test('Firebase hazır + oturum → Firestore depo, auth uid (madde 10)',
      () async {
    const user = AppUser(uid: 'anon-1', isAnonymous: true);
    final container = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(user)),
        firestoreInstanceProvider.overrideWithValue(FakeFirebaseFirestore()),
      ],
    );
    addTearDown(container.dispose);

    // authStateProvider akışının ilk değeri gelsin:
    await container.read(authStateProvider.future);

    expect(
      container.read(decisionRepositoryProvider),
      isA<FirestoreDecisionRepository>(),
    );
    expect(container.read(currentUidProvider), 'anon-1');
  });

  test('Firebase hazır ama oturum yok → güvenli düşüş: in-memory', () async {
    final container = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(null)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    expect(
      container.read(decisionRepositoryProvider),
      isA<InMemoryDecisionRepository>(),
    );
  });
}
