# Monitoring Panosu ve Alarm Eşikleri

| | |
|---|---|
| **Sürüm** | v3.2 — 21 Eylül 2026 (6C4 backup freshness checker **canlıda**) |
| **Önceki sürümler** | v3.1 · v3.0 — 16 Eylül 2026 · v2.0 — 9 Eylül 2026 (İş Paketi 6A) · v1.0 — 8 Temmuz 2026 (**geçersizdi**) — bkz. §0 |
| **Kanıt kaynağı** | 6C1 salt okunur keşif · 6C2 e-posta teslimat testi · 6C3 kalıcı kurulum · 6C4 checker rollout'u |
| **İlişkili** | `functions/src/core/logger.ts`, `docs/RELEASE-RUNBOOK.md` |

> **Public repo kuralı.** Bu belge resource ID, e-posta adresi, bütçe tutarı
> veya billing hesap kimliği **içermez**.

---

## 0. Önceki sürümlerin düzeltilen yanlışları

### 0.1 v1.0 (8 Temmuz 2026)

Bu belgenin ilk sürümü, **hiç uygulanmamış** bileşenleri uygulanmış gibi
anlatıyordu. Düzeltmeler:

| v1.0 iddiası | Gerçek |
|---|---|
| "Araçlar: Firebase Analytics + Crashlytics" | `firebase_analytics` bağımlılık ağacında **YOK** (`pubspec.yaml`). Crashlytics vardır. |
| "Flutter istemci ──► Firebase Analytics ──► BigQuery export" | Böyle bir akış **YOK**. Analytics SDK'sı yok, dolayısıyla BigQuery export'u da yok. |
| "§2 İstemci olay şeması (**uygulandı** — analytics_service.dart)" | `AnalyticsService` bir **dormant arayüzdür**; tek uygulaması `NoopAnalyticsService` ve platform kanalına hiçbir şey göndermez. |
| "consent kapısının arkasında (`analyticsConsentProvider`)" | Böyle bir provider **YOK**. Analytics "kapalı" değil, **hiç uygulanmamıştır**. |
| "Log-based metric'ler ... oluşturulur" (yapılmış gibi) | 9 Eylül 2026 itibarıyla production'da 0 log-based metric, 0 alert policy, 0 notification channel vardı. Güncel canlı durum: §2. |

> **Ayrım:** *"kapalı"* bir SDK'nın var olup devre dışı bırakılması demektir.
> Burada durum farklıdır: **SDK yoktur**. Bu, mağaza beyanlarının ve gizlilik
> politikasının dayandığı gerçektir (`test/release/analytics_dormancy_test.dart`).

### 0.2 v2.0 (9 Eylül 2026) — 6C1 kanıtıyla düzeltildi

| v2.0 ifadesi | Gerçek |
|---|---|
| Her log satırında `message` = olay adı | Yalnız INFO/WARN için doğru. ERROR seviyesinde firebase-functions SDK'sı `message` alanını `Error: <olay>` + stack trace biçimine çevirir. |
| Tüm alarmlar için filtre kalıbı `jsonPayload.message="<olay>"` | ERROR olaylarında bu eşitlik **hiç eşleşmez**; anchored regex gerekir (§3.2). |
| `reservation_settlement_failed` ve `reservation_reconcile_failed` ek alanlarında `name` | Böyle bir alan **yoktur**. |
| `request_failed_unexpected` ek alanı yok ("—") | Gerçek alanlar `errorCode` ve `errorType`. |
| Olay tablosu koddaki tüm olayları kapsıyor | 4 olay eksikti: `analysis_completed`, `analysis_superseded`, `reward_callback`, `reward_callback_invalid_signature`. |
| "Billing budget alarmı: Yok" | Hesap geneli bir budget zaten vardı; artık projeye özel budget da var (§2.4). |
| App Check reddi = "Cloud Run 4xx" | HTTP 401 App Check'e özgü değildir; doğru sinyal `jsonPayload.verifications.app` alanıdır (§3.4). |
| Cloud Run 5xx oranı >%1 / 5 dk | Sıfıra yakın trafikte yüzde eşiği anlamsızdır; mutlak sayı eşiği kullanılır (§3.5). |

---

## 1. Bugün gerçekten uygulanmış olan

### 1.1 Yapılandırılmış Functions log'u — UYGULANDI

`functions/src/core/logger.ts`:

- Ham UID **loglanmaz**; `hashUid` ile SHA-256'nın ilk 12 karakteri (`uidHash`).
- `FORBIDDEN_FIELDS` (title, options, criteria, pros, cons, summary, content,
  prompt, uid, token…) ve secret regex'leri ile alanlar **çalışma zamanında
  ayıklanır**.
- Değer uzunluğu, dizi boyutu ve derinlik sınırlıdır.
- Her satır `jsonPayload` = `{message, fn, jobId, uidHash, …}` taşır.
  - **INFO / WARN:** `jsonPayload.message` birebir olay adıdır.
  - **ERROR:** `jsonPayload.message` = `Error: <olay>` + stack trace.
    Birebir eşitlik bu olayları **yakalamaz** (§3.2).
- `uidHash` pseudonim, `jobId` yüksek cardinality'dir: metric label'ı veya
  label extractor olarak **kullanılmaz**.
- Log adı seviyeye göre değişir (INFO/DEBUG → `run.googleapis.com/stdout`,
  WARNING/ERROR → `run.googleapis.com/stderr`); filtreler log adına bağlanmaz.

**Production backend güncel değil:** production'daki kod repodaki son sürümün
gerisindedir. Örneğin production'da `request_failed` hâlâ eski `errorMessage`
alanını taşır; bu alan hiçbir filtre veya label'da kullanılmaz.

### 1.2 Üretilen olaylar (koddan türetildi)

Tablo `functions/src` taranarak üretilmiştir (`log(...)` ve doğrudan
`logger.<seviye>(...)` çağrıları); elle bakımı yapılmaz — değişiklik olursa
buradan yeniden türetin. Canlı kanıt sütunu 6C1 tarihli gözlemdir.

| Olay | Seviye | Kaynak | Ek alanlar | Canlı kanıt (6C1) |
|---|---|---|---|---|
| `request_started` | info | `middleware/context.ts` | `appCheckVerified`, `authProvider` | VERIFIED |
| `request_failed` | warn | `core/errors.ts` | `errorCode` | VERIFIED |
| `request_failed_unexpected` | error | `core/errors.ts` | `errorCode`, `errorType` | CODE-CONTRACT-ONLY |
| `analysis_failed` | warn | `ai/analyze.ts` | `errorCode` | VERIFIED |
| `analysis_completed` | info | `ai/analyze_service.ts` | `model`, `promptVersion`, `tokensIn`, `tokensOut`, `costUsd`, `durationMs` | VERIFIED |
| `analysis_superseded` | info | `ai/analyze_service.ts` | `analysis_completed` ile aynı | CODE-CONTRACT-ONLY |
| `analysis_applied_without_credit` | warn | `ai/analyze_service.ts` | `reason` | CODE-CONTRACT-ONLY |
| `reservation_settlement_failed` | error | `ai/analyze_service.ts` | `targetState`, `billed`, `errorType` | CODE-CONTRACT-ONLY |
| `reservations_reconciled` | info | `ai/analyze_service.ts` | `recovered` | CODE-CONTRACT-ONLY |
| `reservation_reconcile_failed` | warn | `ai/analyze_service.ts` | `errorType` | CODE-CONTRACT-ONLY |
| `account_deleted` | info | `privacy/deleteAccount.ts` | `deleted`, `barrierFinalized` | CODE-CONTRACT-ONLY |
| `account_deletion_barrier_not_finalized` | warn | `privacy/deleteAccount.ts` | `reason` | CODE-CONTRACT-ONLY |
| `account_deletion_failed` | error | `privacy/deleteAccount.ts` | `failureStage`, `causeType`, `causeCode` | CODE-CONTRACT-ONLY |
| `reward_ticket_created` | info | `rewards/createRewardTicket.ts` | `ticketId` | Fonksiyon production'da yok |
| `reward_callback` | info | `rewards/admobRewardCallback.ts` (doğrudan `logger`) | `outcome`, `transactionId`, `ticketId` | Fonksiyon production'da yok |
| `reward_callback_invalid_signature` | warn | `rewards/admobRewardCallback.ts` (doğrudan `logger`) | — | Fonksiyon production'da yok |
| `backup_check_heartbeat` | info | `backup/check_backup_freshness.ts` | `checkResult`, `ageHours`, `thresholdHours`, `backupCount`, `readyDailyCount`, `unexpectedCount`, `location`, `database`, `errorType` | VERIFIED |
| `backup_freshness_stale` | warn | `backup/check_backup_freshness.ts` | `reason`, `checkResult`, `ageHours`, `thresholdHours`, `backupCount`, `readyDailyCount`, `location`, `database` | CODE-CONTRACT-ONLY |
| `backup_state_unexpected` | warn | `backup/check_backup_freshness.ts` | `state`, `ageHours`, `location`, `database` | CODE-CONTRACT-ONLY |
| `backup_check_failed` | error | `backup/check_backup_freshness.ts` | `errorType`, `httpStatus`, `location`, `database` | CODE-CONTRACT-ONLY |

- **Çift emisyon:** `analyzeDecision`'da her `AppError` iki WARN satırı üretir
  (`analysis_failed` + `request_failed`). Sayımlar yalnız birine dayanır.
- **VERIFIED:** canlı log örneğiyle eşleşti. **CODE-CONTRACT-ONLY:** kod, SDK
  kaynağı ve yerel çalışma zamanıyla doğrulandı; canlı örnek henüz yok.

### 1.3 Firebase SDK seviyesindeki sinyaller (uygulama kodundan önce)

| Mesaj | Seviye ve payload | Tetikleyen durum |
|---|---|---|
| "Callable request verification passed" | DEBUG, `jsonPayload.verifications{app,auth}` + label `firebase-log-type=callable-request-verification` | App Check token'ı VALID **veya MISSING** |
| "Callable request verification failed: …" | WARNING, aynı yapı | App Check veya Auth token'ı INVALID |
| "Failed to validate AppCheck token." | WARNING, `textPayload` | INVALID token |

Ek alanı olmayan SDK mesajları Cloud Logging'de `textPayload` olarak görünür;
uygulama olayları ek alan taşıdığı için `jsonPayload`'da kalır.

### 1.4 App Check enforcement — production'da AKTİF

- Production'daki `analyzeDecision` ve `deleteAccount` callable'ları
  `enforceAppCheck: true` ile çalışıyor; App Check **zaten enforce ediliyor**.
- Canlı kanıt (6C1, 30 günlük pencere): MISSING ve INVALID token'lı isteklerin
  tamamı uygulama koduna ulaşmadan HTTP 401 aldı; "enforcement devre dışı"
  uyarısı hiç görülmedi.
- Firebase Console'daki servis enforcement kaydının 0 olması, callable kod
  seviyesindeki enforcement'ın kapalı olduğu anlamına **gelmez**.

### 1.5 Crashlytics — UYGULANDI, sanitize edilmiş

`lib/core/services/crash_reporter.dart`: Crashlytics'e giden içerik
`safeCrashError` ile `StateError('Application error (<runtimeType>)')`
biçimine indirgenir. Exception mesajı, `reason`, karar içeriği, UID ve belge
yolu **gönderilmez**.

---

## 2. Canlı monitoring durumu (6C2 / 6C3)

### 2.1 Notification channel

- **1 e-posta kanalı.** Teslimatı gerçek bir sentetik test alarmıyla
  doğrulandı (6C2); geçici test politikası sonra silindi.
- E-posta kanalları için API `verificationStatus` değeri tanımsız döner
  (UNSPECIFIED); e-posta tipi doğrulama adımı gerektirmez.
- Tek kanal şimdilik kabul edildi; ikinci kanal public yayın öncesi yeniden
  değerlendirilecek. Adres bu belgede yayınlanmaz.

### 2.2 Log-based metric'ler — 11 adet

| Log-based metric | Kaynak sinyal | Kapsam | Kanıt |
|---|---|---|---|
| `kk_request_failed_unexpected` | `request_failed_unexpected` | analyzedecision + deleteaccount | CODE-CONTRACT-ONLY |
| `kk_analysis_applied_without_credit` | `analysis_applied_without_credit` | analyzedecision | CODE-CONTRACT-ONLY |
| `kk_reservation_settlement_failed` | `reservation_settlement_failed` | analyzedecision | CODE-CONTRACT-ONLY |
| `kk_reservation_reconcile_failed` | `reservation_reconcile_failed` | analyzedecision | CODE-CONTRACT-ONLY |
| `kk_account_deletion_failed` | `account_deletion_failed` | deleteaccount | CODE-CONTRACT-ONLY |
| `kk_account_deletion_barrier_not_finalized` | `account_deletion_barrier_not_finalized` | deleteaccount | CODE-CONTRACT-ONLY |
| `kk_ai_provider_failure` | `analysis_failed` + `ai-uncertain` / `ai-failed` | analyzedecision | CODE-CONTRACT-ONLY |
| `kk_appcheck_reject` | SDK App Check reddi (MISSING / INVALID) | analyzedecision + deleteaccount | VERIFIED |
| `kk_analysis_completed` | `analysis_completed` | analyzedecision | VERIFIED |
| `kk_backup_check_heartbeat` | `backup_check_heartbeat` | checkbackupfreshness | VERIFIED |
| `kk_backup_freshness_problem` | `backup_freshness_stale` + `backup_state_unexpected` + `backup_check_failed` | checkbackupfreshness | CODE-CONTRACT-ONLY |

Ortak özellikler: DELTA / INT64 sayaç; **label extractor yok**, payload
değeri çıkarılmaz. Cloud Logging'in otomatik eklediği sistem `log` label'ı
(log ID) dışında label yoktur. Metric'ler **geçmiş logları backfill etmez**;
oluşturulmadan önceki olaylar sayılmaz.

### 2.3 Alert policy'ler — 11 adet

| ID | Öncelik | Log-based metric / metrik | Eşik | Pencere | Bildirim |
|---|---|---|---|---|---|
| AL-01 | P2 | `kk_request_failed_unexpected` | >0 | 5 dk | e-posta |
| AL-02 | P1 | `kk_analysis_applied_without_credit` | >0 | 5 dk | e-posta |
| AL-03 | P2 | `kk_reservation_settlement_failed` | >0 | 5 dk | e-posta |
| AL-04 | P3 | `kk_reservation_reconcile_failed` | ≥3 | 60 dk | e-posta |
| AL-05 | P2 | `kk_account_deletion_failed` | >0 | 5 dk | e-posta |
| AL-06 | P1 | `kk_account_deletion_barrier_not_finalized` | >0 | 5 dk | e-posta |
| AL-07 | P3 | `kk_ai_provider_failure` | ≥5 | 15 dk | e-posta |
| AL-08 | P2 | native `run.googleapis.com/request_count` (5xx) | ≥5 | 10 dk | e-posta |
| AL-09 | P3 / OBSERVATION | `kk_appcheck_reject` | >0 | 5 dk | **YOK (bildirimsiz)** |
| AL-10 | P1 | `kk_backup_freshness_problem` | >0 | 60 dk | e-posta |
| AL-11 | P1 | `kk_backup_check_heartbeat` | **metrik yokluğu** 3 saat | 60 dk hizalama | e-posta |

- **10 policy e-posta kanalına bağlı; AL-09 bilerek bildirimsizdir** (Paket 6E'ye kadar).
- `kk_analysis_completed` için **alert policy yoktur**; metric yalnız baseline toplar.
- Eksik veri INACTIVE değerlendirilir. API, INACTIVE ile birlikte sıfır olmayan
  süre istediği için koşul süresi 60 sn'dir.
- API yalnız GT/LT karşılaştırmasını destekler: ≥3 ve ≥5 eşikleri INT64 sayaçta
  özdeş olan >2 ve >4 olarak uygulanır.
- P1: yalnız açılış bildirimi, auto-close 24 saat. P2/P3: açılış ve kapanış
  bildirimi, auto-close 1 saat. Tekrar bildirim kapalı.
- **Tüm eşikler başlangıç önerisidir**; gerçek trafik baseline'ı oluştuktan
  sonra ayarlanacaktır.

### 2.4 Budget bildirimleri

- **Hesap geneli budget:** billing hesabındaki tüm projeleri kapsar; 6C
  kapsamında değiştirilmedi.
- **Projeye özel aylık budget:** yalnız production projesini kapsar; gerçekleşen
  harcamada %50 / %90 / %100 ve tahmini %100 eşiklerinde e-posta kanalına
  bildirim gönderir.
- **Budget harcamayı durdurmaz**, yalnız bildirim üretir.
- **OpenAI maliyeti GCP budget'ına dahil değildir**; LLM harcaması GCP
  faturasında görünmez.
- Tutarlar bu belgede yayınlanmaz.

---

## 3. Filtre sözleşmesi

### 3.1 Kapsam

```text
S_BOTH = resource.type="cloud_run_revision" AND resource.labels.project_id="karar-kocum-production" AND resource.labels.service_name=("analyzedecision" OR "deleteaccount")
S_AN   = resource.type="cloud_run_revision" AND resource.labels.project_id="karar-kocum-production" AND resource.labels.service_name="analyzedecision"
S_DEL  = resource.type="cloud_run_revision" AND resource.labels.project_id="karar-kocum-production" AND resource.labels.service_name="deleteaccount"
S_BK   = resource.type="cloud_run_revision" AND resource.labels.project_id="karar-kocum-production" AND resource.labels.service_name="checkbackupfreshness"
```

Her filtre proje, `cloud_run_revision` ve **exact servis kapsamı** içerir.
Reward fonksiyonları production'da yoktur ve kapsam dışıdır; deploy edilirlerse
kapsama **açıkça** eklenmeleri gerekir.

### 3.2 ERROR olayları — anchored regex

```text
jsonPayload.message=~"^(Error: )?<olay>(\s|$)"
```

- Hem düz olay adını hem SDK'nın `Error: <olay>` + stack trace biçimini yakalar.
- Çapa (anchor) sayesinde bir olay adı, onunla başlayan başka bir olayı
  yakalamaz.
- JSON yapılandırma dosyasına yazarken ters eğik çizgi çiftlenir (`\\s`).
- INFO/WARN olaylarında birebir eşitlik (`=`) kullanılır.

### 3.3 `:` operatörü olay eşlemesinde kullanılmaz

`:` (has) operatörü alt dize eşleştirir: `request_failed` araması
`request_failed_unexpected` olayını da yakalar (6C1'de canlı gösterildi). Bu
yüzden exact olay eşlemesinde `:` operatörü **kullanılmaz**; §3.2 ve eşitlik
kalıbı kullanılır.

### 3.4 App Check reddi

```text
S_BOTH AND labels."firebase-log-type"="callable-request-verification" AND jsonPayload.verifications.app=("MISSING" OR "INVALID")
```

- Filtre mesaj metnine değil, **`jsonPayload.verifications.app` alanına** dayanır:
  MISSING retleri DEBUG seviyesinde "verification passed" mesajıyla loglanır.
- Bu filtreye severity koşulu **eklenmez**; eklenirse MISSING retleri kaçar.
- HTTP 401 tek başına App Check sinyali değildir (geçersiz Auth token ve replay
  reddi de 401 döner).

### 3.5 Cloud Run 5xx

- Native `run.googleapis.com/request_count`, `response_code_class="5xx"`,
  **mutlak sayı** eşiği. Sıfıra yakın trafikte yüzde eşiği kullanılmaz.
- İş sonuçları da 5xx üretir: `ai-unavailable` / `ai-uncertain` 503,
  `ai-failed` / `internal` 500. AL-08, AL-01 ve AL-07 ile birlikte çalabilir.

### 3.6 Reddedilen kalıp: genel `severity>=ERROR` alarmı

Olay koşulu olmayan genel bir `severity>=ERROR` alarmı **kurulmaz**. Deploy veya
probe anında POST kabul eden callable'lara gelen GET istekleri ERROR seviyeli
stack trace üretir (6C1: 30 günde 8 zararsız kayıt). `severity>=ERROR` yalnız
§3.2 regex'iyle birlikte kullanılır.

### 3.7 Canlı log-based metric filtreleri (6C3)

Aşağıdaki filtreler canlıdaki metric'lerle birebir aynıdır (§3.1 kapsam
makrolarıyla kısaltılmıştır). Her biri oluşturulmadan önce Logs API ile parse
ettirildi.

```text
kk_request_failed_unexpected               S_BOTH AND severity>=ERROR AND jsonPayload.message=~"^(Error: )?request_failed_unexpected(\s|$)"
kk_analysis_applied_without_credit         S_AN AND severity=WARNING AND jsonPayload.message="analysis_applied_without_credit"
kk_reservation_settlement_failed           S_AN AND severity>=ERROR AND jsonPayload.message=~"^(Error: )?reservation_settlement_failed(\s|$)"
kk_reservation_reconcile_failed            S_AN AND severity=WARNING AND jsonPayload.message="reservation_reconcile_failed"
kk_account_deletion_failed                 S_DEL AND severity>=ERROR AND jsonPayload.message=~"^(Error: )?account_deletion_failed(\s|$)"
kk_account_deletion_barrier_not_finalized  S_DEL AND severity=WARNING AND jsonPayload.message="account_deletion_barrier_not_finalized"
kk_ai_provider_failure                     S_AN AND jsonPayload.message="analysis_failed" AND jsonPayload.errorCode=("ai-uncertain" OR "ai-failed")
kk_appcheck_reject                         S_BOTH AND labels."firebase-log-type"="callable-request-verification" AND jsonPayload.verifications.app=("MISSING" OR "INVALID")
kk_analysis_completed                      S_AN AND severity=INFO AND jsonPayload.message="analysis_completed"
kk_backup_check_heartbeat                  S_BK AND jsonPayload.message=~"^(Error: )?backup_check_heartbeat(\s|$)"
kk_backup_freshness_problem                S_BK AND jsonPayload.message=~"^(Error: )?(backup_freshness_stale|backup_state_unexpected|backup_check_failed)(\s|$)"
```

---

## 4. Backup freshness — native sinyal YOK, kontrol UYGULAMA KODUNDA

### 4.1 Native sinyaller neden yetmedi

- Zamanlanmış yedeklerin başarısı için Cloud Logging'de **log kaydı yoktur**
  (6C1: beş zamanlanmış yedek çalışmasında sıfır kayıt) ve Firestore'un
  **native bir backup freshness metriği yoktur**.
- `firestore.googleapis.com/storage/backups_storage_bytes` yalnız toplam boyut
  gauge'udur:
  - descriptor örnekleme periyodu **60 saniyedir**;
  - gerçek seri **aralıklı** yayınlanır ve saatlerce boşluk olabilir;
  - yedek boyutu adımları snapshot'tan **11–13 saat sonra** görünebilir;
  - saklama dengesi kurulduğunda eğri düzleşir, kaçan bir yedek görünmez.
- Metric-absence koşulunun azami süresi 23,5 saattir; günlük yedek saati her
  gün değiştiği için (gözlenen fark 26 saate kadar) **yedek metriği üzerinde**
  doğrudan kullanılamaz.

Bu yüzden tazeliği native bir sinyal değil, **uygulama kodu ölçer**.

### 4.2 `checkBackupFreshness` — CANLI

| Parametre | Değer |
|---|---|
| Export | `checkBackupFreshness` (`functions/src/backup/`) |
| Servis | `checkbackupfreshness` (Cloud Run, production Functions bölgesi) |
| Kadans | Saatte bir, **UTC** (`0 * * * *`), tek instance, Scheduler retry yok |
| Eşik | **30 saat** — snapshot saati gün içinde kayar (6B: en büyük aralık ~26 saat), 24 saat yanlış alarm üretirdi |
| Kapsam | Yalnız `(default)` veritabanı ve yedeklerin bulunduğu çoklu bölge |
| Aday seçimi | En yeni **READY** günlük yedek; günlük/haftalık ayrımı `expireTime − snapshotTime` süresinden (7 gün / 28 gün) |
| Runtime kimliği | **Adanmış** service account; tek proje rolü yalnız yedek metadata'sı okur |
| Secret | **Yok** — OpenAI anahtarı dahil hiçbir secret bağlı değil |
| Veri erişimi | Hiçbir Firestore belgesi okunmaz |

| Olay | Seviye | Anlamı |
|---|---|---|
| `backup_check_heartbeat` | info | Kontrol çalıştı. Sonuç `checkResult` alanındadır; sağlıklı da olabilir, problemli de. |
| `backup_freshness_stale` | warn | Uygun READY günlük yedek yok **veya** en yenisi eşikten eski. |
| `backup_state_unexpected` | warn | Normal dışı durumda takılmış ya da zaman damgası bozuk bir yedek gözlendi. |
| `backup_check_failed` | error | API, yetki, zaman aşımı, ayrıştırma veya başka bir kontrol hatası. |

**Heartbeat ile problem ayrımı.** Her çalıştırma **tam bir**
`backup_check_heartbeat` üretir (`checkResult` = `fresh` / `stale` / `failed`).
Sorun varsa **ayrıca** bir problem olayı yazılır. İki alarm iki farklı arızayı
yakalar: AL-11 checker'ın **hiç çalışmamasını**, AL-10 checker'ın **sorun
bulmasını**.

**Hata asla "yedek yok" demek değildir.** 401, 403, zaman aşımı, ayrıştırma
hatası ve ulaşılamayan konum `backup_check_failed` üretir; boş listeye veya
"sağlıklı" sonucuna **dönüştürülmez**. Yanlış proje/konumda istek bile
atılmaz. Bozuk zaman damgası taze sayılmaz.

### 4.3 İlk çalıştırma kanıtı (6C4)

- Metric'ler deploy'dan **önce** oluşturuldu; beklenen servis adı repo export
  sözleşmesinden türetildi ve deploy sonrası gerçek Cloud Run servis
  etiketiyle **yeniden doğrulandı** — ikisi aynı.
- Tek kontrollü manuel çalıştırma **tam bir** heartbeat üretti:
  `checkResult=fresh`, eşik 30 saat, en yeni günlük yedeğin yaşı yaklaşık
  12,4 saat, kapsamda 9 yedek, 7'si READY günlük. Problem olayı **yok**.
- Bir sonraki **zamanlanmış** çalıştırma (saat başı, UTC) manuel müdahale
  olmadan ikinci heartbeat'i üretti.
- Adanmış service account'un tek dar rolü yedek metadata'sını okumaya
  **yetti**; 403 alınmadı ve yetki genişletilmedi.
- Heartbeat metriğinde gerçek veri noktası görüldükten **sonra** AL-11
  oluşturuldu. Problem metriğinde sıfır nokta olması normaldir; sentetik
  problem olayı **üretilmedi**.

### 4.4 Dürüst sınır — AL-11 tetiklenmesi henüz gözlenmedi

AL-11 bir **metrik yokluğu** koşuludur. Heartbeat'in üretildiği doğrulandı,
ancak **koşulun gerçekten tetiklendiği canlıda gözlenmedi**: bunu görmek için
checker'ın 3 saat boyunca hiç çalışmaması gerekir ve bu turda böyle bir kesinti
üretilmedi. Log tabanlı metriklerde yokluk semantiği, serinin veri yazmayı
gerçekten durdurmasına bağlıdır. Bu, gerçek bir kesintide veya ayrı bir
doğrulama turunda (6C5) teyit edilmelidir.

---

## 5. Henüz UYGULANMAMIŞ olanlar

| Bileşen | Durum | Nerede yapılır |
|---|---|---|
| App Check alarmının bildirime bağlanması ve rollout eşiği | **Yok** (AL-09 bildirimsiz) | Paket 6E |
| AL-11 yokluk koşulunun canlı tetiklenme kanıtı | **Yok** — gerçek kesinti gözlenmedi (§4.4) | Paket 6C5 |
| Eşik ayarı (gerçek trafik baseline'ı) | **Yok** | Lansman sonrası |
| İkinci notification channel | **Yok** (tek kanal kabul edildi) | Public yayın öncesi karar |
| Incident owner yedeği | **Yok** (tek sorumlu: proje sahibi) | Public yayın öncesi karar |
| İstemci kullanım analitiği | **Uygulanmadı** (SDK yok) | Ürün kararı; bu sürümün kapsamı değil |
| Dashboard | **Yok** | Gerekirse sonra |
| Uptime check | **Önerilmez:** callable'lar App Check istediği için her zaman 401 döner ve AL-09'u kirletir | — |

---

## 6. Bu belgenin bakımı

- Olay tablosu (§1.2) **koddan türetilir**. `functions/src` altında yeni bir
  `log(...)` veya `logger.<seviye>(...)` çağrısı eklenirse tablo güncellenmelidir
  (`test/release/ops_docs_test.dart` denetler).
- Canlı kaynaklar (§2) değişirse aynı değişiklikte bu belge güncellenmelidir.
- §5'teki hiçbir satır, canlı kanıt olmadan §1 veya §2'ye taşınmamalıdır.
- Bu belge gelecekteki işleri **yapılmış gibi** anlatmaz; v1.0 tam olarak bu
  yüzden geçersiz hâle gelmişti.
