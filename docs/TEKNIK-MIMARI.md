# Karar Veriyorum — Teknik Mimari Dokümanı

| | |
|---|---|
| **Doküman Sürümü** | v1.0 |
| **Tarih** | 8 Temmuz 2026 |
| **Temel Doküman** | [PRD.md](./PRD.md) v1.0 |
| **Hedef** | Üretime hazır, App Store / Google Play'de yayınlanabilir MVP mimarisi |

---

## 1. Mimari Genel Bakış

### 1.1 Yüksek Seviye Diyagram

```
┌─────────────────────────────────────────────────────────────┐
│                     FLUTTER İSTEMCİ                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Presentation  │→│    Domain     │←│     Data      │       │
│  │ (UI+Riverpod) │  │ (Entity+UseCase)│ (Repo impl+DTO)│     │
│  └──────────────┘  └──────────────┘  └──────┬───────┘       │
└─────────────────────────────────────────────┼───────────────┘
                                              │
              ┌───────────────────────────────┼───────────────┐
              │                               ▼               │
              │  FIREBASE                                     │
              │  ┌────────┐ ┌───────────┐ ┌────────────────┐  │
              │  │  Auth  │ │ Firestore │ │ Cloud Functions │  │
              │  └────────┘ └───────────┘ │  (AI Proxy +    │  │
              │  ┌────────┐ ┌───────────┐ │   kota + billing│  │
              │  │Analytics│ │Remote Cfg │ │   webhook)      │  │
              │  └────────┘ └───────────┘ └───────┬────────┘  │
              │  ┌────────┐ ┌───────────┐         │           │
              │  │Crashlyt.│ │  Storage  │         ▼           │
              │  └────────┘ └───────────┘   ┌──────────┐      │
              └──────────────────────────────│ LLM API  │──────┘
                                             │(sunucuda │
                                             │ anahtar) │
                                             └──────────┘
   ┌──────────────┐        ┌──────────────────────────┐
   │  RevenueCat  │◄──────►│ App Store / Play Billing │
   └──────────────┘        └──────────────────────────┘
```

### 1.2 Temel Mimari Kararlar (ADR Özeti)

| # | Karar | Gerekçe | Alternatif (red nedeni) |
|---|---|---|---|
| AD-1 | **LLM çağrıları yalnızca Cloud Functions üzerinden** | API anahtarı istemciye asla inmez; rate limit, kota, moderasyon tek noktada | İstemciden doğrudan çağrı (anahtar sızıntısı, kota bypass) |
| AD-2 | **Skor motoru tamamen istemcide, deterministik** | What-if simülasyonu < 100 ms şartı; ağ bağımlılığı yok; %100 birim test | Sunucuda hesap (gecikme, maliyet) |
| AD-3 | **Offline-first: Firestore offline persistence + anonim oturum** | US-E1: girişsiz ilk karar; taslaklar cihazda yaşar | Salt online (aktivasyon hunisini öldürür) |
| AD-4 | **RevenueCat ile abonelik soyutlaması** | İki mağaza + web geliştirme hızı; receipt doğrulama ve webhook hazır | Ham StoreKit2/Play Billing (2× iş, doğrulama sunucusu yazmak gerek) |
| AD-5 | **Riverpod 2 (code-gen ile) — BLoC değil** | PRD şartı + derleme zamanı güvenliği, kolay test, `AsyncValue` ile hata/yükleme durumu standardı | BLoC (törensel kod fazlalığı) |
| AD-6 | **Freezed + json_serializable ile immutable modeller** | PRD şartı; kopya-ile-değiştir (copyWith) desenine oturan puan matrisi | Elle model (hata riski) |
| AD-7 | **AI çıktısı yapılandırılmış JSON (tool/structured output)** | Sonuç ekranı alanlara ayrılmış render ister; serbest metin parse edilmez | Serbest metin (kırılgan parse) |
| AD-8 | **Feature-first klasörleme, katman-first değil** | Ekip küçük; özellik bazlı gezinme hızı; katmanlar özellik içinde korunur | Katman-first (dosya zıplama maliyeti) |

---

## 2. Proje Yapısı

```
karar_veriyorum/
├── lib/
│   ├── main.dart                      # bootstrap: Firebase.init, ProviderScope, runApp
│   ├── app.dart                       # MaterialApp.router, tema, locale
│   │
│   ├── core/                          # özelliklerden bağımsız altyapı
│   │   ├── config/                    # ortam (dev/staging/prod), flavor tanımları
│   │   ├── constants/                 # limitler (min 2 / max 10 seçenek vb.)
│   │   ├── error/                     # Failure hiyerarşisi, Result<T> tipi
│   │   ├── extensions/
│   │   ├── l10n/                      # arb dosyaları (tr, en)
│   │   ├── network/                   # Dio kurulumu, interceptor'lar
│   │   ├── router/                    # GoRouter yapılandırması, guard'lar
│   │   ├── services/                  # analytics, remote_config, crash sarmalayıcıları
│   │   ├── theme/                     # Material 3 ColorScheme, tipografi, spacing token'ları
│   │   └── widgets/                   # paylaşılan UI (AppButton, EmptyState, ErrorView…)
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/                  # repositories/ (impl), datasources/, dtos/
│   │   │   ├── domain/                # entities/, repositories/ (abstract), usecases/
│   │   │   └── presentation/          # screens/, widgets/, providers/
│   │   ├── decision/                  # karar CRUD, seçenek, artı/eksi, kriter
│   │   ├── scoring/                   # skor motoru (SAF DART — flutter import YOK)
│   │   ├── ai_analysis/               # AI proxy istemcisi, streaming, analiz durumu
│   │   ├── results/                   # sonuç ekranı, what-if simülatörü
│   │   ├── history/                   # geçmiş, arama, filtre, favori
│   │   ├── paywall/                   # abonelik, kota, RevenueCat entegrasyonu
│   │   ├── report/                    # PDF üretimi, paylaşım kartı
│   │   ├── onboarding/
│   │   └── settings/                  # profil, tema, dil, hesap silme, veri indirme
│   │
│   └── firebase_options.dart          # flutterfire configure çıktısı (flavor başına)
│
├── functions/                         # Cloud Functions (TypeScript)
│   ├── src/
│   │   ├── ai/                        # analyze.ts, suggestCriteria.ts, scoreOptions.ts
│   │   ├── billing/                   # revenuecatWebhook.ts → users/{uid}.plan günceller
│   │   ├── privacy/                   # deleteAccount.ts, exportData.ts
│   │   ├── quota/                     # kota kontrol middleware
│   │   └── moderation/                # hassas içerik ön filtresi
│   └── test/
│
├── test/                              # unit + widget (lib yapısını aynalar)
├── integration_test/
├── firestore.rules
├── firestore.indexes.json
└── .github/workflows/ci.yaml
```

**Katman bağımlılık kuralı (lint ile zorlanır):**
`presentation → domain ← data` · domain hiçbir şeye bağımlı değil (saf Dart) · `core` herkes tarafından kullanılabilir ama `features/`'ı import edemez.

---

## 3. Domain Katmanı

### 3.1 Çekirdek Entity'ler (Freezed)

```dart
@freezed
class Decision with _$Decision {
  const factory Decision({
    required String id,
    required String ownerUid,          // anonim uid olabilir
    required String title,             // 3-100 karakter (validator)
    String? templateId,
    required DecisionStatus status,    // draft | analyzed | archived
    required List<Option> options,     // 2-10 (invariant: domain'de doğrulanır)
    required List<Criterion> criteria,
    required ScoreMatrix scores,
    AiAnalysis? aiAnalysis,
    DecisionResult? result,
    required bool isFavorite,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Decision;
}

@freezed
class Option with _$Option {
  const factory Option({
    required String id,
    required String title,
    String? description,
    String? imageUrl,
    @Default([]) List<String> pros,    // madde başına 1-140 karakter
    @Default([]) List<String> cons,
  }) = _Option;
}

@freezed
class Criterion with _$Criterion {
  const factory Criterion({
    required String id,
    required String name,
    required int weight,               // 1-10
    required CriterionSource source,   // user | aiSuggested
  }) = _Criterion;
}

/// scores[optionId][criterionId] = CellScore(value: 1-10, source: manual|ai)
typedef ScoreMatrix = Map<String, Map<String, CellScore>>;

@freezed
class AiAnalysis with _$AiAnalysis {
  const factory AiAnalysis({
    required String summary,
    required List<String> risks,
    required Map<String, OptionInsight> perOption,  // güçlü/zayıf yönler
    required List<String> suggestedCriteria,
    required Confidence confidence,     // low | medium | high
    required String confidenceReason,
    required AiTier tier,               // basic | advanced
    required DateTime generatedAt,
  }) = _AiAnalysis;
}
```

### 3.2 Skor Motoru (features/scoring — saf Dart, %100 test kapsamı)

```dart
class ScoringEngine {
  /// Ağırlıklı skor: her seçenek için
  ///   skor = Σ (kriterAğırlığı_normalize × hücrePuanı) → 0-100 ölçeğine
  /// Ağırlıklar toplamı 1'e normalize edilir; eksik hücre = analiz engeli
  /// (partial analize izin verilmez — sonuç yanıltıcı olur).
  DecisionResult compute({
    required List<Option> options,
    required List<Criterion> criteria,
    required ScoreMatrix scores,
  });
}
```

- **Deterministik ve senkron** → what-if simülatöründe her slider hareketi anında yeniden hesap (< 100 ms şartı, pratikte < 1 ms).
- Güven seviyesi girdisi: skor farkı (1. ve 2. seçenek arası), kriter sayısı, AI/manuel puan oranı → `Confidence` hesabı da bu motorda (AI'dan gelen güven yorumuyla birleşir).

### 3.3 Use Case Örnekleri

| Use case | İmza | Not |
|---|---|---|
| `CreateDecision` | `(title, templateId?) → Result<Decision>` | kota kontrolü ÖNCE (yerel sayaç + sunucu doğrulaması) |
| `RequestAiAnalysis` | `(decisionId) → Stream<AiAnalysisChunk>` | Functions'a çağrı; streaming |
| `ComputeResult` | `(decision) → DecisionResult` | tamamen yerel |
| `UpdateCriterionWeight` | `(decisionId, criterionId, weight) → Decision` | sonucu anında yeniden hesaplar |
| `ExportPdf` | `(decisionId) → Result<File>` | premium guard içerir |
| `DeleteAccount` | `() → Result<void>` | Functions `deleteAccount` çağrısı + yerel temizlik |

---

## 4. Data Katmanı

### 4.1 Repository Deseni

```dart
// domain/repositories/decision_repository.dart (abstract — domain'de)
abstract class DecisionRepository {
  Stream<List<Decision>> watchAll();
  Future<Decision?> getById(String id);
  Future<void> upsert(Decision decision);
  Future<void> delete(String id);
}

// data/repositories/decision_repository_impl.dart
// Firestore offline persistence AÇIK → tek veri kaynağı Firestore SDK cache'i.
// Ayrı bir yerel DB (Isar/Hive) MVP'de YOK — Firestore cache offline senaryoyu karşılar.
// Anonim kullanıcı da Firestore'a yazar (anonim uid ile) → hesap yükseltmede
// linkWithCredential sonrası veri zaten aynı uid altında kalır (taşıma gerekmez).
```

**Kritik karar — anonim → hesap taşıma:** Firebase Auth `linkWithCredential` kullanılır; anonim uid korunur, Firestore verisi el değmeden kalır. Yalnızca link çakışması (hedef hesap zaten var) durumunda Functions tarafında `mergeAccounts` ile taşıma yapılır.

### 4.2 Firestore Şeması

```
users/{uid}
  ├─ displayName, email, photoUrl, locale
  ├─ plan: "free" | "premium"            # YALNIZ Functions yazar (billing webhook)
  ├─ planExpiresAt: Timestamp?
  ├─ quota: { month: "2026-07", used: 3 } # YALNIZ Functions yazar
  ├─ createdAt, lastActiveAt
  └─ consent: { analytics: bool, updatedAt }

users/{uid}/decisions/{decisionId}
  ├─ title, templateId?, status, isFavorite
  ├─ options: [ {id, title, description?, imageUrl?, pros[], cons[]} ]   # gömülü
  ├─ criteria: [ {id, name, weight, source} ]                           # gömülü
  ├─ scores: { optionId: { criterionId: {value, source} } }             # gömülü
  ├─ aiAnalysis: {...} | null
  ├─ result: {...} | null
  ├─ searchTokens: string[]               # başlıktan üretilen küçük-harf token'lar (arama için)
  └─ createdAt, updatedAt

templates/{templateId}                     # global, salt okunur (Remote Config'ten de beslenebilir)
  ├─ title, category, locale
  ├─ suggestedCriteria: [ {name, defaultWeight} ]
  └─ order, isActive

aiJobs/{jobId}                             # Functions iç muhasebesi (istemciye kapalı)
  ├─ uid, decisionId, tier, status, tokenCost, createdAt
```

**Neden gömülü (embedded) doküman?** Bir karar bütünüyle yüklenir/kaydedilir; seçenek ve kriter sayıları küçük ve sınırlı (≤10 ve pratikte ≤15 kriter) → 1 MB doküman limitine uzak, tek okuma = tek karar, senkron basit. Alt koleksiyon parçalaması gereksiz karmaşıklık olurdu.

**İndeksler (`firestore.indexes.json`):**
- `decisions`: (`ownerUid` otomatik — koleksiyon zaten kullanıcı altında) `status + updatedAt desc`, `isFavorite + updatedAt desc`, `searchTokens array-contains + updatedAt desc`

### 4.3 Firestore Security Rules (özet)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {

    match /users/{uid} {
      allow read: if request.auth != null && request.auth.uid == uid;
      // plan ve quota alanlarını istemci DEĞİŞTİREMEZ:
      allow update: if request.auth.uid == uid
        && !request.resource.data.diff(resource.data)
             .affectedKeys().hasAny(['plan','planExpiresAt','quota']);
      allow create: if request.auth.uid == uid
        && request.resource.data.plan == 'free';
      allow delete: if false;                    // silme yalnız Functions üzerinden

      match /decisions/{id} {
        allow read, write: if request.auth.uid == uid
          && request.resource.data.options.size() >= 2
          && request.resource.data.options.size() <= 10
          && request.resource.data.title.size() >= 3
          && request.resource.data.title.size() <= 100;
        // aiAnalysis alanı istemciden yazılamaz (yalnız Functions):
        // ayrı bir 'aiAnalysisLocked' custom claim yaklaşımı yerine
        // Functions admin SDK ile yazar; istemci update'inde alan diff kontrolü yapılır.
      }
    }

    match /templates/{id} { allow read: if true; allow write: if false; }
    match /aiJobs/{id}    { allow read, write: if false; }  // yalnız admin SDK
  }
}
```

---

## 5. Cloud Functions (TypeScript, 2. nesil)

### 5.1 Fonksiyon Envanteri

| Fonksiyon | Tetikleyici | Görev |
|---|---|---|
| `analyzeDecision` | Callable (auth zorunlu) | Moderasyon → kota kontrolü → LLM çağrısı (structured output) → `aiAnalysis` alanını Firestore'a yaz → kota artır. **Streaming:** yanıt SSE ile istemciye akar, tamamlanınca Firestore'a kalıcı yazılır |
| `suggestCriteria` | Callable | Hafif model ile eksik kriter önerisi (kota: ayrı, daha cömert sayaç) |
| `scoreOptions` | Callable (premium guard) | AI otomatik puan matrisi üretimi |
| `revenuecatWebhook` | HTTPS (imza doğrulamalı) | `INITIAL_PURCHASE / RENEWAL / CANCELLATION / EXPIRATION` → `users/{uid}.plan` güncelle |
| `deleteAccount` | Callable | Auth kaydı + tüm Firestore verisi + Storage görselleri kaskad silme |
| `exportData` | Callable | Kullanıcı verisini JSON'a paketle, kısa ömürlü imzalı Storage URL'i döndür |
| `resetMonthlyQuota` | Scheduled (aylık) | gerek YOK — kota `{month, used}` çifti; ay değişince istemci/fonksiyon sıfır kabul eder (lazy reset, cron maliyeti yok) |

### 5.2 AI Proxy Boru Hattı (`analyzeDecision`)

```
İstek (decisionId, tier)
  → [1] Auth doğrula (anonim dahil; App Check zorunlu)
  → [2] Firestore'dan kararı OKU (istemciden veri alma — istemci payload'ına güvenme)
  → [3] Moderasyon ön filtresi (hassas alan: kendine zarar, tıbbi/hukuki yüksek risk
        → analiz yerine güvenli yönlendirme yanıtı döndür, kota HARCANMAZ)
  → [4] Kota kontrolü (free: aylık 5; transaction ile artır — yarış durumu yok)
  → [5] Tier seçimi: free → küçük model (ör. Haiku sınıfı)
                     premium → büyük model (ör. Sonnet sınıfı)
  → [6] Prompt derleme (sistem şablonu + karar verisi; kullanıcı metni delimiter içinde,
        prompt injection'a karşı "veri olarak işle" çerçevesi)
  → [7] LLM çağrısı — structured output (JSON şema: summary, risks[], perOption{},
        suggestedCriteria[], confidence, confidenceReason)
  → [8] Şema doğrulama (zod) — geçmezse 1 kez düzeltme denemesi, sonra hata
  → [9] Firestore'a yaz + aiJobs kaydı (maliyet muhasebesi) + Analytics event
  → Yanıt: streaming chunk'lar + final yapılandırılmış obje
```

**Rate limiting:** kullanıcı başına dakikada 3 / saatte 10 AI çağrısı (Firestore transaction sayaç veya Redis-siz basit sliding window `aiJobs` sorgusu). **App Check** (DeviceCheck/Play Integrity) tüm callable'larda zorunlu → bot/emülatör istismarını keser.

**Maliyet muhasebesi:** her çağrının token maliyeti `aiJobs`'a yazılır → PRD'deki "maliyet/karar" metriği BigQuery export ile panoda izlenir.

### 5.3 Gizli Anahtar Yönetimi

- LLM API anahtarı: **Secret Manager** (`defineSecret`) — kodda, env dosyasında, istemcide asla.
- RevenueCat webhook imza anahtarı: Secret Manager.
- İstemcide secure storage (`flutter_secure_storage`): yalnız oturum yenileme token'ları (Firebase SDK zaten yönetir) ve kullanıcı tercihi hassas bayraklar.

---

## 6. Presentation Katmanı

### 6.1 Riverpod Provider Mimarisi

```dart
// Katmanlı provider grafiği (code-gen: @riverpod)

// 1) Altyapı
@Riverpod(keepAlive: true) FirebaseAuth firebaseAuth(...)
@Riverpod(keepAlive: true) FirebaseFirestore firestore(...)

// 2) Repository (domain arayüzü → data impl bağlama noktası; testte override edilir)
@Riverpod(keepAlive: true) DecisionRepository decisionRepository(...)

// 3) Oturum & yetki
@Riverpod(keepAlive: true) Stream<AppUser?> authState(...)
@Riverpod(keepAlive: true) Stream<Plan> currentPlan(...)      // RevenueCat + Firestore birleşimi
@riverpod QuotaState quota(...)                               // kalan karar hakkı

// 4) Özellik durumları
@riverpod class DecisionEditor extends _$DecisionEditor {     // taslak düzenleme state machine
  // build(decisionId?) → Decision taslağı; autosave (debounce 800ms) → repository
}
@riverpod class AiAnalysisController extends _$AiAnalysisController {
  // state: idle → streaming(chunks) → done(analysis) | failure(retry)
}
@riverpod DecisionResult liveResult(ref, decisionId) {
  // DecisionEditor'ı izler → ScoringEngine.compute — what-if buradan beslenir
}
```

**Kurallar:**
- Widget'lar yalnız provider okur; iş mantığı Notifier/UseCase'te.
- Tüm async durumlar `AsyncValue<T>` → yükleme/hata UI'ı tek `AsyncValueWidget` sarmalayıcısıyla standart.
- `keepAlive` yalnız altyapı ve oturum; özellik provider'ları otomatik dispose (bellek).

### 6.2 GoRouter Haritası

```
/                     → SplashGate (auth + remote config bekler, < 2 sn bütçe)
/onboarding           → 2 sayfa, atlanabilir; tamamlanınca shared_prefs bayrağı
/home                 → geçmiş listesi + "Yeni Karar" (boş durum: şablon kartları)
/decision/new         → başlık + şablon seçimi
/decision/:id/edit    → seçenekler / artı-eksi / kriterler (sekmeli tek ekran)
/decision/:id/analyze → AI streaming ekranı
/decision/:id/result  → sonuç + what-if + paylaş/PDF
/paywall              → modal route (nereden açıldıysa oraya döner)
/settings, /settings/account, /settings/privacy
```

**Guard'lar:** `redirect` içinde — onboarding bayrağı, `/decision/new` öncesi kota kontrolü (doluysa `/paywall?source=quota`), premium özellik rotalarında plan kontrolü.

### 6.3 Tema & Tasarım Sistemi

- **Material 3**, `ColorScheme.fromSeed` (tohum: marka moru/laciverti — tasarım aşamasında kesinleşir), `ThemeMode.system` + kullanıcı tercihi.
- Token dosyası: spacing (4'lük ızgara), radius, elevation, duration sabitleri → `core/theme/tokens.dart`.
- Tipografi: dinamik tip ölçeklemesine saygı (`MediaQuery.textScaler` sınırlaması yalnız aşırı uçta).
- Erişilebilirlik: tüm interaktif öğeler ≥ 48dp dokunma hedefi, `Semantics` etiketleri, kontrast ≥ 4.5:1 (tema testinde otomatik kontrol).

---

## 7. Abonelik Mimarisi

```
İstemci ──(satın al)──► RevenueCat SDK ──► StoreKit2 / Play Billing
                             │
                             ▼ (webhook, imzalı)
                    revenuecatWebhook (Functions)
                             │
                             ▼
                  users/{uid}.plan = "premium"     ◄── Firestore stream ── istemci UI anında güncellenir
```

- **Tek doğruluk kaynağı:** `users/{uid}.plan` (Functions yazar). İstemci RevenueCat'ten gelen entitlement'ı **iyimser** gösterir, Firestore onayıyla kalıcılaşır → webhook gecikmesinde UX takılmaz.
- **Guard deseni:** `PremiumGate(child:…, fallback: PaywallCta(source:…))` widget'ı + use case seviyesinde ikinci kontrol (UI atlatılsa bile).
- Kota düşümü **yalnız sunucuda** (`analyzeDecision` transaction) → saat oynatma / reinstall hileleri işlemez.
- Restore purchases, aile paylaşımı ve iade (refund) senaryoları RevenueCat event'leriyle otomatik.

---

## 8. Hata Yönetimi ve Dayanıklılık

### 8.1 Failure Hiyerarşisi

```dart
sealed class Failure {
  const factory Failure.network() = NetworkFailure;        // bağlantı yok / timeout
  const factory Failure.quotaExceeded() = QuotaFailure;    // → paywall yönlendirme
  const factory Failure.aiUnavailable({bool retryable}) = AiFailure;
  const factory Failure.moderated(SafeRedirect redirect) = ModeratedFailure;
  const factory Failure.auth(AuthErrorCode code) = AuthFailure;
  const factory Failure.validation(String field, String message) = ValidationFailure;
  const factory Failure.unexpected(Object error, StackTrace st) = UnexpectedFailure;
}
```

- Her Failure → kullanıcı dostu, yerelleştirilmiş mesaj + (uygunsa) eylem butonu ("Tekrar dene", "Premium'a geç").
- `UnexpectedFailure` → Crashlytics non-fatal kaydı (PII temizlenmiş).
- AI streaming kesintisi: kısmi içerik korunur, "devam et" yeniden tam analiz ister (idempotent — aynı `decisionId+contentHash` için Functions önbelleğe döner, çift kota harcanmaz).

### 8.2 Çevrimdışı Davranış Matrisi

| Eylem | Çevrimdışı davranış |
|---|---|
| Karar taslağı oluştur/düzenle | ✓ tam çalışır (Firestore cache, senkron sonra) |
| Skor hesaplama / what-if | ✓ tam çalışır (yerel motor) |
| AI analizi | ✗ — açıklayıcı durum: "İnternet gelince hazır" + bağlantı dönünce otomatik tetikleme önerisi |
| Satın alma | ✗ — mağaza zaten engeller; net mesaj |
| PDF üretimi | ✓ (analiz zaten yerelde kayıtlıysa) |

---

## 9. Gözlemlenebilirlik

### 9.1 Analytics Olay Şeması (çekirdek huni)

```
onboarding_completed
decision_created        {template_id?, source: blank|template}
template_selected       {template_id}                ← önizleme sheet CTA anı (A1)
options_completed       {option_count}
criteria_completed      {criterion_count, ai_suggested_count}
criterion_suggestion_accepted {origin: template|keyword|generic}  ← A2 chip anı
analysis_requested      {tier}
analysis_completed      {latency_ms, tier}          ← AKTİVASYON OLAYI
analysis_feedback       {thumbs: up|down}
result_shared           {channel, format: card|pdf}
paywall_viewed          {source: quota|pdf|advanced_ai}
legal_link_opened       {document: privacy|terms|support}
trial_started / purchase_completed {plan: monthly|yearly}
account_deleted
```

- Kullanıcı özellikleri: `plan`, `decisions_total` (kovalanmış: 1-2/3-5/6+), `locale`.
- **Consent gate:** Analytics yalnız `consent.analytics == true` ise etkin (KVKK).
- BigQuery export açık → maliyet/karar ve huni analizi SQL ile.

### 9.2 Performans İzleme

- Firebase Performance: soğuk açılış trace'i (hedef < 2 sn), `analyzeDecision` custom trace (p95 < 15 sn), ekran render metrikleri.
- Cloud Functions: yapılandırılmış log (uid hash'li, PII yok), hata oranı alarmı (> %2 → e-posta).

---

## 10. Test Stratejisi

| Katman | Araç | Kapsam hedefi | Odak |
|---|---|---|---|
| Skor motoru | `test` (saf Dart) | **%100** | ağırlık normalizasyonu, sınır değerleri (tüm 1'ler / tüm 10'lar, tek kriter, eşitlik), güven hesabı |
| Domain use case | `test` + mocktail | ≥ %90 | kota guard'ları, validasyon, anonim→hesap senaryoları |
| Data | fake_cloud_firestore | ≥ %80 | DTO ↔ entity dönüşümleri, offline cache davranışı |
| Presentation | flutter_test + Riverpod override | ≥ %75 | DecisionEditor state machine, AsyncValue durum geçişleri, PremiumGate |
| Widget | golden_toolkit | kritik ekranlar | sonuç ekranı light/dark golden'ları, boş/hata durumları |
| Functions | vitest + firebase emulator | ≥ %85 | kota transaction yarışı, webhook imza doğrulama, moderasyon dalları, rules testleri |
| E2E | integration_test + emulator suite | 3 altın yol | (1) sıfırdan ilk karar → sonuç, (2) kota duvarı → satın alma (sandbox), (3) hesap silme |

**Genel kapsam kapısı: ≥ %80 (CI'da zorlanır).** Firestore rules `@firebase/rules-unit-testing` ile ayrıca test edilir (plan alanını istemciden yazma denemesi REDDEDİLMELİ vb.).

---

## 11. CI/CD ve Ortamlar

### 11.1 Flavor / Ortam Matrisi

| Flavor | Firebase projesi | LLM | Amaç |
|---|---|---|---|
| `dev` | karar-dev | küçük model, sahte moderasyon opsiyonu | günlük geliştirme + emulator suite |
| `staging` | karar-staging | prod ile aynı | TestFlight / Internal Testing, sandbox IAP |
| `prod` | karar-prod | prod | mağaza |

### 11.2 Pipeline (GitHub Actions)

```
PR →  format check → flutter analyze (fatal-infos) → custom lint (katman kuralı)
   →  unit+widget testler + coverage gate (%80)
   →  functions: lint + vitest + rules test (emulator)

main'e merge → staging build (Fastlane: TestFlight + Play Internal) + sürüm notu taslağı

release/x.y tag → prod build → mağaza gönderimi (manuel onay adımı)
                → dSYM/mapping upload (Crashlytics) → sürüm etiketli Analytics
```

- Sürümleme: semver + build number otomatik artar; Remote Config `min_supported_version` ile zorunlu güncelleme kapısı.
- İmzalama: iOS — App Store Connect API key ile Fastlane match; Android — Play App Signing.

---

## 12. Güvenlik Kontrol Listesi (üretim kapısı)

- [x] LLM anahtarları yalnız Secret Manager'da; istemci binary'sinde hiçbir gizli yok
- [x] App Check tüm callable fonksiyonlarda zorunlu
- [x] Firestore rules: kullanıcı yalnız kendi verisi; `plan/quota/aiAnalysis` istemciden yazılamaz
- [x] Rate limiting: AI çağrıları kullanıcı başına sınırlı; kota transaction ile atomik
- [x] Input validation: hem istemci (UX) hem rules hem Functions (zod) — üç katman
- [x] Prompt injection önlemi: kullanıcı metni veri olarak çerçevelenir, sistem talimatından ayrılır
- [x] TLS her yerde (Firebase varsayılan); sertifika pinning MVP'de yok (Firebase SDK ile uyumsuzluk riski > kazanç), v1.1'de değerlendirilir
- [x] PII: loglarda uid hash'lenir; Analytics'e karar içeriği ASLA gönderilmez (yalnız sayısal meta)
- [x] KVKK/GDPR: consent gate, `deleteAccount` kaskadı, `exportData` (JSON), aydınlatma metni linki
- [x] Webhook imza doğrulaması (RevenueCat authorization header)

---

## 13. Performans Bütçeleri ve Taktikler

| Bütçe | Hedef | Taktik |
|---|---|---|
| Soğuk açılış | < 2 sn | `deferred` Firebase init sıralaması (Auth önce, Analytics sonra); splash'te yalnız auth+remote config beklenir (500 ms timeout ile cache'e düşer) |
| Ekran geçişleri | 60 FPS | `const` widget disiplini, liste `itemExtent`, görsellerde `cached_network_image` + boyut sınırı |
| AI yanıtı | p95 < 15 sn | streaming ile algılanan gecikme < 2 sn (ilk chunk); tier bazlı model seçimi |
| What-if yeniden hesap | < 100 ms | senkron yerel motor (pratikte < 1 ms) |
| Uygulama boyutu | < 30 MB (Android AAB) | icon font yerine seçili SVG'ler, `--split-debug-info`, deferred loading değerlendirmesi |
| Firestore okuma | oturum başına < 50 | gömülü doküman modeli (karar = 1 okuma), liste sayfalama (20'şer) |

---

## 14. Açık Konular ve Sonraki Adımlar

| # | Konu | Karar zamanı |
|---|---|---|
| 1 | LLM sağlayıcı seçimi ve model eşlemesi (free/premium tier) — maliyet/kalite benchmark'ı Faz 0 prompt prototipiyle | Faz 0 |
| 2 | RevenueCat vs ham billing — ölçek maliyeti analizi (MVP kararı: RevenueCat) | Kesinleşti (AD-4) |
| 3 | Görsel yükleme (Storage) MVP'de mi? — öneri: v1'de var ama sıkıştırma istemcide, 1 MB sınır | Faz 1 |
| 4 | Paylaşım kartı render yaklaşımı: widget → `RepaintBoundary` screenshot (öneri) vs sunucu render | Faz 2 |
| 5 | `searchTokens` yaklaşımı ölçeklenmezse Algolia/Typesense değerlendirmesi | v1.1+ |

**Bir sonraki somut adım (Faz 0, Hafta 1):**
1. `flutter create` + flavor kurulumu + katman iskeleti + CI boru hattı
2. Firebase projeleri (dev/staging/prod) + `flutterfire configure`
3. Skor motoru TDD ile (ilk %100 kapsamlı modül)
4. 20 gerçek karar senaryosuyla prompt prototipi (Functions'tan önce lokal script ile)

---

*Bu mimari, PRD v1.0'daki tüm fonksiyonel ve fonksiyonel olmayan gereksinimleri karşılayacak şekilde tasarlanmıştır; her ADR yeni bilgiyle revize edilebilir.*
