// Platform sahteleri, ağ olmadan gerçek bootstrap'i çalıştırır.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_app_check_platform_interface/firebase_app_check_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';

class _Core extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [];
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async =>
      CoreInitializeResponse(
        name: appName,
        options: initializeAppRequest,
        pluginConstants: {},
      );
}

/// `activate()` YALNIZ provider fabrikasını kurar; gerçek attestation'ı
/// KANITLAMAZ. Sahte bunu bilerek modeller: sayaç kurulum denemesini sayar.
class _AppCheck extends FirebaseAppCheckPlatform {
  _AppCheck() : super(appInstance: null);

  /// Bir sonraki kurulum denemesi başarısız olsun.
  bool failNextInstall = false;
  int installAttempts = 0;
  AndroidProvider? lastAndroidProvider;
  AppleProvider? lastAppleProvider;

  void reset() {
    failNextInstall = false;
    installAttempts = 0;
    lastAndroidProvider = null;
    lastAppleProvider = null;
  }

  @override
  FirebaseAppCheckPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAppCheckPlatform setInitialValues() => this;

  @override
  Future<void> activate({
    WebProvider? webProvider,
    AndroidProvider? androidProvider,
    AppleProvider? appleProvider,
  }) async {
    installAttempts++;
    lastAndroidProvider = androidProvider;
    lastAppleProvider = appleProvider;
    if (failNextInstall) {
      failNextInstall = false;
      throw Exception('provider kurulumu geçici olarak başarısız');
    }
  }
}

class _Auth extends FirebaseAuthPlatform {
  /// Bu denemede oturum açma ASILI kalır (Future asla dönmez).
  int? hangOnAttempt;
  int attempts = 0;
  final List<Completer<void>> gates = [];

  void reset() {
    hangOnAttempt = null;
    attempts = 0;
    gates.clear();
  }

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;
  @override
  UserPlatform? get currentUser => null;

  @override
  Future<UserCredentialPlatform> signInAnonymously() async {
    attempts++;
    if (attempts == hangOnAttempt) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    // Akış auth sınırında biter; bu testlerin ilgisi buraya KADAR olan sıra.
    throw Exception('test auth sınırında biter');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Platform sahteleri YALNIZ BİR KEZ kurulur: `FirebaseAppCheck.instance`
  // ve `FirebaseAuth.instance` delegelerini ilk erişimde ÖNBELLEĞE ALIR,
  // bu yüzden test başına yeni nesne atamak sessizce etkisiz kalırdı.
  final check = _AppCheck();
  final auth = _Auth();

  setUpAll(() {
    TestFirebaseCoreHostApi.setUp(_Core());
    FirebaseAppCheckPlatform.instance = check;
    FirebaseAuthPlatform.instance = auth;
  });

  setUp(() {
    // SIRA BAĞIMSIZLIĞI: statik ve sahte durum her testten önce sıfırlanır.
    FirebaseBootstrap.resetForTest();
    check.reset();
    auth.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    FirebaseBootstrap.resetForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  group('App Check provider kurulumu', () {
    test('kurulum başarısızsa auth akışına GİRİLMEZ', () async {
      check.failNextInstall = true;
      await FirebaseBootstrap.ensureInitialized();

      expect(check.installAttempts, 1);
      expect(
        auth.attempts,
        0,
        reason: 'kurulum başarısızken hazır/auth akışına geçilmemeli',
      );
      expect(Firebase.apps, isNotEmpty);
    });

    test('başarısız kurulum, Firebase app ZATEN VARKEN retry\'da tekrarlanır',
        () async {
      check.failNextInstall = true;
      await FirebaseBootstrap.ensureInitialized();
      expect(check.installAttempts, 1);

      await FirebaseBootstrap.ensureInitialized();
      expect(
        check.installAttempts,
        2,
        reason: 'retry, eksik kalan kurulumu tamamlamalı',
      );
      expect(auth.attempts, 1);
    });

    test('BAŞARILI kurulum gereksiz yere tekrarlanmaz', () async {
      await FirebaseBootstrap.ensureInitialized();
      await FirebaseBootstrap.ensureInitialized();

      expect(check.installAttempts, 1, reason: 'kurulum idempotent olmalı');
      expect(auth.attempts, 2, reason: 'yalnız eksik olan oturum tekrarlanır');
    });

    test('release sağlayıcıları debug sağlayıcısına DÜŞMEZ', () async {
      await FirebaseBootstrap.ensureInitialized();

      // Kurulumda GERÇEKTEN saf seçicilerin sonucu kullanılmış olmalı.
      expect(
        check.lastAndroidProvider,
        androidAppCheckProviderFor(isDebug: kDebugMode),
      );
      expect(
        check.lastAppleProvider,
        appleAppCheckProviderFor(isDebug: kDebugMode),
      );
      // RELEASE dalı testte çalıştırılamaz; saf seçici üzerinden sabitlenir.
      // Debug sağlayıcısının release'e sızması tam olarak budur.
      final releaseAndroid = androidAppCheckProviderFor(isDebug: false);
      final releaseApple = appleAppCheckProviderFor(isDebug: false);
      expect(releaseAndroid, AndroidProvider.playIntegrity);
      expect(releaseAndroid, isNot(AndroidProvider.debug));
      expect(releaseApple, AppleProvider.appAttestWithDeviceCheckFallback);
      expect(releaseApple, isNot(AppleProvider.debug));
      // Debug dalı da korunur: debug'da debug sağlayıcısı beklenir.
      expect(androidAppCheckProviderFor(isDebug: true), AndroidProvider.debug);
      expect(appleAppCheckProviderFor(isDebug: true), AppleProvider.debug);
    });
  });

  group('asılı başlatma retry\'ları ZEHİRLEMEZ', () {
    test('asılı SDK\'da ensureInitialized SINIR içinde döner', () async {
      auth.hangOnAttempt = 1;
      final status = await FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 20),
      ).timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('ensureInitialized başlatmayı SINIRLAMADI'),
      );
      expect(status, firebaseFailureStatus(isReleaseMode: kReleaseMode));
    });

    test('zaman aşımından sonra YENİ bir deneme başlatılabilir', () async {
      auth.hangOnAttempt = 1;
      await FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 20),
      );
      expect(auth.attempts, 1);

      // Asılı deneme artık paylaşılmıyor: bu çağrı YENİ bir deneme başlatır.
      await FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 20),
      );
      expect(
        auth.attempts,
        2,
        reason: 'asılı future sonraki retry\'ları kalıcı olarak zehirlememeli',
      );
    });

    test('EŞ ZAMANLI çağrılar tek başlatmada birleşir', () async {
      auth.hangOnAttempt = 1;
      final a = FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 40),
      );
      final b = FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 40),
      );
      await Future.wait([a, b]);

      expect(auth.attempts, 1, reason: 'iki çağrı tek denemeyi paylaşmalı');
      expect(check.installAttempts, 1);
    });

    test('GEÇ tamamlanan eski deneme, yeni denemeyi bozmaz', () async {
      auth.hangOnAttempt = 1;
      await FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 20),
      );
      expect(auth.attempts, 1);

      // 2. deneme başlar ve o da asılı kalır (hangOnAttempt yalnız 1'di,
      // bu yüzden 2. deneme auth sınırında hata ile biter) — ardından
      // eski deneme GEÇ tamamlanır.
      final second = FirebaseBootstrap.ensureInitialized(
        timeout: const Duration(milliseconds: 40),
      );
      auth.gates.single.complete(); // eski, zaman aşımına uğramış deneme biter
      await second;

      expect(auth.attempts, 2);
      // Eski denemenin geç tamamlanması yeni durumu ezmemeli: bir sonraki
      // çağrı normal biçimde yeni bir deneme başlatabilmeli.
      await FirebaseBootstrap.ensureInitialized();
      expect(auth.attempts, 3);
    });
  });

  group('test seam\'i', () {
    test('resetForTest statik durumu gerçekten sıfırlar', () async {
      await FirebaseBootstrap.ensureInitialized();
      expect(check.installAttempts, 1);

      FirebaseBootstrap.resetForTest();
      check.reset();
      await FirebaseBootstrap.ensureInitialized();

      expect(
        check.installAttempts,
        1,
        reason: 'sıfırlamadan sonra kurulum YENİDEN yapılmalı',
      );
    });
  });
}
