import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';

/// TEK TİMEOUT SÖZLEŞMESİ (6E0).
///
/// Başlatmanın ne kadar bekleneceğine ve zaman aşımının hangi duruma
/// düşeceğine KARAR VEREN TEK YER burasıdır. Eskiden `StartupGate` de kendi
/// `.timeout()` katmanını uyguluyordu; iki katman üst üste binince içteki
/// DEĞER döndürdüğü için dıştaki hiç tetiklenmiyor ve release dışı davranış
/// sessizce değişiyordu.
void main() {
  test('ilk açılış SONSUZA kadar bekleyemez', () async {
    final sdk = Completer<FirebaseStatus>();
    final result = await waitForFirebaseStartup(
      sdk.future,
      isReleaseMode: true,
      timeout: const Duration(milliseconds: 10),
    );
    expect(result, FirebaseStatus.unavailable);

    // Alttaki işlem sonradan tamamlansa da dönmüş sonuç değişmez.
    sdk.complete(FirebaseStatus.ready);
    expect(result, FirebaseStatus.unavailable);

    // Aynı işlem yeniden beklenebilir; ikinci bir SDK çağrısı gerekmez.
    expect(
      await waitForFirebaseStartup(sdk.future, isReleaseMode: true),
      FirebaseStatus.ready,
    );
  });

  test('RELEASE zaman aşımında FAIL-CLOSED kalır', () async {
    expect(
      await waitForFirebaseStartup(
        Completer<FirebaseStatus>().future,
        isReleaseMode: true,
        timeout: const Duration(milliseconds: 10),
      ),
      FirebaseStatus.unavailable,
      reason: 'release\'de yerel moda düşmek sahte veri gösterirdi',
    );
  });

  test('DEBUG/PROFILE zaman aşımında BİLİNÇLİ olarak yerel moda düşer',
      () async {
    expect(
      await waitForFirebaseStartup(
        Completer<FirebaseStatus>().future,
        isReleaseMode: false,
        timeout: const Duration(milliseconds: 10),
      ),
      FirebaseStatus.localMode,
      reason: 'geliştirme akışı Firebase olmadan da sürmelidir',
    );
  });

  test('başarılı açılış ready durumunu korur', () async {
    expect(
      await waitForFirebaseStartup(
        Future.value(FirebaseStatus.ready),
        isReleaseMode: true,
      ),
      FirebaseStatus.ready,
    );
  });

  test('onTimedOut YALNIZ zaman aşımında çağrılır', () async {
    var timedOut = 0;

    await waitForFirebaseStartup(
      Future.value(FirebaseStatus.ready),
      isReleaseMode: true,
      onTimedOut: () => timedOut++,
    );
    expect(timedOut, 0, reason: 'başarılı açılışta temizlik tetiklenmemeli');

    await waitForFirebaseStartup(
      Completer<FirebaseStatus>().future,
      isReleaseMode: true,
      timeout: const Duration(milliseconds: 10),
      onTimedOut: () => timedOut++,
    );
    expect(timedOut, 1, reason: 'asılı deneme temizlik kancasını tetiklemeli');
  });

  test('varsayılan açılış süresi açıkça tanımlı ve makul', () {
    const expected = Duration(seconds: 15);
    expect(FirebaseBootstrap.defaultStartupTimeout, expected);
  });
}
