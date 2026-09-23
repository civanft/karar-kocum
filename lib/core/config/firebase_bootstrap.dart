import 'dart:async';

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
  /// çalışır (in-memory depo, kimliksiz). Yalnız debug/profile/test için
  /// normaldir; release'de ASLA seçilmez.
  localMode,

  /// Release'de Firebase'e bağlanılamadı — FAIL-CLOSED.
  ///
  /// Yerel moda düşmek release'de kabul edilemez: in-memory depo kalıcı
  /// sanılan karar, LocalCreditsRepository sahte kredi ve MockAiAnalysisClient
  /// uydurma bir analiz gösterirdi. Bu durumda uygulama açık bir "bağlanılamadı"
  /// ekranı gösterir ve hiçbir sahte veri üretmez.
  unavailable,
}

/// Başlatma hatasının hangi duruma düşeceğini belirleyen SAF politika.
///
/// [kReleaseMode] doğrudan test edilemediği için karar buraya ayrıldı;
/// çağıran taraf bayrağı geçer, test seam'i saf kalır.
FirebaseStatus firebaseFailureStatus({required bool isReleaseMode}) =>
    isReleaseMode ? FirebaseStatus.unavailable : FirebaseStatus.localMode;

/// Bound the first startup as well as retries. The underlying SDK operation
/// remains shared: timing out must not start a second anonymous sign-in.
Future<FirebaseStatus> waitForFirebaseStartup(
  Future<FirebaseStatus> initialization, {
  required bool isReleaseMode,
  Duration timeout = const Duration(seconds: 15),
}) =>
    initialization.timeout(
      timeout,
      onTimeout: () => firebaseFailureStatus(isReleaseMode: isReleaseMode),
    );

/// Uygulama açılışında Firebase'i dener; başarısızlık ÇÖKME DEĞİLDİR.
/// Splash bütçesi (mimari §13): burada yalnız init + anonim oturum var,
/// Remote Config/Analytics sonraki sprintlerde eklenirken de bekletilmez.
abstract final class FirebaseBootstrap {
  /// Aynı anda iki başlatma çalışmasını önler: retry butonuna arka arkaya
  /// basılması ya da paralel bir çağrı duplicate-app üretmemeli.
  static Future<FirebaseStatus>? _inFlight;
  static bool _appCheckActivated = false;

  /// Retry için idempotent giriş noktası.
  ///
  /// Firebase app zaten kuruluysa yeniden kurulmaz (`Firebase.apps`);
  /// yalnız eksik olan anonim oturum tamamlanır. Devam eden bir başlatma
  /// varsa aynı Future paylaşılır.
  static Future<FirebaseStatus> ensureInitialized() {
    final running =
        _inFlight ??= tryInitialize().whenComplete(() => _inFlight = null);
    return waitForFirebaseStartup(running, isReleaseMode: kReleaseMode);
  }

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
      // Release'de de aynı güvenlik politikası: kayıtsız platform sahte
      // veriyle çalışmaz.
      if (!kReleaseMode) {
        debugPrint('FirebaseBootstrap: platform yapılandırması yok — '
            'yerel mod. $e');
      }
      return firebaseFailureStatus(isReleaseMode: kReleaseMode);
    }

    try {
      // İdempotent: zaten kuruluysa duplicate-app hatası üretmeden geç.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      // App creation can succeed before attestation fails. A retry must
      // finish activation even when the Firebase app already exists.
      if (!_appCheckActivated) {
        await _activateAppCheck();
        _appCheckActivated = true;
      }
      await _ensureSignedIn();
      return FirebaseStatus.ready;
    } catch (error, stackTrace) {
      // Release'de teşhis AYRINTISI yazdırılmaz: exception mesajı Firebase
      // proje kimliği, UID ya da belge yolu taşıyabilir. Yalnız hata TÜRÜ.
      if (kReleaseMode) {
        debugPrint('FirebaseBootstrap: başlatılamadı (${error.runtimeType}).');
      } else {
        debugPrint('FirebaseBootstrap: başlatılamadı, yerel mod. $error');
        debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      }
      return firebaseFailureStatus(isReleaseMode: kReleaseMode);
    }
  }

  /// App Check aktivasyonu — analyzeDecision consumeAppCheckToken ister.
  /// Sağlayıcılar: iOS App Attest (DeviceCheck yedekli) / Android Play
  /// Integrity; debug build'de debug provider (Console'da debug token
  /// kaydı gerekir).
  /// Başarısızlık üstteki başlangıç kapısına taşınır; release hazır sayılmaz.
  static Future<void> _activateAppCheck() async {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: appleAppCheckProviderFor(isDebug: kDebugMode),
    );
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
