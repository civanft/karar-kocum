import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_environment.dart';

/// PR-PROD-2 — Firebase ortam seçimi (saf sözleşme).
///
/// Firebase BAŞLATILMAZ: çözüm saf bir fonksiyona ayrıldığı için
/// `Firebase.initializeApp` olmadan test edilebilir. Yalnız PUBLIC
/// kimlikler (project id, bölge) doğrulanır; anahtar/config içeriği YOK.
void main() {
  group('FirebaseEnvironment.resolve', () {
    test('release build → production', () {
      expect(
        FirebaseEnvironment.resolve(isReleaseMode: true),
        FirebaseEnvironment.production,
      );
    });

    test('debug/profile build → development', () {
      expect(
        FirebaseEnvironment.resolve(isReleaseMode: false),
        FirebaseEnvironment.development,
      );
    });

    test('çözüm yalnız bayrağa bağlıdır (yan etkisiz)', () {
      expect(
        FirebaseEnvironment.resolve(isReleaseMode: true),
        FirebaseEnvironment.resolve(isReleaseMode: true),
      );
      expect(
        FirebaseEnvironment.resolve(isReleaseMode: false),
        isNot(FirebaseEnvironment.resolve(isReleaseMode: true)),
      );
    });
  });

  group('ortam kimlikleri', () {
    test('development → dev projesi ve us-central1', () {
      expect(
        FirebaseEnvironment.development.projectId,
        'karar-veriyorum-dev',
      );
      expect(
        FirebaseEnvironment.development.functionsRegion,
        'us-central1',
      );
    });

    test('production → production projesi ve europe-west1', () {
      expect(
        FirebaseEnvironment.production.projectId,
        'karar-kocum-production',
      );
      expect(
        FirebaseEnvironment.production.functionsRegion,
        'europe-west1',
      );
    });

    test('iki ortam farklı proje ve bölge kullanır', () {
      expect(
        FirebaseEnvironment.development.projectId,
        isNot(FirebaseEnvironment.production.projectId),
      );
      expect(
        FirebaseEnvironment.development.functionsRegion,
        isNot(FirebaseEnvironment.production.functionsRegion),
      );
    });
  });

  group('FlutterFire seçenekleri', () {
    test('her ortam kendi projesinin seçeneklerini döndürür', () {
      for (final env in FirebaseEnvironment.values) {
        expect(
          env.currentPlatformOptions().projectId,
          env.projectId,
          reason: '${env.name} yanlış projeye bağlı',
        );
      }
    });
  });

  group('provider seam', () {
    test('varsayılan provider çözümü override edilebilir', () {
      final container = ProviderContainer(
        overrides: [
          firebaseEnvironmentProvider
              .overrideWithValue(FirebaseEnvironment.production),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(firebaseEnvironmentProvider),
        FirebaseEnvironment.production,
      );
      expect(container.read(functionsRegionProvider), 'europe-west1');
    });

    test('development override → us-central1', () {
      final container = ProviderContainer(
        overrides: [
          firebaseEnvironmentProvider
              .overrideWithValue(FirebaseEnvironment.development),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(functionsRegionProvider), 'us-central1');
    });
  });
}
