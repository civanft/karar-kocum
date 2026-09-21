# Karar Koçum

[![CI](https://github.com/civanft/karar-kocum/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/civanft/karar-kocum/actions/workflows/ci.yaml)

> Önemli kararlarını seçenekler, kriterler ve ağırlıklarla yapılandır; istersen
> açık iznine dayalı bir AI analiziyle değerlendir.

Flutter (iOS + Android) · Riverpod · Firebase (Auth, Firestore, Cloud Functions) · OpenAI (yalnız backend'den)

## Proje özeti

**Karar Koçum**, kullanıcının bir kararı **seçenekler**, **kriterler** ve bu
kriterlere verdiği **önem ağırlıklarıyla** yapılandırmasına, seçenekleri
puanlayarak ağırlıklı bir sonuca ulaşmasına yardımcı olur.

**AI analizi isteğe bağlıdır** ve yalnız kullanıcının **açık izniyle** çalışır;
izin verilmeden karar içeriği AI sağlayıcısına gönderilmez.

> **Yayın durumu:** Uygulama **henüz App Store veya Google Play'de public
> olarak yayınlanmadı.** Proje aktif olarak **release-candidate** hazırlığındadır;
> kalan kapılar aşağıdaki tablodadır.

## Güncel durum

| Paket | Kapsam | Durum |
|---|---|---|
| Paket 1 | Bağımlılık ve dağıtım tabanı | Tamamlandı |
| Paket 2 | Backend işlem güvenliği | Tamamlandı |
| Paket 3 | Silme güvenliği | Tamamlandı |
| Paket 4 | İstemci dayanıklılığı | Tamamlandı |
| Paket 5 | AI / gizlilik sözleşmesi | Tamamlandı |
| Paket 6A | Release / operations baseline | Tamamlandı |
| Paket 6B | Backup, PITR ve restore drill | Tamamlandı |
| Paket 6C | Monitoring | Tamamlandı: e-posta kanalı doğrulandı, kalıcı alarmlar ve saatlik backup freshness kontrolü canlıda |
| Paket 6E | App Check provider ve gerçek cihaz doğrulaması | Bekliyor |
| Paket 6F | İmzalı build ve fiziksel cihaz testi | Bekliyor |
| Store submission | App Store / Google Play gönderimi | Yapılmadı |

Production backend, repodaki son sürümün gerisindedir; güncel backend'in
deploy'u kontrollü bir release adımıdır ([runbook §7 ve §10](docs/RELEASE-RUNBOOK.md)).

## Güvenlik ve güvenilirlik

- **Replay / idempotency:** Her analiz isteği bir istek kimliğiyle journal'a
  bağlanır; aynı istek tekrarlandığında iş yeniden ücretlendirilmez, tamamlanmış
  sonuç geri döner.
- **Tek istek, tek kredi:** Kredi yalnız başarıyla tamamlanan analizde düşer;
  rezervasyon ve kapanış atomik transaction'larla yapılır.
- **Sağlayıcı belirsizliği:** Sonucu bilinmeyen sağlayıcı çağrıları journal'da
  izlenir ve güvenli biçimde kurtarılır; istemciye açık bir retry yönergesi döner.
- **Hesap silme bariyeri:** Silme, yeni veri yazımını durduran bir bariyerle
  başlar; veri doğrulanarak silinir ve Auth hesabı en son silinir.
  Uygulama içinden: *Ayarlar → Hesap ve Veriler → Hesabımı ve Verilerimi Sil*.
- **İstemci dayanıklılığı:** Analiz sonucu uygulama yeniden açıldığında geri
  yüklenir; kayıt hataları kullanıcıya görünür biçimde gösterilir ve çıkışta
  bekleyen yazımlar tamamlanır.
- **AI içerik izni:** Karar içeriği yalnız sürümlenmiş açık kullanıcı izniyle
  AI'a gönderilir; izin istemcide ve backend'de fail-closed denetlenir.
- **Structured logging:** Backend logger'ı ham UID, karar içeriği, prompt veya
  secret loglamaz; yasak alanlar çalışma zamanında ayıklanır.
- **App Check:** Production'daki callable'lar (`analyzeDecision`,
  `deleteAccount`) App Check'i **zaten enforce ediyor**; token'ı eksik veya
  geçersiz istekler canlıda HTTP 401 ile reddediliyor. Provider kayıtları ve
  imzalı gerçek cihaz token doğrulaması ise **hâlâ açık bir release kapısıdır**
  (Paket 6E).
- **Backup:** Firestore PITR ile günlük ve haftalık zamanlanmış yedekler;
  izole bir veritabanına yapılan gerçek restore tatbikatı başarılı oldu.
- **Monitoring:** Doğrulanmış e-posta kanalına bağlı kalıcı alarmlar (aşağıda).

## Mimari

- **İstemci:** Flutter (iOS + Android), feature-first Clean Architecture
  (`presentation → domain ← data`; domain saf Dart), durum yönetimi Riverpod.
- **Backend:** Firebase Auth, Cloud Firestore ve Cloud Functions 2nd gen
  (Node.js 22).
- **AI:** OpenAI çağrısı **yalnız backend'den** yapılır; API anahtarı Secret
  Manager'da tutulur ve istemcide bulunmaz.
- **Ortamlar:** Debug/Profile derlemeleri development, Release derlemeleri
  production Firebase projesine bağlanır
  (`lib/core/config/firebase_environment.dart`).

Ayrıntılar: [Teknik mimari](docs/TEKNIK-MIMARI.md) ·
[Proje yapısı](docs/PROJE-YAPISI.md) ·
[Firestore veri modeli](docs/FIRESTORE-VERI-MODELI.md) ·
[AI MVP mimarisi](docs/AI-MVP-MIMARI.md)

## Gizlilik

- **AI analizi yalnız açık izinle:** İzin verilmeden karar içeriği AI
  sağlayıcısına gönderilmez.
- **AI'a gönderilen:** karar başlığı, seçenekler (açıklama, artı/eksi) ve
  kriterler ile önem ağırlıkları. **Gönderilmeyen:** seçeneklere verilen
  puanlar (puan matrisi).
- **Analytics SDK'sı yok:** Uygulamada kullanım analitiği SDK'sı bulunmaz
  (`firebase_analytics` bağımlılıklarda yok).
- **Reklam kimliği kullanılmaz:** Android'de `AD_ID` izinleri manifest
  birleştirmede kaldırılır; iOS'ta izleme izni istenmez.
- **Crashlytics** raporları sanitize edilir; hata mesajı, karar içeriği ve UID
  gönderilmez.

Belgeler: [Veri akışı envanteri](docs/privacy/DATA-FLOW-INVENTORY.md) ·
[Gizlilik politikası](hosting/privacy/index.html) ·
[Google Play Data Safety](docs/store/GOOGLE-PLAY-DATA-SAFETY.md) ·
[App Store Privacy](docs/store/APP-STORE-PRIVACY.md)

## Backup ve operasyon

| Katman | Durum |
|---|---|
| Point-in-time recovery (PITR) | Açık — 7 gün |
| Günlük zamanlanmış yedek | Açık — 7 gün saklama |
| Haftalık zamanlanmış yedek | Açık — 28 gün saklama |
| Restore tatbikatı | PASS — izole geçici veritabanına; production'a dokunulmadı |
| Backup freshness kontrolü | Açık — saatlik (UTC), 30 saat tazelik eşiği |

Yedek tazeliğini saatlik bir zamanlanmış kontrol ölçer: yalnız yedek
metadata'sını okur, hiçbir uygulama verisine erişmez ve adanmış, en az
yetkili bir kimlikle çalışır. Sorun bulduğunda ya da kontrolün kendisi
çalışamadığında alarm üretir — **bir yetki hatası "yedek yok" sayılmaz**.

Kanıt: [Restore tatbikatı kanıtı](docs/operations/RESTORE-DRILL-2026-09-14.md) ·
[Checker rollout kanıtı](docs/operations/BACKUP-CHECKER-ROLLOUT-2026-09-21.md) ·
Prosedür: [Release runbook §4–§6](docs/RELEASE-RUNBOOK.md)

## Monitoring

- **Bildirim kanalı:** Gerçek bir test e-postasıyla teslimatı doğrulanmış
  e-posta kanalı.
- **Kalıcı sinyaller:** 11 log-based metric ve 11 alert policy (beklenmeyen
  hata, kredi tutarlılığı, rezervasyon, hesap silme, AI sağlayıcı, Cloud Run
  5xx, App Check, yedek tazeliği, yedek kontrolünün kendisi).
- **App Check gözlem alarmı şimdilik bildirimsizdir;** Paket 6E rollout'unda
  bildirime bağlanacak.
- **Analiz hacmi** metriği yalnız baseline topluyor; kanıtsız eşik
  uydurulmadığı için alarmı yok.
- **Proje bütçesi bildirimi** vardır. Budget **harcamayı durdurmaz**, yalnız
  bildirim üretir; **OpenAI maliyeti GCP budget'ına dahil değildir.**
- **Yedek tazeliği** saatlik olarak ölçülür; ayrıca kontrolün kendisi
  durursa ikinci bir alarm devreye girer.
- **Eksik:** lansman sonrası eşik ayarı ve yedek kontrolü alarmının gerçek bir
  kesintide tetiklendiğinin gözlenmesi.

Ayrıntılar ve filtre sözleşmesi: [Monitoring](docs/MONITORING-PANOSU.md)

## Yerel geliştirme

**Gereksinimler**

- **Flutter:** sürüm [`.flutter-version`](.flutter-version) dosyasında
  sabitlenir; CI aynı dosyayı okur.
- **Node.js 22:** `functions/` (`engines.node`).
- **Java 21:** Firebase emulator testleri için (CI: Temurin 21).
- iOS için Xcode, Android için Android SDK.

**İstemci**

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Freezed/JSON codegen
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
bash scripts/check_layers.sh
flutter test --coverage
bash scripts/check_coverage.sh 80
```

**Functions**

```sh
cd functions
npm ci
npm run lint
npm run build
npm run typecheck
npm test                 # unit testleri
npm run test:rules       # Firestore Rules (emulator)
npm run test:privacy     # hesap silme kaskadı (Firestore + Auth emulator)
npm run test:emulator    # analiz journal ve kurtarma senaryoları (emulator)
```

Emulator testleri `firebase-tools` sürümünü `npx` ile sabitler ve yalnız
`demo-karar` demo projesine bağlanır; canlı projeye dokunmaz.

**Firebase yapılandırması:** İstemci Firebase yapılandırmaları secret değildir
ve repoda izlenir: Dart seçenekleri (development + production), iOS
Development/Production `GoogleService-Info.plist` dosyaları ve Android release
`google-services.json`. Android debug `google-services.json` repoda izlenmez.

**Secret'lar:** Gerçek AI analizi `OPENAI_API_KEY` secret'ını gerektirir
(production'da Secret Manager). CI hiçbir secret kullanmaz; unit ve emulator
testleri gerçek sağlayıcıya bağlanmaz. Yerel emulator'da gerçek çağrı
gerekirse `functions/.secret.local.example` şablonu kullanılır;
`.secret.local` git tarafından yok sayılır.

**Canlı duman testi:** `scripts/smoke/live_smoke_test.mjs` canlı projeye
bağlanır ve istemci anahtarını yalnız `FIREBASE_WEB_API_KEY` ortam
değişkeninden okur. CI bu testi çalıştırmaz; yalnız yapılandırma birim
testlerini çalıştırır (`npm test --prefix scripts/smoke`).

## Kalite kapıları

Her pull request ve `main` push'unda [CI](.github/workflows/ci.yaml) şu
işleri çalıştırır:

- **security:** yayın ve credential guard (`scripts/check_publication.py`),
  git geçmişinde gitleaks taraması, smoke bağımlılık denetimi ve birim testleri
- **flutter:** format denetimi, `flutter analyze --fatal-infos`, katman
  kuralları, `flutter test --coverage` ve **minimum %80 kapsam**
- **functions:** `npm audit`, lint, build, typecheck, unit, Firestore Rules,
  privacy ve emulator testleri
- **codeql:** CodeQL statik analizi (JavaScript/TypeScript)

## Belgeler

| Belge | İçerik |
|---|---|
| [Teknik mimari](docs/TEKNIK-MIMARI.md) | Katmanlar, veri modeli, güvenlik, ADR'ler |
| [Release runbook](docs/RELEASE-RUNBOOK.md) | Yayın kapıları, backup/restore, App Check, rollback |
| [Monitoring](docs/MONITORING-PANOSU.md) | Log olayları, canlı alarmlar, filtre sözleşmesi |
| [Veri akışı envanteri](docs/privacy/DATA-FLOW-INVENTORY.md) | Hangi veri nereye gider |
| [Gizlilik politikası](hosting/privacy/index.html) | Yayınlanan gizlilik politikasının kaynağı |
| [Google Play Data Safety](docs/store/GOOGLE-PLAY-DATA-SAFETY.md) | Play veri güvenliği beyanı hazırlığı |
| [App Store Privacy](docs/store/APP-STORE-PRIVACY.md) | App Store gizlilik beyanı hazırlığı |
| [Restore tatbikatı kanıtı](docs/operations/RESTORE-DRILL-2026-09-14.md) | 2026-09-14 tatbikatı (sanitize) |
| [Checker rollout kanıtı](docs/operations/BACKUP-CHECKER-ROLLOUT-2026-09-21.md) | Yedek tazelik kontrolünün canlıya alınması (sanitize) |
| [PRD](docs/PRD.md) | Ürün gereksinimleri |
| [Katkı rehberi](CONTRIBUTING.md) | Branch, commit ve PR kuralları |

## Bilinen sınırlar

- Uygulama mağazalarda yayınlanmadı; imzalı build ve fiziksel cihaz testleri
  (Paket 6F) bekliyor.
- Production backend, repodaki son sürümün gerisindedir.
- App Check provider kayıtları ve gerçek cihaz token doğrulaması (Paket 6E)
  tamamlanmadı.
- Yedek tazeliği alarmının gerçek bir kesintide tetiklendiği henüz gözlenmedi;
  kontrolün çalıştığı doğrulandı, alarmın ateşlendiği doğrulanmadı.
- `riverpod_lint` / `custom_lint` analyzer uyumsuzluğu nedeniyle geçici olarak
  devre dışı; katman kuralları `scripts/check_layers.sh` ile denetlenir.
