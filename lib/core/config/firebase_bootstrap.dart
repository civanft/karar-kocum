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

/// TEK ZAMAN AŞIMI SÖZLEŞMESİ — uygulamadaki başlatma beklemelerinin
/// TAMAMINI bu fonksiyon sınırlar.
///
/// Eskiden `StartupGate` de kendi `.timeout()` katmanını uyguluyordu. İki
/// katman üst üste bindiğinde içteki katman bir DEĞER döndürdüğü için
/// dıştaki `TimeoutException` hiç oluşmuyor, üstelik gate release dışında da
/// `unavailable` üretiyordu. Şimdi sınırı yalnız burası koyar; gate sonucu
/// bekler.
///
/// Alttaki SDK işlemi İPTAL EDİLEMEZ: zaman aşımı yalnız BEKLEMEKTEN
/// vazgeçer. [onTimedOut], vazgeçilen denemenin paylaşılan durumunu
/// temizlemek için çağrılır.
Future<FirebaseStatus> waitForFirebaseStartup(
  Future<FirebaseStatus> initialization, {
  required bool isReleaseMode,
  Duration timeout = FirebaseBootstrap.defaultStartupTimeout,
  void Function()? onTimedOut,
}) =>
    initialization.timeout(
      timeout,
      onTimeout: () {
        onTimedOut?.call();
        return firebaseFailureStatus(isReleaseMode: isReleaseMode);
      },
    );

/// Uygulama açılışında Firebase'i dener; başarısızlık ÇÖKME DEĞİLDİR.
/// Splash bütçesi (mimari §13): burada yalnız init + anonim oturum var,
/// Remote Config/Analytics sonraki sprintlerde eklenirken de bekletilmez.
abstract final class FirebaseBootstrap {
  /// Başlatmanın sonuçlanması için beklenen ÜST SINIR.
  ///
  /// Yavaş bir mobil bağlantıda başlatmanın tamamlanmasına yetecek kadar
  /// uzun, kullanıcıyı splash'te kaybetmeyecek kadar kısadır.
  static const defaultStartupTimeout = Duration(seconds: 15);

  /// Aynı anda iki başlatma çalışmasını önler: retry butonuna arka arkaya
  /// basılması ya da paralel bir çağrı duplicate-app üretmemeli.
  static Future<FirebaseStatus>? _inFlight;

  /// Devam eden denemenin KUŞAK numarası.
  ///
  /// Zaman aşımına uğramış bir deneme paylaşımdan düşürülür ama İPTAL
  /// EDİLEMEZ; saatler sonra tamamlanabilir. Kuşak numarası olmadan o geç
  /// tamamlanma, kendisinden sonra başlamış SAĞLIKLI denemenin kaydını
  /// silerdi. Her temizlik yalnız KENDİ kuşağına dokunur.
  static int _generation = 0;

  /// App Check sağlayıcı fabrikası KURULDU mu.
  ///
  /// Dikkat: bu bayrak yalnız KURULUMU izler, gerçek attestation başarısını
  /// DEĞİL (bkz. [_installAppCheckProvider]).
  static bool _appCheckProviderInstalled = false;

  /// Retry için idempotent giriş noktası; sonuç her zaman SINIRLIDIR.
  ///
  /// Firebase app zaten kuruluysa yeniden kurulmaz (`Firebase.apps`);
  /// yalnız eksik olan adımlar tamamlanır. Devam eden bir başlatma varsa
  /// aynı Future paylaşılır — eş zamanlı çağrılar ikinci bir SDK çalışması
  /// başlatmaz.
  static Future<FirebaseStatus> ensureInitialized({Duration? timeout}) {
    final generation = _generation;
    final running = _inFlight ??= tryInitialize().whenComplete(() {
      // Yalnız kendi kuşağını temizler: zaman aşımından sonra başlamış yeni
      // bir denemenin kaydı korunur.
      if (_generation == generation) _inFlight = null;
    });

    return waitForFirebaseStartup(
      running,
      isReleaseMode: kReleaseMode,
      timeout: timeout ?? defaultStartupTimeout,
      onTimedOut: () => _abandon(generation),
    );
  }

  /// Zaman aşımına uğrayan denemeyi paylaşımdan düşürür.
  ///
  /// Bu olmadan asılı kalan tek bir Future, uygulama yeniden başlayana kadar
  /// HER retry'ı zehirlerdi: her deneme aynı ölü Future'ı beklemek için
  /// süreyi baştan harcardı.
  static void _abandon(int generation) {
    if (_generation != generation) return;
    _generation++;
    _inFlight = null;
  }

  /// Testler için statik durumu sıfırlar — testler arası sızıntıyı ve sıra
  /// bağımlılığını önler. Üretim kodundan ÇAĞRILMAZ.
  @visibleForTesting
  static void resetForTest() {
    _generation++;
    _inFlight = null;
    _appCheckProviderInstalled = false;
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
      // App oluşturma başarılı olup sağlayıcı kurulumu başarısız olabilir.
      // Bu yüzden kurulum, app'in varlığından BAĞIMSIZ olarak izlenir:
      // aksi halde bir retry eksik kalan kurulumu asla tamamlamazdı.
      if (!_appCheckProviderInstalled) {
        await _installAppCheckProvider();
        _appCheckProviderInstalled = true;
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

  /// App Check SAĞLAYICI FABRİKASINI kurar — attestation YAPMAZ.
  ///
  /// SINIR: `activate()` hem Android hem iOS tarafında yalnız yerel bir
  /// yapılandırma çağrısıdır (provider factory kurulumu) ve ağ işlemi
  /// içermez. Bu çağrının başarıyla dönmesi, cihazın gerçekten geçerli bir
  /// App Check token'ı ALABİLECEĞİ anlamına GELMEZ. Gerçek attestation ilk
  /// token isteğinde, yani App Check zorunlu bir callable çağrılırken
  /// doğrulanır; sağlayıcı kaydı eksikse orada 401 alınır.
  ///
  /// Sağlayıcılar: iOS App Attest (DeviceCheck yedekli) / Android Play
  /// Integrity; debug build'de debug provider (Console'da debug token
  /// kaydı gerekir).
  /// Kurulum başarısızlığı üstteki başlangıç kapısına taşınır.
  static Future<void> _installAppCheckProvider() async {
    await FirebaseAppCheck.instance.activate(
      androidProvider: androidAppCheckProviderFor(isDebug: kDebugMode),
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
///  - Daha eski   : DeviceCheck (App Attest yok)
///
/// NEDEN SAF `appAttest` DEĞİL: App Attest yalnız iOS 14+'da vardır.
/// Projenin minimum sürümü **iOS 14.0**'tır (`ios/Podfile` ve Xcode
/// `IPHONEOS_DEPLOYMENT_TARGET`), yani App Attest bugünkü tabanın tamamında
/// kullanılabilir. Yedekli seçici yine de tercih edilir: minimum sürüm
/// ileride düşürülürse ya da platform App Attest'i reddederse kod tarafında
/// sürüm kontrolü gerekmeden doğru sağlayıcı seçilir.
AppleProvider appleAppCheckProviderFor({required bool isDebug}) => isDebug
    ? AppleProvider.debug
    : AppleProvider.appAttestWithDeviceCheckFallback;

/// Android tarafı App Check sağlayıcısını seçer (saf fonksiyon).
///
/// Apple tarafındaki seçiciyle simetriktir ve aynı nedenle vardır: sağlayıcı
/// seçimi `kDebugMode`'a bağlı olduğu için, RELEASE dalı testte doğrudan
/// çalıştırılamaz. Saf seçici, debug sağlayıcısının release'e sızmadığını
/// test edilebilir kılar.
AndroidProvider androidAppCheckProviderFor({required bool isDebug}) =>
    isDebug ? AndroidProvider.debug : AndroidProvider.playIntegrity;
