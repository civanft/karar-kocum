# App Store — App Privacy beyanı (doldurmaya hazır)

**Kaynak gerçeklik:** `docs/privacy/DATA-FLOW-INVENTORY.md`
**Doğrulanan revizyon:** `feat/ai-privacy-contract`
**Durum:** Bu dosya App Store Connect'e **girilecek** cevapların kaynak
kontrollü kanıtıdır. Konsola giriş veya submission bu pakette YAPILMAZ.

## Özet cevaplar

| Soru | Cevap | Kanıt |
|---|---|---|
| Uygulama tracking yapıyor mu? | **Hayır** | `ios/Runner/PrivacyInfo.xcprivacy` `NSPrivacyTracking=false`; reklam/attribution SDK'sı yok (`pubspec.yaml`) |
| ATT (AppTrackingTransparency) gerekli mi? | **Hayır** — izlenen veri yok, IDFA okunmuyor | `ios/Runner/Info.plist` (NSUserTrackingUsageDescription YOK), `pubspec.yaml` |
| Üçüncü taraf reklam ağı var mı? | **Hayır** | `pubspec.yaml`, `test/release/analytics_dormancy_test.dart` |

## Veri türleri

Sütunlar: Toplanıyor / Paylaşılıyor / Kullanıcıyla ilişkili / Tracking /
Amaç / Zorunlu / Şifreli (aktarımda) / Silme talebi destekleniyor / Kanıt /
Konsolda seçilecek karşılık.

| Veri türü | Toplanıyor | Paylaşılıyor | Kullanıcıyla ilişkili | Tracking | Amaç | Zorunlu | Şifreli | Silme | Kanıt | Konsol karşılığı |
|---|---|---|---|---|---|---|---|---|---|---|
| Kullanıcı kimliği (anonim UID) | Evet | Hayır | Evet | Hayır | App Functionality | Zorunlu | Evet (HTTPS/TLS) | Evet | `lib/core/config/firebase_bootstrap.dart` | Identifiers → User ID |
| Karar içeriği (başlık, seçenekler, kriterler, puanlar) | Evet | Hayır | Evet | Hayır | App Functionality | Zorunlu | Evet | Evet | `functions/src/ai/schema.ts` | User Content → Other User Content |
| AI analiz metni | Evet | Hayır | Evet | Hayır | App Functionality | İsteğe bağlı (izne bağlı) | Evet | Evet | `functions/src/ai/firestore_ports.ts` | User Content → Other User Content |
| Çökme verisi (Firebase Crashlytics) | Evet | Hayır | Hayır | Hayır | App Functionality | Zorunlu | Evet | Hayır (sağlayıcıda) | `lib/core/services/crash_reporter.dart` | Diagnostics → Crash Data |
| Cihaz bütünlük sinyali (App Check) | Evet | Hayır | Hayır | Hayır | App Functionality, Fraud Prevention | Zorunlu | Evet | Yok (kalıcı değil) | `lib/core/config/firebase_bootstrap.dart` | Identifiers → Device ID |
| Reklam kimliği (IDFA) | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `pubspec.yaml`, `ios/Runner/Info.plist` | Beyan edilmez |
| Kullanım analitiği | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `lib/core/services/analytics/analytics_service.dart` | Beyan edilmez |
| Konum | Hayır | Hayır | Hayır | Hayır | — | — | — | — | `ios/Runner/Info.plist` (usage description yok) | Beyan edilmez |
| İletişim bilgisi (e-posta/ad) | Hayır | Hayır | Hayır | Hayır | — | — | — | — | Yalnız anonim oturum: `lib/core/config/firebase_bootstrap.dart` | Beyan edilmez |

## "Paylaşılıyor" (shared) neden Hayır

Apple'ın "shared with third parties" tanımı, verinin üçüncü tarafın **kendi
amaçları** için kullanılmasını kapsar. Karar içeriği OpenAI'ye **bizim
adımıza işlenmek üzere** gönderilir; API verisi OpenAI modellerini eğitmek
için varsayılan olarak kullanılmaz (opt-in gerekir) — bkz.
`docs/privacy/DATA-FLOW-INVENTORY.md` §2. Bu nedenle **service provider**
ilişkisi kabul edilmiştir ve aktarımın kendisi politikada açıkça anlatılır
(`hosting/privacy/index.html`).

> **Dürüst risk:** Bu bir yorumdur. Apple incelemesi OpenAI aktarımını
> "shared" saymayı isterse cevap *Evet (Other User Content, App
> Functionality)* olarak güncellenmelidir; politikada ve envanterde
> aktarımın kendisi zaten açıkça yazılıdır.

## Gizlilik manifesti gerçekten paketleniyor mu

`ios/Runner/PrivacyInfo.xcprivacy` yalnız depoda durmuyor: Xcode projesinde
`PBXFileReference` + `PBXBuildFile` olarak tanımlı ve Runner hedefinin
**Resources build phase**'ine bağlı
(`ios/Runner.xcodeproj/project.pbxproj`). Simülatör derlemesinde dosyanın
`build/ios/Debug-iphonesimulator/Runner.app/PrivacyInfo.xcprivacy` yoluna
kopyalandığı doğrulanmıştır. Bağlantı
`test/release/privacy_consistency_test.dart` ile kilitlidir — koparılırsa
süit kırmızıya döner.

## Data Use / retention notu

OpenAI'nin varsayılan davranışı: API içeriği **opt-in olmadıkça eğitim için
kullanılmaz**; kötüye kullanım izleme kayıtları istem/yanıt içerebilir ve
**30 güne kadar** saklanır. ZDR/MAM bu projede **kanıtlanmamıştır** ve
etkinmiş gibi beyan edilmez.
