import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_environment.dart';

/// Açılışta FirebaseBootstrap sonucu ile override edilir (main.dart).
/// Varsayılan localMode: testler ve önizleme Firebase'siz çalışır.
/// (Core'da yaşar: hem auth hem analytics hem data katmanı bunu izler.)
final firebaseStatusProvider =
    Provider<FirebaseStatus>((_) => FirebaseStatus.localMode);

/// Firebase başlatma sonucu — provider ağacına override ile enjekte edilir.
enum FirebaseStatus {
  /// Firebase hazır; Firestore + Auth kullanılabilir.
  ready,

  /// Yapılandırma placeholder ya da başlatma hatası — uygulama YEREL MODDA
  /// çalışır (in-memory depo, kimliksiz). Geliştirme ve CI için normaldir.
  localMode,
}

/// Uygulama açılışında Firebase'i dener; başarısızlık ÇÖKME DEĞİLDİR.
/// Splash bütçesi (mimari §13): burada yalnız init + anonim oturum var,
/// Remote Config/Analytics sonraki sprintlerde eklenirken de bekletilmez.
abstract final class FirebaseBootstrap {
  static Future<FirebaseStatus> tryInitialize() async {
    final FirebaseOptions options;
    try {
      // Ortam seçimi merkezidir (release → production, debug/profile → dev).
      // flutterfire'ın ürettiği dosya, kayıtlı olmayan platformda
      // (ör. web önizlemesi) UnsupportedError fırlatır — çökme değil,
      // yerel mod nedeni.
      options = FirebaseEnvironment.resolve(isReleaseMode: kReleaseMode)
          .currentPlatformOptions();
    } on UnsupportedError catch (e) {
      debugPrint('FirebaseBootstrap: platform yapılandırması yok — '
          'yerel mod. $e');
      return FirebaseStatus.localMode;
    }

    try {
      await Firebase.initializeApp(options: options);
      await _activateAppCheck();
      await _ensureSignedIn();
      return FirebaseStatus.ready;
    } catch (error, stackTrace) {
      // İlk açılış + uçak modu gibi durumlarda kullanıcıyı kilitlemeyiz.
      debugPrint('FirebaseBootstrap: başlatılamadı, yerel mod. $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      return FirebaseStatus.localMode;
    }
  }

  /// App Check aktivasyonu — analyzeDecision consumeAppCheckToken ister.
  /// Sağlayıcılar: iOS App Attest (DeviceCheck yedekli) / Android Play
  /// Integrity; debug build'de debug provider (Console'da debug token
  /// kaydı gerekir).
  /// Aktivasyon başarısızlığı çökme değildir — istek reddi olarak yansır.
  static Future<void> _activateAppCheck() async {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: appleAppCheckProviderFor(isDebug: kDebugMode),
      );
    } catch (error) {
      debugPrint('FirebaseBootstrap: App Check aktive edilemedi. $error');
    }
  }

  /// US-E1: giriş yapmadan ilk karar — açılışta sessiz anonim oturum.
  /// Mevcut oturum (anonim ya da bağlı hesap) varsa dokunulmaz.
  static Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }
}

/// Apple tarafı App Check sağlayıcısını seçer (saf fonksiyon → test edilebilir).
///
///  - Debug build : Firebase debug provider (token Console'a elle kaydedilir)
///  - iOS 14+     : App Attest
///  - iOS 13      : DeviceCheck (App Attest yok)
///
/// NEDEN SAF `appAttest` DEĞİL: App Attest yalnız iOS 14+'da vardır, bu
/// projenin minimum sürümü ise 13.0. Saf `appAttest` seçilirse iOS 13
/// cihazlarda sağlayıcı kurulamaz ve App Check zorunlu callable'lar
/// (analyzeDecision, deleteAccount, createRewardTicket) 403 döner.
/// `appAttestWithDeviceCheckFallback` platform sürümüne göre doğru olanı
/// seçer; kod tarafında sürüm kontrolü gerekmez.
AppleProvider appleAppCheckProviderFor({required bool isDebug}) => isDebug
    ? AppleProvider.debug
    : AppleProvider.appAttestWithDeviceCheckFallback;
