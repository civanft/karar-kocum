# Veri Akışı Envanteri

**Kapsam:** Bu belge yalnız **bugün çalışan** davranışı anlatır. Planlanan
özellikler mevcutmuş gibi yazılmaz; kaynağı olmayan satır yoktur.

**Doğrulama tarihi:** 2026-09-09
**Doğrulanan revizyon:** `origin/main` @ `826046d`
**Çalışma zamanı AI sağlayıcısı:** OpenAI (Chat Completions).
`docs/GEMINI-MVP-MIMARI.md` bir **alternatif/gelecek** mimari belgesidir ve
çalışma zamanı kanıtı **sayılmaz** — üretim kodunda Gemini istemcisi yoktur.

---

## 0. Çalışma zamanı gerçekleri (kanıt)

| Gerçek | Değer | Kanıt |
|---|---|---|
| AI sağlayıcı | OpenAI, `chat.completions.parse` | `functions/src/ai/openai_gateway.ts:87` |
| Model | `gpt-4.1-mini` (env ile değişebilir) | `functions/src/config.ts:29` |
| API anahtarı konumu | Yalnız sunucu (Secret Manager) — cihazda **yok** | `functions/src/core/secrets.ts`, `functions/src/ai/analyze.ts:31` |
| `store` parametresi | Gönderilmiyor (varsayılan) | `openai_gateway.ts:87-97` |
| Son kullanıcı tanımlayıcısı (`user`) | OpenAI'ye **gönderilmiyor** | `openai_gateway.ts:87-97` |
| Ayrı moderation API çağrısı | **Yok** | `grep -rn "moderation" functions/src lib` → 0 |
| Kimlik doğrulama | Yalnız **anonim** Firebase Auth | `lib/core/config/firebase_bootstrap.dart:126` |
| Analytics SDK | **Yok** — `firebase_analytics` bağımlılığı bulunmuyor | `pubspec.yaml`; `lib/core/services/analytics/analytics_service.dart:1-115` |
| Reklam SDK | **Yok** — istemcide AdMob/RevenueCat bağımlılığı bulunmuyor | `pubspec.yaml` |
| Reklam kimliği izinleri | Manifest-merger'da **kaldırılıyor** (`tools:node="remove"`) | `android/app/src/main/AndroidManifest.xml:15-20` |
| Deploy edilen functions | `analyzeDecision`, `createRewardTicket`, `admobRewardCallback`, `deleteAccount` | `functions/src/index.ts:16-23` |
| Veri dışa aktarma | `exportData` **index'ten çıkarılmış** → canlıda yok | `functions/src/index.ts:5-9`, `functions/src/privacy/exportData.ts:11-17` |

---

## 1. Kategori bazlı akış

### 1.1 Karar başlığı, seçenekler, kriterler

| Alan | Değer |
|---|---|
| Kaynak | Kullanıcı girişi (düzenleme ekranı) |
| Amaç | Kararın kendisi; AI analizinin girdisi |
| Hedef | Firestore (birincil), izin verilmişse OpenAI API (analiz anında) |
| Yol / endpoint | `users/{uid}/decisions/{decisionId}` → `api.openai.com` Chat Completions |
| Kullanıcıyla ilişkili | **Evet** (Firebase UID yolunda) |
| Zorunlu/isteğe bağlı | Uygulama için zorunlu; **OpenAI'ye aktarım isteğe bağlı** (AI izni) |
| Saklama/silme | Firestore'da kullanıcı silene ya da hesabı silene kadar; hesap silmede kaskadla silinir |
| Kanıt | `functions/src/ai/prompt.ts:29-56`, `functions/src/ai/firestore_ports.ts:91` |
| Mağaza karşılığı | Apple: *Other User Content*; Play: *App activity / Other user-generated content* |

**OpenAI'ye giden tam alan listesi** (`prompt.ts:29-56`, şema `schema.ts:36-59`):
karar başlığı; her seçeneğin **id, başlık, açıklama, artılar, eksiler**;
her kriterin **adı ve 1-10 önem ağırlığı**.

> **Puan matrisi (skorlar) OpenAI'ye GÖNDERİLMEZ.** `buildUserMessage`
> yalnız kriter ağırlıklarını yazar; `decisionContentSchema` skor alanı
> içermez. Skorlar yalnız cihazda/Firestore'da yerel sıralama için kullanılır.

### 1.2 Puan matrisi (skorlar)

| Alan | Değer |
|---|---|
| Kaynak | Kullanıcı girişi | 
| Amaç | Yerel ağırlıklı sıralama (sonuç ekranı) |
| Hedef | **Yalnız Firestore** — dışarı çıkmaz |
| Yol | `users/{uid}/decisions/{decisionId}.scores` |
| Kullanıcıyla ilişkili | Evet |
| Zorunlu | Sonuç için gerekli |
| Saklama/silme | Karar/hesap silmeyle |
| Kanıt | `functions/src/ai/schema.ts:36-59` (skor alanı YOK), `lib/features/decision/domain/usecases/compute_result.dart` |

### 1.3 AI analiz çıktısı

| Alan | Değer |
|---|---|
| Kaynak | OpenAI yanıtı |
| Amaç | Kullanıcıya analiz göstermek; tekrar açılışta geri yükleme |
| Hedef | Firestore |
| Yol | `users/{uid}/decisions/{decisionId}/aiAnalyses/latest` |
| Kullanıcıyla ilişkili | Evet |
| Zorunlu | Hayır (yalnız analiz istenirse) |
| Saklama/silme | Karar/hesap silmeyle |
| Kanıt | `functions/src/ai/firestore_ports.ts:683-685`, `lib/features/ai_analysis/data/firestore_stored_analysis_repository.dart:24` |
| Mağaza karşılığı | Apple: *Other User Content*; Play: *Other user-generated content* |

### 1.4 Firebase UID (anonim)

| Alan | Değer |
|---|---|
| Kaynak | `signInAnonymously()` |
| Amaç | Veri sahipliği, güvenlik kuralları, kota/kredi muhasebesi |
| Hedef | Firebase Auth + Firestore yolları |
| Kullanıcıyla ilişkili | Evet (kimliğin kendisidir) |
| Zorunlu | Evet — uygulama fail-closed çalışır, oturumsuz veri yazılmaz |
| Saklama/silme | `deleteAccount` hem Firestore ağacını hem Auth kullanıcısını siler |
| Kanıt | `lib/core/config/firebase_bootstrap.dart:126`, `functions/src/privacy/firestore_account_deletion_ports.ts:45-73` |
| Mağaza karşılığı | Apple: *User ID*; Play: *App activity → App interactions* değil, *Personal info → User IDs* |

> **E-posta / ad / profil fotoğrafı toplanmaz.** `AppUser` bu alanları
> taşıyabilir ama üretimde yalnız anonim oturum açılır; Google/Apple/e-posta
> ile giriş yolu **yoktur** (`grep GoogleSignIn` → 0).

### 1.5 Kota, kredi ve muhasebe

| Alan | Değer |
|---|---|
| Kaynak | Sunucu (analiz akışı) |
| Amaç | Ücretsiz analiz hakkı, maliyet freni, kötüye kullanım sınırı |
| Hedef | Firestore |
| Yol | `users/{uid}` (plan, krediler), `users/{uid}/analysisRequests/*` (journal), `users/{uid}/analysisReservations/state`, `rateLimits/{uid}` |
| Kullanıcıyla ilişkili | Evet |
| Zorunlu | Evet (özellik kullanılırsa) |
| Saklama/silme | Hesap silmede kaskad + top-level yollar |
| Kanıt | `functions/src/ai/firestore_ports.ts:107,168,171,533` |

### 1.6 Bekleyen analiz anahtarı (cihazda)

| Alan | Değer |
|---|---|
| Kaynak | İstemci (idempotency anahtarı) |
| Amaç | Süreç kesintisinden sonra **ücretli çağrıyı tekrarlamadan** kurtarma |
| Hedef | Cihaz — `SharedPreferences`, anahtar öneki `ai.pendingRequest.` |
| İçerik | **Yalnız requestId** — karar içeriği kopyalanmaz |
| Kullanıcıyla ilişkili | Cihaz yerel; sunucuya gönderilmez |
| Saklama/silme | Analiz tamamlanınca temizlenir; uygulama silinince gider |
| Kanıt | `lib/features/ai_analysis/data/pending_analysis_request_store.dart:30-71` |

### 1.7 Çökme/teşhis (Crashlytics)

| Alan | Değer |
|---|---|
| Kaynak | Uygulama hataları |
| Amaç | Kararlılık teşhisi |
| Hedef | Firebase Crashlytics (Google) |
| Gönderilen | **Sanitize edilmiş**: `StateError('Application error (<runtimeType>)')` + stack. Exception mesajı, `reason`, karar içeriği, UID, belge yolu **gönderilmez** |
| Kullanıcıyla ilişkili | Crashlytics kendi cihaz/kurulum tanımlayıcısını üretir; uygulama UID **eklemez** |
| Zorunlu | Evet (v1'de ayrı kapatma anahtarı yoktur) |
| Saklama/silme | Firebase Crashlytics saklama politikası |
| Kanıt | `lib/core/services/crash_reporter.dart:19-47` |
| Mağaza karşılığı | Apple: *Crash Data*, *Performance Data* (App Functionality); Play: *App info and performance → Crash logs* |

### 1.8 App Check sinyalleri

| Alan | Değer |
|---|---|
| Kaynak | Cihaz bütünlük sağlayıcısı |
| Amaç | Sahte istemciden gelen ücretli çağrıları engellemek |
| Hedef | iOS: App Attest (DeviceCheck yedekli); Android: Play Integrity |
| İçerik | Platform tarafından üretilen bütünlük token'ı — uygulama içeriği taşımaz |
| Zorunlu | Evet — `analyzeDecision` ve `deleteAccount` `enforceAppCheck: true` |
| Kanıt | `lib/core/config/firebase_bootstrap.dart:107-115,143-145`, `functions/src/ai/analyze.ts:29-30` |
| Mağaza karşılığı | Apple: *Device ID* (Fraud Prevention, App Functionality); Play: *Device or other IDs* |

### 1.9 Yerel bildirimler

| Alan | Değer |
|---|---|
| Kaynak | Uygulama (7 gün sonrası karar kontrolü) |
| Amaç | Kullanıcıya kendi kararını hatırlatmak |
| Hedef | **Cihaz** — `flutter_local_notifications`. Push/FCM **yok**, sunucuya veri gitmez |
| İzinler | `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` (yeniden başlatmada planı korumak için) |
| Kanıt | `android/app/src/main/AndroidManifest.xml:3-9`, `pubspec.yaml` (`flutter_local_notifications`) |

### 1.10 Teknik veriler (uygulama kodunda görünmeyen)

Uygulama bu verileri **kendisi toplamaz**, ancak istek sunuculara ulaştığı
için sağlayıcılar tarafından işlenir:

| Veri | İşleyen | Neden |
|---|---|---|
| IP adresi, kaba coğrafi konum, kullanıcı aracısı | Google (Firebase Auth / Firestore / Functions / Crashlytics / Hosting), OpenAI (analiz isteği sunucudan gider → **Cloud Functions'ın IP'si**, cihazınki değil) | Ağ isteğinin doğası |
| Cihaz/işletim sistemi bilgisi | Firebase Crashlytics | Çökme teşhisi |
| Cihaz bütünlük sinyalleri | Apple App Attest / Google Play Integrity | Kötüye kullanım engelleme |

> OpenAI isteği **cihazdan değil, Cloud Functions'tan** çıkar; bu yüzden
> OpenAI son kullanıcının IP adresini uygulamamız aracılığıyla **almaz**.
> Kanıt: `functions/src/ai/analyze.ts:37-47` (çağrı sunucu tarafında).

---

## 2. OpenAI'nin veri kullanımı (resmî kaynak)

Kaynak: <https://developers.openai.com/api/docs/guides/your-data> (2026-09-09).

- API'ye gönderilen veri, **açıkça opt-in yapılmadıkça** OpenAI modellerini
  eğitmek veya geliştirmek için **kullanılmaz**.
- Varsayılan olarak tüm API kullanımı için **kötüye kullanım izleme (abuse
  monitoring) kayıtları** üretilir; bu kayıtlar **istem ve yanıt gibi müşteri
  içeriğini kapsayabilir** ve **30 güne kadar** saklanır (yasa daha uzun
  saklama gerektirmedikçe).
- **Zero Data Retention (ZDR)** ve **Modified Abuse Monitoring (MAM)** bu
  kayıtlardan müşteri içeriğini çıkarır; ikisi de **OpenAI'nin ön onayını**
  gerektirir.

> **Bu projede ZDR/MAM etkin olduğu KANITLANAMAMIŞTIR.** Organizasyon
> ayarına erişimimiz yok; bu yüzden politika ve mağaza beyanları
> **varsayılan davranışa** göre yazılmıştır. Etkinleştirildiği canlı
> organizasyon ayarından kanıtlanana kadar aksi iddia edilmeyecektir.
>
> Aynı gerekçeyle **veri yerleşimi (data residency)** de yapılandırılmış
> sayılmaz: isteğin hangi bölgede işlendiği garanti edilemez, bu yüzden
> "yurt dışında işlenebilir" ifadesi korunur.

---

## 3. Silme ve dışa aktarma

| Yol | Durum | Kanıt |
|---|---|---|
| Hesap + veri silme | **Çalışıyor** — uygulama içinden `deleteAccount`; `users/{uid}` ağacı recursive silinir, top-level UID kayıtları temizlenir, Auth kullanıcısı silinir | `functions/src/privacy/firestore_account_deletion_ports.ts:45-73`, `functions/src/index.ts:23` |
| AI izni kaydının silinmesi | Hesap silme kaskadına **dahil** (`users/{uid}` altında) | `firestore_account_deletion_ports.ts:28-33` (`privacy` alt koleksiyonu) |
| Veri dışa aktarma | **Canlıda yok** — `exportData` deploy yüzeyinden çıkarılmış | `functions/src/index.ts:5-9` |

> Dışa aktarma canlı olmadığı için izin kaydı da dışa aktarmaya **dahil
> değildir**; gizlilik politikası bu durumu olduğu gibi anlatır ve
> kullanıcıyı destek e-postasına yönlendirir.

---

## 4. Envanterin test edilen kısımları

| İddia | Testi |
|---|---|
| Skorlar OpenAI'ye gönderilmez | `functions/test/ai/prompt.test.ts` |
| İzin yokken sağlayıcı çağrısı 0 | `functions/test/ai/consent_enforcement.test.ts` |
| Analytics çalışma zamanında kapalı, SDK yok | `test/release/analytics_dormancy_test.dart` |
| Crashlytics'e içerik/UID gitmez | `test/features/decision/error_privacy_test.dart` |
| Politika ↔ kod ↔ mağaza beyanı tutarlılığı | `test/release/privacy_consistency_test.dart` |
