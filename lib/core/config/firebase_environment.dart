import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart' as dev;
import '../../firebase_options_prod.dart' as prod;

/// Uygulamanın bağlandığı Firebase ortamı (PR-PROD-2).
///
/// TEK KAYNAK: proje kimliği ve Functions bölgesi yalnız burada yazar.
/// Presentation/data katmanları sabit proje kimliği taşımaz; ortamı
/// [firebaseEnvironmentProvider] üzerinden okur, böylece testler override
/// edebilir.
enum FirebaseEnvironment {
  /// Debug ve profile build'leri — geliştirme projesi, mevcut bölge.
  development(
    projectId: 'karar-veriyorum-dev',
    functionsRegion: 'us-central1',
  ),

  /// Release build'leri — Store'a giden production projesi.
  ///
  /// Production Firestore `eur3` bölgesinde kurulacağı için Functions
  /// `europe-west1`'dedir; aynı kıtada kalmak gidiş-dönüş gecikmesini ve
  /// kıtalar arası çıkış trafiğini azaltır.
  production(
    projectId: 'karar-kocum-production',
    functionsRegion: 'europe-west1',
  );

  const FirebaseEnvironment({
    required this.projectId,
    required this.functionsRegion,
  });

  /// Firebase proje kimliği (public tanımlayıcı).
  final String projectId;

  /// Callable'ların çalıştığı bölge — istemci AYNI bölgeyi hedeflemelidir,
  /// aksi halde çağrı `not-found` ile döner.
  final String functionsRegion;

  /// Saf çözüm (test seam'i): yalnız build moduna bakar, yan etkisi yoktur.
  static FirebaseEnvironment resolve({required bool isReleaseMode}) =>
      isReleaseMode ? FirebaseEnvironment.production : development;

  /// Ortamın FlutterFire seçenekleri; platform çözümü FlutterFire'ındır.
  FirebaseOptions currentPlatformOptions() => switch (this) {
        FirebaseEnvironment.development =>
          dev.DefaultFirebaseOptions.currentPlatform,
        FirebaseEnvironment.production =>
          prod.DefaultFirebaseOptions.currentPlatform,
      };
}

/// Aktif ortam. Varsayılan `kReleaseMode`'a bağlıdır; testler override eder.
final firebaseEnvironmentProvider = Provider<FirebaseEnvironment>(
  (_) => FirebaseEnvironment.resolve(isReleaseMode: kReleaseMode),
);

/// Callable istemcilerinin kullanacağı bölge (türetilmiş seam).
final functionsRegionProvider = Provider<String>(
  (ref) => ref.watch(firebaseEnvironmentProvider).functionsRegion,
);
