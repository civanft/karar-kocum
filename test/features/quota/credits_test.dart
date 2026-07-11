import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/features/auth/domain/entities/app_user.dart';
import 'package:karar_veriyorum/features/auth/presentation/providers/auth_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/quota/data/repositories/firestore_credits_repository.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/credits_repository.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';

import '../auth/repository_switch_test.dart' show FakeAuthRepository;

void main() {
  group('FirestoreCreditsRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreCreditsRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FirestoreCreditsRepository(firestore, uid: 'u1');
    });

    test('alan hiç yazılmamış (yeni kullanıcı) → başlangıç 5', () async {
      expect(await repo.watchRemaining().first, 5);
    });

    test('sunucu düşümü canlı yansır: 5 → 2', () async {
      final emissions = <int>[];
      final sub = repo.watchRemaining().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      // analyzeDecision transaction'ının yazımını simüle et (admin yolu):
      await firestore
          .collection('users')
          .doc('u1')
          .set({'freeAnalysisCredits': 2});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emissions.first, 5); // lazy-init görünümü
      expect(emissions.last, 2); // sunucu değeri
    });

    test('savunma: bozuk negatif veri asla negatif GÖSTERİLMEZ', () async {
      await firestore
          .collection('users')
          .doc('u1')
          .set({'freeAnalysisCredits': -3});
      expect(await repo.watchRemaining().first, 0);
    });

    test('sıfır kredi sıfır olarak okunur', () async {
      await firestore
          .collection('users')
          .doc('u1')
          .set({'freeAnalysisCredits': 0});
      expect(await repo.watchRemaining().first, 0);
    });

    test('7A: iki havuz TOPLANIR (free 2 + reward 3 = 5)', () async {
      await firestore
          .collection('users')
          .doc('u1')
          .set({'freeAnalysisCredits': 2, 'rewardCredits': 3});
      expect(await repo.watchRemaining().first, 5);
    });

    test('7A: free bitmiş, yalnız reward varsa o görünür', () async {
      await firestore
          .collection('users')
          .doc('u1')
          .set({'freeAnalysisCredits': 0, 'rewardCredits': 2});
      expect(await repo.watchRemaining().first, 2);
    });
  });

  group('provider seçimi ve akış', () {
    test('yerel mod → LocalCreditsRepository, değer 5', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(creditsRepositoryProvider),
        isA<LocalCreditsRepository>(),
      );
      expect(await container.read(remainingCreditsProvider.future), 5);
    });

    test('Firebase hazır + oturum → Firestore deposu', () async {
      const user = AppUser(uid: 'u1', isAnonymous: true);
      final container = ProviderContainer(
        overrides: [
          firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(user)),
          firestoreInstanceProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);

      expect(
        container.read(creditsRepositoryProvider),
        isA<FirestoreCreditsRepository>(),
      );
      expect(await container.read(remainingCreditsProvider.future), 5);
    });
  });
}
