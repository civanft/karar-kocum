import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';

/// App Check Apple sağlayıcı seçimi (AŞAMA 24C-1).
///
/// Firebase BAŞLATILMAZ: seçim saf bir fonksiyona ayrıldığı için
/// `Firebase.initializeApp` olmadan test edilebilir.
///
/// Neden `appAttest` değil `appAttestWithDeviceCheckFallback`:
/// App Attest yalnız iOS 14+'da vardır; projenin minimum sürümü 13.0.
/// Saf `appAttest` ile iOS 13 cihazlarda sağlayıcı kurulamaz ve App Check
/// zorunlu callable'lar (analyzeDecision, deleteAccount …) 403 alır.
void main() {
  test('debug build → Firebase debug provider', () {
    expect(
      appleAppCheckProviderFor(isDebug: true),
      AppleProvider.debug,
    );
  });

  test('release build → App Attest + DeviceCheck fallback', () {
    expect(
      appleAppCheckProviderFor(isDebug: false),
      AppleProvider.appAttestWithDeviceCheckFallback,
    );
  });

  test('release seçiminde SAF appAttest kullanılmaz (iOS 13 kırılır)', () {
    expect(
      appleAppCheckProviderFor(isDebug: false),
      isNot(AppleProvider.appAttest),
    );
  });

  test('release\'de debug provider\'a sessizce düşülmez', () {
    // iOS 13 uyumluluğu debug provider'la çözülmez: debug token yalnız
    // Console'a elle kaydedilmiş cihazlarda çalışır.
    expect(
      appleAppCheckProviderFor(isDebug: false),
      isNot(AppleProvider.debug),
    );
  });

  test('seçim yalnız isDebug bayrağına bağlıdır (yan etkisiz)', () {
    expect(
      appleAppCheckProviderFor(isDebug: true),
      appleAppCheckProviderFor(isDebug: true),
    );
    expect(
      appleAppCheckProviderFor(isDebug: false),
      appleAppCheckProviderFor(isDebug: false),
    );
    expect(
      appleAppCheckProviderFor(isDebug: true),
      isNot(appleAppCheckProviderFor(isDebug: false)),
    );
  });
}
