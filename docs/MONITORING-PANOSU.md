# Monitoring Panosu ve Alarm Eşikleri

| | |
|---|---|
| **Sürüm** | v2.0 — 9 Eylül 2026 (İş Paketi 6A) |
| **Önceki sürüm** | v1.0 — 8 Temmuz 2026. **Geçersizdi**: bkz. §0. |
| **İlişkili** | `functions/src/core/logger.ts`, `docs/RELEASE-RUNBOOK.md` |

---

## 0. v1.0'ın düzeltilen yanlışları

Bu belgenin önceki sürümü, **hiç uygulanmamış** bileşenleri uygulanmış gibi
anlatıyordu. Düzeltmeler:

| v1.0 iddiası | Gerçek |
|---|---|
| "Araçlar: Firebase Analytics + Crashlytics" | `firebase_analytics` bağımlılık ağacında **YOK** (`pubspec.yaml`). Crashlytics vardır. |
| "Flutter istemci ──► Firebase Analytics ──► BigQuery export" | Böyle bir akış **YOK**. Analytics SDK'sı yok, dolayısıyla BigQuery export'u da yok. |
| "§2 İstemci olay şeması (**uygulandı** — analytics_service.dart)" | `AnalyticsService` bir **dormant arayüzdür**; tek uygulaması `NoopAnalyticsService` ve platform kanalına hiçbir şey göndermez. |
| "consent kapısının arkasında (`analyticsConsentProvider`)" | Böyle bir provider **YOK**. Analytics "kapalı" değil, **hiç uygulanmamıştır**. |
| "Log-based metric'ler ... oluşturulur" (yapılmış gibi) | Production'da **0 log-based metric**, **0 alert policy**, **0 notification channel**. |

> **Ayrım:** *"kapalı"* bir SDK'nın var olup devre dışı bırakılması demektir.
> Burada durum farklıdır: **SDK yoktur**. Bu, mağaza beyanlarının ve gizlilik
> politikasının dayandığı gerçektir (`test/release/analytics_dormancy_test.dart`).

---

## 1. Bugün gerçekten uygulanmış olan

### 1.1 Yapılandırılmış Functions log'u — UYGULANDI

`functions/src/core/logger.ts`:

- Ham UID **loglanmaz**; `hashUid` ile SHA-256'nın ilk 12 karakteri (`uidHash`).
- `FORBIDDEN_FIELDS` (title, options, criteria, pros, cons, summary, content,
  prompt, uid, token…) ve secret regex'leri ile alanlar **çalışma zamanında
  ayıklanır**.
- Değer uzunluğu, dizi boyutu ve derinlik sınırlıdır.
- Her satır: `message` = olay adı, `jsonPayload` = `{fn, jobId, uidHash, …}`.

### 1.2 Üretilen olaylar (koddan türetildi)

Aşağıdaki tablo `functions/src` taranarak üretilmiştir; elle bakımı
yapılmaz — değişiklik olursa buradan yeniden türetin.

| Olay | Seviye | Kaynak | Ek alanlar |
|---|---|---|---|
| `request_started` | info | `middleware/context.ts:59` | `appCheckVerified`, `authProvider` |
| `request_failed` | warn | `core/errors.ts:147` | `errorCode` |
| `request_failed_unexpected` | error | `core/errors.ts:160` | — |
| `analysis_failed` | warn | `ai/analyze.ts:51` | `errorCode` |
| `analysis_applied_without_credit` | warn | `ai/analyze_service.ts:554` | `reason` |
| `reservation_settlement_failed` | error | `ai/analyze_service.ts:469` | `billed`, `errorType`, `name`, `targetState` |
| `reservation_reconcile_failed` | warn | `ai/analyze_service.ts:491` | `errorType`, `name` |
| `reservations_reconciled` | info | `ai/analyze_service.ts:488` | — |
| `account_deleted` | info | `privacy/deleteAccount.ts:45` | `deleted`, `barrierFinalized` |
| `account_deletion_barrier_not_finalized` | warn | `privacy/deleteAccount.ts:54` | `reason` |
| `account_deletion_failed` | error | `privacy/deleteAccount.ts:65` | sanitize edilmiş tanı |
| `reward_ticket_created` | info | `rewards/createRewardTicket.ts:48` | `ticketId` |

### 1.3 Crashlytics — UYGULANDI, sanitize edilmiş

`lib/core/services/crash_reporter.dart`: Crashlytics'e giden içerik
`safeCrashError` ile `StateError('Application error (<runtimeType>)')`
biçimine indirgenir. Exception mesajı, `reason`, karar içeriği, UID ve belge
yolu **gönderilmez**.

---

## 2. Henüz UYGULANMAMIŞ olanlar

Aşağıdakilerin hiçbiri canlıda yoktur. Bunlar **6C** kapsamındadır ve
canlı GCP mutasyonu gerektirir.

| Bileşen | Durum | Nerede yapılır |
|---|---|---|
| Log-based metric tanımları | **Yok** (production'da 0) | Canlı: Cloud Logging |
| Alert policy'ler | **Yok** (production'da 0) | Canlı: Cloud Monitoring |
| Notification channel | **Yok** (production'da 0) | Canlı + insan kararı |
| Incident owner | **Belirlenmedi** | İnsan kararı |
| Billing budget alarmı | **Yok** | Canlı: Billing |
| İstemci kullanım analitiği | **Uygulanmadı** (SDK yok) | Ürün kararı; bu sürümün kapsamı değil |

### 2.1 Neden bugün alarm kurulamaz

İki bağımlılık var:

1. **Production backend güncel değil.** Canlıdaki `analyzeDecision` ve
   `deleteAccount` eski bir revizyondan gelir; yukarıdaki olay adlarının bir
   kısmı canlı loglarda **henüz üretilmiyor olabilir**. Filtreler, güncel
   backend deploy edildikten sonra **gerçek bir log satırıyla** doğrulanmalıdır.
2. **Gerçek trafik baseline'ı yok.** Uygulama yayınlanmadı. Aşağıdaki
   eşikler bu yüzden **başlangıç önerisidir**; gözlem sonrası ayarlanacaktır.

---

## 3. Önerilen başlangıç alarmları (6C girdisi)

Filtre kalıbı: `resource.type="cloud_run_revision"` +
`jsonPayload.message="<olay>"`. **Her filtre kurulmadan önce canlı bir log
örneğiyle doğrulanmalıdır** — `logger.ts` olay adını log *message*'ı yapar,
alan adı değil.

| # | Amaç | Filtre | Başlangıç eşiği | Gürültü riski | Runbook aksiyonu |
|---|---|---|---|---|---|
| A1 | Beklenmeyen hata | `message="request_failed_unexpected"` | >0 / 5 dk | Düşük | Log incele; hotfix kararı |
| A2 | Sağlayıcı belirsizliği | `message="analysis_failed"` ve `jsonPayload.errorCode` ∈ {`ai-uncertain`,`ai-failed`} | >5 / 15 dk | Orta (OpenAI kesintisi) | Sağlayıcı durumu + journal mutabakatı |
| A3 | Kredi tutarsızlığı | `message="analysis_applied_without_credit"` | >0 / 1 sa | Çok düşük | **P1** — muhasebe denetimi |
| A4 | Rezervasyon kapanmadı | `message="reservation_settlement_failed"` | >0 / 15 dk | Düşük | Orphan recovery doğrula |
| A5 | Silme yarım kaldı | `message="account_deletion_barrier_not_finalized"` | >0 / 1 sa | Çok düşük | **KVKK** — bariyeri elle sonlandır |
| A6 | Silme başarısız | `message="account_deletion_failed"` | >0 / 1 sa | Düşük | Kullanıcıya dönüş + tekrar |
| A7 | App Check reddi | Cloud Run 4xx + App Check reddi | Rollout'ta yalnız **gözlem** | **Yüksek** | Enforcement'ı geri al |
| A8 | Maliyet sıçraması | Billing budget (aylık bütçenin %50/%90'ı) | İnsan kararı | Düşük | `MAX_DAILY_USD` frenini gözden geçir |
| A9 | Fonksiyon sağlığı | Cloud Run 5xx oranı | >%1 / 5 dk | Orta | Bilinen iyi commit'ten yeniden deploy |

---

## 4. Bu belgenin bakımı

- Olay tablosu (§1.2) **koddan türetilir**. `functions/src` altında yeni bir
  `log(...)` çağrısı eklenirse tablo güncellenmelidir.
- §2'deki hiçbir satır, canlı kanıt olmadan §1'e taşınmamalıdır.
- Bu belge gelecekteki işleri **yapılmış gibi** anlatmaz; v1.0 tam olarak bu
  yüzden geçersiz hâle gelmişti.
