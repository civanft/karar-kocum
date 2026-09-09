# Google Play — Data Safety beyanı (doldurmaya hazır)

**Kaynak gerçeklik:** `docs/privacy/DATA-FLOW-INVENTORY.md`
**Durum:** Play Console'a **girilecek** cevapların kaynak kontrollü kanıtı.
Konsola giriş veya submission bu pakette YAPILMAZ.

## Özet cevaplar

| Soru | Cevap | Kanıt |
|---|---|---|
| Veri toplanıyor mu / paylaşılıyor mu? | Toplanıyor: **Evet**. Paylaşılıyor: **Hayır** | `docs/privacy/DATA-FLOW-INVENTORY.md` |
| Aktarımda şifreleniyor mu? | **Evet** — tüm trafik HTTPS/TLS (Firebase SDK'ları ve callable) | `functions/src/ai/analyze.ts` |
| Kullanıcı silme talep edebiliyor mu? | **Evet** — uygulama içi hesap+veri silme | `functions/src/privacy/deleteAccount.ts` |
| Reklam kimliği kullanılıyor mu? | **Hayır** — izin manifest-merger'da kaldırılıyor | `android/app/src/main/AndroidManifest.xml` |
| Tracking / reklam amaçlı kullanım var mı? | **Hayır** | `pubspec.yaml`, `test/release/analytics_dormancy_test.dart` |

## Veri türleri

| Veri türü | Toplanıyor | Paylaşılıyor | Kullanıcıyla ilişkili | Tracking | Amaç | Zorunlu | Şifreli | Silme | Kanıt | Konsol karşılığı |
|---|---|---|---|---|---|---|---|---|---|---|
| Kullanıcı kimliği (anonim UID) | Evet | Hayır | Evet | Hayır | App functionality | Zorunlu | Evet | Evet | `lib/core/config/firebase_bootstrap.dart` | Personal info → User IDs |
| Karar içeriği ve puanlar | Evet | Hayır | Evet | Hayır | App functionality | Zorunlu | Evet | Evet | `functions/src/ai/schema.ts` | App activity → Other user-generated content |
| AI analiz metni | Evet | Hayır | Evet | Hayır | App functionality | İsteğe bağlı (izne bağlı) | Evet | Evet | `functions/src/ai/firestore_ports.ts` | App activity → Other user-generated content |
| Çökme kayıtları (Firebase Crashlytics) | Evet | Hayır | Hayır | Hayır | App functionality, Diagnostics | Zorunlu | Evet | Hayır (sağlayıcıda) | `lib/core/services/crash_reporter.dart` | App info and performance → Crash logs |
| Cihaz bütünlük sinyali (App Check) | Evet | Hayır | Hayır | Hayır | Fraud prevention, security | Zorunlu | Evet | Yok (kalıcı değil) | `lib/core/config/firebase_bootstrap.dart` | Device or other IDs |
| Reklam kimliği | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `android/app/src/main/AndroidManifest.xml` | Beyan edilmez |
| Kullanım analitiği | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `lib/core/services/analytics/analytics_service.dart` | Beyan edilmez |
| Konum | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `android/app/src/main/AndroidManifest.xml` | Beyan edilmez |
| Kişiler / mesajlar / dosyalar | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `android/app/src/main/AndroidManifest.xml` | Beyan edilmez |

## Beyan edilen Android izinleri

| İzin | Neden | Kanıt |
|---|---|---|
| `POST_NOTIFICATIONS` | 7 gün sonraki karar kontrolü hatırlatması (YEREL bildirim, FCM değil) | `android/app/src/main/AndroidManifest.xml` |
| `RECEIVE_BOOT_COMPLETED` | Planlanmış yerel bildirim cihaz yeniden başlayınca kaybolmasın | `android/app/src/main/AndroidManifest.xml` |

**Derleme-zamanı kanıtı:** `flutter build appbundle --release` ile üretilen
`app-release.aab` içindeki BİRLEŞTİRİLMİŞ `base/manifest/AndroidManifest.xml`
taranmıştır: `AD_ID` ve `ACCESS_ADSERVICES` dizeleri **bulunmaz**,
`POST_NOTIFICATIONS` ve `RECEIVE_BOOT_COMPLETED` **bulunur**. Yani beyan
kaynak manifestin niyetine değil, gerçekten yayınlanan pakete dayanır.

Reklam/attribution izinleri (`AD_ID`, `ACCESS_ADSERVICES_*`) manifest-merger
düzeyinde **kaldırılır**: bir bağımlılık bunları eklerse Data Safety beyanı
sessizce yanlış hâle gelirdi. Testi:
`test/release/analytics_dormancy_test.dart`.

## "Paylaşılıyor" neden Hayır

Play'in "shared" tanımı üçüncü tarafa aktarımı kapsar ancak **service
provider** olarak işleyenleri hariç tutar. OpenAI, analizi bizim adımıza
üretir; API içeriği opt-in olmadıkça model eğitiminde kullanılmaz. Aktarım
gizlilik politikasında açıkça anlatılır ve kullanıcı **açık izin** vermeden
gerçekleşmez (`functions/src/privacy/ai_consent.ts`).

> **Dürüst risk:** Bu bir yorumdur. Play incelemesi aksini isterse cevap
> *Evet (Other user-generated content)* olarak güncellenmelidir.
