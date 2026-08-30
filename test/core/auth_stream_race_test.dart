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
import 'package:karar_veriyorum/features/journey/data/follow_up_aware_decision_repository.dart';
import 'package:karar_veriyorum/features/quota/data/repositories/firestore_credits_repository.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/credits_repository.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';

/// PR-RELEASE-1A / P0-2 — auth stream yarışı.
///
/// Firebase HAZIR ve senkron `currentUser` geçerli olduğu hâlde
/// `authStateChanges` ilk değerini henüz yayınlamamışsa, depo seçimi
/// yerel/in-memory'ye düşüyordu: kullanıcı açılışın ilk anlarında kalıcı
/// sanacağı kararlar ve sahte kredi görürdü.
class SlowAuthRepository implements AuthRepository {
  SlowAuthRepository(this.user);
  final AppUser? user;

  /// Akış GECİKİR: ilk emisyon test süresince gelmez.
  @override
  Stream<AppUser?> authStateChanges() =>
      Stream<AppUser?>.periodic(const Duration(days: 1), (_) => user);

  @override
  AppUser? get currentUser => user;

  @override
  Future<AppUser> signInAnonymously() async => user!;

  @override
  Future<void> signOut() async {}
}

ProviderContainer readyWith(AppUser? user) {
  final c = ProviderContainer(
    overrides: [
      firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
      authRepositoryProvider.overrideWithValue(SlowAuthRepository(user)),
      firestoreInstanceProvider.overrideWithValue(FakeFirebaseFirestore()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Object inner(ProviderContainer c) =>
    (c.read(decisionRepositoryProvider) as FollowUpAwareDecisionRepository)
        .inner;

void main() {
  group('A. ready + currentUser var, stream henüz yayınlamadı', () {
    const user = AppUser(uid: 'anon-race', isAnonymous: true);

    test('karar deposu InMemory OLMAZ → Firestore seçilir', () {
      final c = readyWith(user);
      expect(inner(c), isNot(isA<InMemoryDecisionRepository>()));
      expect(inner(c), isA<FirestoreDecisionRepository>());
    });

    test('kredi deposu Local OLMAZ → Firestore seçilir', () {
      final c = readyWith(user);
      final repo = c.read(creditsRepositoryProvider);
      expect(repo, isNot(isA<LocalCreditsRepository>()));
      expect(repo, isA<FirestoreCreditsRepository>());
    });

    test('currentUidProvider GERÇEK uid döndürür', () {
      expect(readyWith(user).read(currentUidProvider), 'anon-race');
    });

    test('sözleşme tablosu: hiçbir durumda boş string dönmez', () {
      for (final c in [readyWith(user), readyWith(null)]) {
        expect(c.read(currentUidProvider), isNot(''));
      }
    });
  });

  group('B. ready + currentUser null, stream yayın yok', () {
    test('karar deposu InMemory OLMAZ, akış hata verir', () async {
      final c = readyWith(null);
      expect(inner(c), isNot(isA<InMemoryDecisionRepository>()));
      await expectLater(
        c.read(decisionRepositoryProvider).watchAll().first,
        throwsA(isA<Exception>()),
      );
    });

    test('kredi deposu Local OLMAZ, sahte kredi yayınlanmaz', () async {
      final c = readyWith(null);
      expect(
        c.read(creditsRepositoryProvider),
        isNot(isA<LocalCreditsRepository>()),
      );
      await expectLater(
        c.read(creditsRepositoryProvider).watchRemaining().first,
        throwsA(isA<Exception>()),
      );
    });

    // PR-P1-UID-1: boş string sentinel KALDIRILDI — eksik kimlik artık
    // tip düzeyinde null. isNot('local-user') zayıf bir kontroldü; '' de
    // geçerdi ve sahte bir kimlik olarak downstream'e sızabilirdi.
    test('currentUidProvider NULL döndürür (boş string sentinel yok)', () {
      expect(readyWith(null).read(currentUidProvider), isNull);
    });
  });

  group('C. unavailable', () {
    test('unavailable durumda currentUidProvider null döndürür', () {
      final c = ProviderContainer(
        overrides: [
          firebaseStatusProvider.overrideWithValue(FirebaseStatus.unavailable),
        ],
      );
      addTearDown(c.dispose);
      // isNot('local-user') zayıftı: boş string sentinel'i de geçerdi.
      expect(c.read(currentUidProvider), isNull);
    });
  });

  group('D. localMode', () {
    test('local-user YALNIZ burada kullanılır', () {
      final c = ProviderContainer(
        overrides: [
          firebaseStatusProvider.overrideWithValue(FirebaseStatus.localMode),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(currentUidProvider), 'local-user');
      expect(inner(c), isA<InMemoryDecisionRepository>());
      expect(c.read(creditsRepositoryProvider), isA<LocalCreditsRepository>());
    });
  });
}
