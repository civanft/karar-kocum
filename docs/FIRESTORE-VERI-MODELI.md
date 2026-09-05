# Firestore Veri Modeli — Sprint 2 Öncesi Tasarım

| | |
|---|---|
| **Sürüm** | v1.0 — 8 Temmuz 2026 |
| **İlişkili** | [TEKNIK-MIMARI.md](TEKNIK-MIMARI.md) §4, [TEKNIK-AUDIT-SPRINT1.md](TEKNIK-AUDIT-SPRINT1.md) K-2/Y-3/Y-4/Y-5 |
| **ADR güncellemesi** | AD-9: `aiAnalysis` karar belgesinden ayrı alt koleksiyona taşındı (aşağıda gerekçe) |

## 0. Yerleşim özeti ve iki temel tasarım kararı

```
users/{uid}                                    ← koleksiyon
users/{uid}/decisions/{decisionId}             ← alt koleksiyon (options+criteria+scores GÖMÜLÜ)
users/{uid}/decisions/{id}/aiAnalyses/{aid}    ← alt koleksiyon (YALNIZ Functions yazar)
users/{uid}/subscriptions/{eventId}            ← alt koleksiyon (YALNIZ Functions yazar)
templates/{templateId}                         ← global, salt okunur
aiJobs/{jobId}                                 ← ops-iç, istemciye tamamen kapalı
```

**Karar 1 — `decision_options` ve `criteria` ayrı koleksiyon DEĞİL, gömülü dizi (AD-8 korundu).**
Seçenek ≤ 10, kriter ≤ 15 (ürün limiti). Ayrı koleksiyon olsaydı: bir kararı açmak 1 yerine 1+N+M okuma (26× maliyet), atomik güncelleme için transaction zorunluluğu, offline senkronda parça tutarsızlığı riski. Gömülü modelde karar = tek belge: 1 okuma, atomik yazım, senkron basit. **Ayrıştırma tetikleyicisi** (ileride limit büyürse): seçenek limiti > 30 VEYA belge boyutu p95 > 256 KB olursa `decisions/{id}/options/{oid}` alt koleksiyonuna göç — şema bu dokümanda hazır (§3.4).

**Karar 2 — `ai_analyses` AYRI alt koleksiyona çıkarıldı (AD-9, yeni).**
Gömülü `aiAnalysis` alanı audit K-2'nin sunucu ayağının kaynağıydı: istemcinin tam-belge autosave'i Functions'ın yazdığı analizi ezebilirdi ve rules'ta kırılgan diff-kontrolü gerektiriyordu. Ayrı alt koleksiyonda: **yazma yolu fiziksel olarak ayrık** (istemci `decisions`'a, Functions `aiAnalyses`'e yazar — çakışma imkânsız), rules tek satır (`allow write: if false`), analiz geçmişi bedavaya gelir (yeniden analiz = yeni belge), büyük AI çıktısı sıcak karar belgesini şişirmez.

---

## 1. `users/{uid}`

### 1.1 Şema
| Alan | Tip | Yazar | Not |
|---|---|---|---|
| `displayName` | string? | istemci | ≤ 80 kr |
| `email` | string? | istemci (Auth'tan) | |
| `photoUrl` | string? | istemci | |
| `locale` | string | istemci | `tr` \| `en` |
| `plan` | string | **yalnız Functions** | `free` \| `premium` — hızlı gating snapshot'ı; kaynak-of-truth §6 |
| `planExpiresAt` | Timestamp? | **yalnız Functions** | |
| `quota` | map | **yalnız Functions** | `{month: "2026-07", used: 3}` — lazy reset |
| `consent` | map | istemci | `{analytics: bool, updatedAt: Timestamp}` |
| `createdAt` / `lastActiveAt` | Timestamp | istemci | `serverTimestamp()` ile |
| `decisionCount` | int | istemci (yalnız atomik) | Karar cap'i (50) sayacı — bkz. 1.3 |
| `decisionCountMutationId` | string? | istemci (yalnız atomik) | Son sayaç mutasyonunun `decisionId`'si. `decisionCount` değişimini AYNI batch'teki gerçek karar create/delete'ine bağlar (rules doğrular); bağımsız değiştirilemez. Eski belgelerde YOK olabilir (opsiyonel, migration gerekmez). Ürün verisi değildir, kullanıcıya gösterilmez. |

### 1.2 İndeks
Yok — belgeye her zaman doğrudan `uid` ile erişilir. Tek-alan otomatik indeksler yeterli.

### 1.3 Güvenlik kuralları (özet — tam hali firestore.rules'ta)
Okuma: yalnız sahibi. Update: sahibi, **ancak** `plan`/`planExpiresAt`/`quota` alanlarına dokunamaz (diff kontrolü). Create: `plan == 'free'` zorunlu. Delete: kapalı (yalnız `deleteAccount` fonksiyonu).

**Sayaç bütünlüğü (security hotfix):** `decisionCount` ve `decisionCountMutationId` tek başına yazılamaz. `+1` yalnız aynı batch'te `users/{uid}/decisions/{decisionId}` **oluşuyorsa**, `-1` yalnız **siliniyorsa** ve marker o `decisionId`'yi taşıyorsa geçerlidir (`exists`/`existsAfter`). Karar create/delete kuralları da user sayacının projected (`getAfter`) durumunu doğrular — bağ çift yönlüdür. Böylece sayacı bağımsız azaltıp 50 karar sınırını aşmak imkânsızdır.

### 1.4 Boyut tahmini
Tipik **~0,6 KB**, tavan ~2 KB. 100K kullanıcı ≈ 60-200 MB — ihmal edilebilir.

### 1.5 Ölçeklenebilirlik
Rastgele uid'ler doğal shard'lama sağlar; hotspot yok. Yazım sıklığı düşük (`lastActiveAt` oturum başı 1 — her ekranda değil!). Risk: `quota.used` artışı Functions transaction'ında — kullanıcı başına saniyede 1 yazım limiti AI çağrı hızından (dk'da 3) çok uzak. 🟢

---

## 2. `users/{uid}/decisions/{decisionId}`

### 2.1 Şema
| Alan | Tip | Yazar | Not |
|---|---|---|---|
| `ownerUid` | string | istemci | **rules: `== uid` zorunlu (Y-5 kapanışı)** |
| `title` | string | istemci | 3-100 kr |
| `templateId` | string? | istemci | |
| `status` | string | istemci: `draft`/`archived` · Functions: `analyzed` | |
| `options` | array<map> | istemci | 2-10 eleman — şema §3 |
| `criteria` | array<map> | istemci | 1-15 eleman — şema §4 |
| `scores` | map<map> | istemci | `{optionId: {criterionId: {value: 1-10, source}}}` |
| `result` | map? | istemci | yerel motor çıktısı snapshot'ı |
| `latestAnalysisId` | string? | **yalnız Functions** | §5'e işaretçi |
| `isFavorite` | bool | istemci | |
| `searchTokens` | array<string> | istemci | başlıktan, ≤ 20 token, küçük harf |
| `createdAt` / `updatedAt` | Timestamp | istemci | `updatedAt` = `serverTimestamp()` (Y-4) |

### 2.2 İndeksler (`firestore.indexes.json`)
Bileşik: `(status ASC, updatedAt DESC)` · `(isFavorite ASC, updatedAt DESC)` · `(searchTokens CONTAINS, updatedAt DESC)` — üçü de geçmiş ekranı filtreleri için.
**Alan muafiyetleri (kritik maliyet optimizasyonu):** `scores` (150 hücreli dinamik map — her anahtar otomatik indekslenirse indeks yazım maliyeti belge başına yüzlerce girdi), `options` içindeki `pros`/`cons`/`description` → indeksleme kapalı. Sorgulanmayan alanı indekslemek para ve yazım gecikmesi israfıdır.

### 2.3 Güvenlik kuralları
Sahibi okur/yazar/siler + doğrulamalar: `ownerUid == uid`, başlık 3-100, options 2-10, criteria ≤ 15, `latestAnalysisId` ve `status: 'analyzed'` istemciden yazılamaz (diff kontrolü). Y-3 limitleri (seçenek adı ≤ 60, açıklama ≤ 280, kriter adı ≤ 40, artı/eksi ≤ 20 madde × ≤ 140 kr) rules'ta **da** zorlanır — üç katman kuralı.

### 2.4 Boyut tahmini
| Senaryo | Hesap | Boyut |
|---|---|---|
| Tipik (3 seçenek, 4 kriter, 5'er artı/eksi) | 3×(60+150+10×140÷2) + 4×60 + 12 hücre×30B + meta | **~3-4 KB** |
| Ağır (10 seçenek, 15 kriter, 20'şer madde) | 10×(60+280+40×140) + 15×60 + 150×30B + meta | **~65 KB** |
| Mutlak tavan (limitlerle) | | < 80 KB — 1 MB limitinin %8'i 🟢 |

Kullanıcı başına yıllık ~25 karar × 4 KB ≈ 100 KB/yıl. 100K kullanıcı ≈ 10 GB/yıl — depolama maliyeti önemsiz (~2,5 $/ay).

### 2.5 Ölçeklenebilirlik
- Kullanıcı-altı koleksiyon → sorgu daima tek kullanıcıya scoped; global daralma yok.
- Yazım deseni: en sık işlem autosave — **Y-2 debounce şart** (800 ms + `onChangeEnd`); belge başına 1 yazım/sn Firestore limitine tek kullanıcı zaten yaklaşamaz.
- Geçmiş listesi sayfalanır (20/sayfa, `updatedAt` cursor) — oturum başına okuma < 50 bütçesi korunur.
- `searchTokens` prefix-arama yaklaşımı ~10K karar/kullanıcıya kadar yeterli; ötesi zaten Algolia tetikleyicisi (mimari açık konu #5). 🟢

---

## 3. `decision_options` — gömülü dizi olarak (ayrı koleksiyon değil)

### 3.1 Eleman şeması (decisions.options[])
| Alan | Tip | Not |
|---|---|---|
| `id` | string | istemci üretimi, 20 kr |
| `title` | string | 1-60 kr |
| `description` | string? | ≤ 280 kr |
| `imageUrl` | string? | Storage yolu; yalnız kendi bucket'ı (rules'ta pattern) |
| `pros` / `cons` | array<string> | ≤ 20 madde × ≤ 140 kr |

### 3.2 İndeks · 3.3 Kurallar · Boyut
Gömülü olduğu için ayrı indeks/kural/belge yok — §2'nin içinde doğrulanır (rules'ta `options.size()`, eleman alanları döngüsüz üst-seviye kontrollerle sınırlanır; derin eleman doğrulaması Functions'ta zod ile). Boyut §2.4'e dahil.

### 3.4 Ayrıştırma planı (tetiklenirse)
`decisions/{id}/options/{optionId}` alt koleksiyonu; karar belgesinde `optionOrder: string[]` kalır. Tetik: seçenek limiti > 30 veya p95 belge > 256 KB. Göç: Functions batch script, istemci sürümü feature-flag ile çift-okuma. **Bugün için: gereksiz karmaşıklık.** 🟢

---

## 4. `criteria` — gömülü dizi olarak (ayrı koleksiyon değil)

### 4.1 Eleman şeması (decisions.criteria[])
| Alan | Tip | Not |
|---|---|---|
| `id` | string | |
| `name` | string | 1-40 kr |
| `weight` | int | 1-10 |
| `source` | string | `user` \| `aiSuggested` |

Gerekçe, indeks/kural/boyut durumu §3 ile aynı mantık: ≤ 15 eleman, skorlarla atomik güncellenmeli (kriter silme = matris sütunu silme — tek belgede atomik, iki koleksiyonda transaction gerektirirdi). **Şablon kriterleri** ayrı yerde yaşar: `templates/{id}.suggestedCriteria` (global, salt okunur). 🟢

---

## 5. `users/{uid}/decisions/{id}/aiAnalyses/{analysisId}` — AYRI koleksiyon (AD-9)

### 5.1 Şema
| Alan | Tip | Not |
|---|---|---|
| `tier` | string | `basic` \| `advanced` |
| `summary` | string | ≤ 4.000 kr |
| `risks` | array<string> | ≤ 10 |
| `perOption` | map | `{optionId: {strengths[], weaknesses[]}}` |
| `suggestedCriteria` | array<map> | `{name, defaultWeight}` ≤ 5 |
| `confidence` | string | `low`/`medium`/`high` |
| `confidenceReason` | string | ≤ 500 kr |
| `model` | string | maliyet/kalite izlemesi için model kimliği |
| `inputHash` | string | idempotency: aynı karar durumu → önbellek, çift kota harcanmaz |
| `generatedAt` | Timestamp | `serverTimestamp()` |

**Yazar: YALNIZ Functions (admin SDK).** İstemci salt okur. Yeniden analiz = yeni belge; `decisions.latestAnalysisId` işaretçisi güncellenir → geçmiş bedava, karşılaştırma UI'ı (v1.2+) hazır altyapı bulur.

### 5.2 İndeks
Tek-alan otomatik `generatedAt` yeterli (son analizi işaretçi zaten veriyor; liste sorgusu `orderBy generatedAt desc limit 5`). Ops için collectionGroup `aiAnalyses (tier, generatedAt DESC)` — maliyet panosu sorguları.

### 5.3 Güvenlik kuralları
```
allow read: if request.auth.uid == uid;
allow write: if false;   // tek satır — K-2'nin kırılgan diff kuralının yerini alır
```

### 5.4 Boyut tahmini
Tipik **~4-6 KB**, tavan (advanced, 10 seçenek) ~25 KB. Karar başına ortalama 1,3 analiz → kullanıcı-yıl ~150 KB. 🟢

### 5.5 Ölçeklenebilirlik
Yazım yalnız Functions'tan, kullanıcı başına dk'da ≤ 3 (rate limit) — hiçbir limite yaklaşmaz. Analiz geçmişi sınırsız büyürse: 90 gün+ eski analizlere TTL politikası (Firestore TTL alanı `expiresAt`) — v1.1'de değerlendir; maliyet o zamana dek önemsiz. 🟢

---

## 6. `users/{uid}/subscriptions/{eventId}` — abonelik kayıtları

### 6.1 Şema
| Alan | Tip | Not |
|---|---|---|
| `type` | string | `INITIAL_PURCHASE` / `RENEWAL` / `CANCELLATION` / `EXPIRATION` / `BILLING_ISSUE` |
| `productId` | string | `monthly` / `yearly` mağaza ürün kimliği |
| `store` | string | `app_store` \| `play_store` |
| `eventTimestamp` | Timestamp | RevenueCat olay zamanı |
| `expiresAt` | Timestamp? | entitlement bitişi |
| `environment` | string | `SANDBOX` \| `PRODUCTION` |
| `raw` | map | webhook payload'ının denetim kopyası (PII ayıklanmış) |

**Yazar: YALNIZ Functions** (`revenuecatWebhook`, imza doğrulamalı). Belge kimliği = RevenueCat event id → **doğal idempotency**: webhook tekrar teslimatı aynı belgeyi ezer, çift işlem imkânsız. `users/{uid}.plan` bu koleksiyondaki son duruma göre Functions'ça türetilir — plan snapshot'ı hızlı gating, bu koleksiyon denetim izi + uyuşmazlık çözümü (iade itirazı, destek talebi).

### 6.2 İndeks
Tek-alan `eventTimestamp` yeterli (kullanıcının olay geçmişi). Ops: collectionGroup `(environment, eventTimestamp DESC)` — sandbox/prod ayrık raporlama.

### 6.3 Güvenlik kuralları
`allow read: if request.auth.uid == uid; allow write: if false;`

### 6.4 Boyut · 6.5 Ölçek
Olay ~0,5-1 KB; premium kullanıcı yılda ~13 olay (12 yenileme + 1) ≈ 10 KB/yıl. Yazım hızı webhook-güdümlü, düşük. Tek risk: webhook burst (toplu yenileme günü) — Functions concurrency bunu emer, Firestore'a kullanıcı başına tek belge yazımı. 🟢

---

## 7. Kesişen konular

- **Zaman damgaları (Y-4):** tüm `createdAt/updatedAt` alanları `FieldValue.serverTimestamp()`; istemci modeli `TimestampConverter` ile ISO değil Timestamp okur-yazar. Sıralama garantisi cihaz saatinden bağımsız.
- **K-2 sunucu ayağı bu modelle kapanır:** istemci ve Functions'ın yazdığı belgeler fiziksel ayrık (decisions ↔ aiAnalyses/subscriptions); tek kesişim `latestAnalysisId`+`status` — ikisi de rules diff'iyle istemciye kapalı.
- **Toplam kullanıcı maliyeti tahmini (aylık, aktif kullanıcı):** ~2 karar × (1 yazım debounce'lu oturum ~15 yazım + 30 okuma) → ≪ 0,001 $/kullanıcı-ay. Firestore bu üründe maliyet kalemi değil; LLM maliyeti belirleyici (mimari R2).
- **Göç stratejisi:** mevcut in-memory JSON şeması bu modelle alan-uyumlu (bkz. JSON round-trip testi); tek kırıcı fark Timestamp converter — Sprint 2 PR'ında model güncellemesiyle birlikte gelir.

---

## 8. Hesap ve veri silme (PR-R1)

Mağaza zorunluluğu (App Store 5.1.1(v) / Play Data Deletion): uygulama içinden
hesabın ve tüm verilerinin kalıcı silinmesi. Tek giriş noktası
`deleteAccount` callable'ıdır (Gen2, `enforceAppCheck` + `consumeAppCheckToken`).

**Kimlik:** UID YALNIZ `request.auth.uid`'den okunur. İstemci boş payload
gönderir; başka bir kullanıcının yolu istemciden etkilenemez.

**Silme kapsamı ve SIRA (sıra güvenlik gereğidir) — İş Paketi 3:**

| # | Hedef | Yöntem | Not |
|---|-------|--------|-----|
| 1 | `accountDeletionBlocks/{uid}` | create-if-absent | **BARİYER.** İlk adım; bundan sonra yeni kullanıcı verisi oluşturulamaz |
| 2 | Açık AI rezervasyonları | bounded drain + reconcile | Devam eden analiz veriyi diriltemesin diye; kapanmadan silmeye geçilmez |
| 3 | `users/{uid}` ağacı | `recursiveDelete(userRef)` | `decisions` → `aiAnalyses`, `analysisRequests`, `analysisReservations`, `rewardTickets`, `subscriptions` KAPSAM İÇİ |
| 4 | `rateLimits/{uid}` | tek belge silme | `analyzeDecision` limiti; `users` ağacının DIŞINDA |
| 5 | `rateLimits/{uid}:reward` | tek belge silme | `createRewardTicket` limiti; AYRI belge |
| 6 | Temizlik doğrulaması | okuma | Auth'a geçmeden önce veri gerçekten gitti mi |
| 7 | Firebase Auth kullanıcısı | `getAuth().deleteUser(uid)` | EN SON |
| 8 | Bariyer | **silinmez** | TTL politikası kaldırır (aşağıya bakınız) |

**Neden Auth en son:** Auth önce silinseydi kullanıcının token'ı anında
geçersizleşir, Firestore adımı yarıda kalırsa veri yetim kalırdı. Firestore
adımlarından biri hata verirse Auth'a HİÇ geçilmez.

### 8.1 Silme bariyeri — `accountDeletionBlocks/{uid}`

**Çözdüğü sorun:** kaskad `users/{uid}` ağacını sildikten sonra Auth
kullanıcısı silinene kadar eski Firebase ID token GEÇERLİ kalır (token ömrü
bir saate kadar çıkabilir). O pencerede istemci yazması, devam eden bir AI
analizi ya da bir ödül callback'i silinmiş veriyi **diriltir**.

**Durum makinesi (İş Paketi 3B):**

| Durum | Alanlar | TTL |
|---|---|---|
| `deleting` | `schemaVersion`, `state`, `startedAt` | **YOK** — `expiresAt` alanı bulunmaz |
| `deleted` | + `completedAt`, `expiresAt` | `completedAt + ≥48 saat` |

**Neden `deleting` durumunda TTL alanı yok:** Firestore TTL yalnız timestamp
taşıyan `expiresAt` alanını işler. Bariyer oluşturulurken `expiresAt`
yazılsaydı, silme 48 saatten uzun süre tamamlanamadığında TTL bariyeri
kaldırır ve **Auth hesabı hâlâ dururken** eski/yeni oturum tekrar veri
yazabilirdi. Tamamlanmamış bir silme bariyeri bu yüzden **süresiz** durur:
kalıcı bariyer, Auth mevcutken bariyerin erken silinmesinden daha güvenlidir.

TTL saati **yalnız** terminal geçişte (`deleted`) başlar; o noktada veri
temizliği doğrulanmış ve Auth kullanıcısı gerçekten silinmiştir.

**Geçişler:** `deleting → deleted` tek yönlüdür; `deleted → deleting`
YASAKTIR. Terminal geçiş idempotenttir. 3. Paket biçimindeki
`deleting + expiresAt` kayıtları bir sonraki retry'da güvenli migrasyonla
`expiresAt`'ten arındırılır; `startedAt` korunur.

**Terminal geçiş başarısız olursa:** bariyer silinmez, sahte başarı/expiry
yazılmaz. Veri ve Auth gerçekten silindiği için kullanıcıya hata dönmez;
PII içermeyen sabit bir teşhis logu üretilir ve bariyer süresiz kalır. Bu
nadir durum **manuel reconciliation** gerektirir (rollback runbook).

UID yalnız **belge kimliğidir**; gövdede e-posta, isim, karar içeriği veya
başka hiçbir kişisel veri bulunmaz. Belge istemciye tamamen kapalıdır.

**48 saat neden:** eski ID token'lar bir saate kadar yaşayabilir, TTL silmesi
anlık değildir ve bariyer, eski kimlik belirteci doğal olarak geçersizleşmeden
kaldırılmamalıdır.

**İdempotency:** bariyer create-if-absent'tir. Tekrar çağrıda `startedAt` ve
`expiresAt` **ileri taşınmaz** — her retry süreyi uzatsaydı bariyer hiç sona
ermeyebilirdi.

**İki katmanlı zorlama:**
- **Firestore Rules** — `accountActive(uid)` yardımcısı sahiplik VE bariyerin
  yokluğunu birlikte doğrular; `users/{uid}` ağacındaki her istemci kuralı
  bunu kullanır (`isOwner` tek başına kullanılmaz).
- **Admin SDK** — Rules'u bypass ettiği için sunucu yazma yolları bariyeri
  KENDİ transaction'ları içinde okur: AI rezervasyonu, sağlayıcı çağrısı
  öncesi son kontrol, ödül bileti oluşturma ve SSV callback'i. Transaction
  öncesi tek bir `get()` yeterli olmazdı — bariyer ile yazım aynı anda
  commit ederse okuma çakışma kümesinde olduğu için transaction yeniden
  çalışır ve reddeder.

**TTL:** `accountDeletionBlocks.expiresAt` alanında Firestore TTL politikası
etkindir. TTL silmesi **kesin bir süre garantisi vermez**; Google
dokümantasyonu silmenin süre sonundan sonra gerçekleşeceğini söyler ama
gecikme olabilir. Bariyerin erken kaldırılmaması güvenlik açısından
belirleyicidir, geç kaldırılması zararsızdır.

### 8.2 Devam eden AI isteğiyle yarış

Bariyer yeni rezervasyonu ve sağlayıcı çağrısını kapatır, ama bariyerden
**önce** açılmış bir rezervasyon hâlâ çalışıyor olabilir. Bu yüzden silme,
recursive delete'e geçmeden önce açık rezervasyonları **drain** eder:

- `reserved` (sağlayıcı hiç başlamadı) → maliyetsiz kapanır;
- `provider_call_started` (sonuç bilinmiyor) → 2C'nin ihtiyatlı politikası;
- `provider_succeeded` (sonuç var) → 2D'nin atomik finalizasyonu.

Bir rezervasyonu açan çağrının artık çalışmadığına, `analyzeDecision`'ın
60 saniyelik fonksiyon timeout'unu aşan bir yaşa ulaşmasıyla karar verilir.
Daha genç kayıtlar için sınırlı süre beklenir; bu sürede kapanmazlarsa
**Auth silinmez ve veri silinmez** — kullanıcıya tekrar denenebilir hata
döner ve bariyer durduğu için yeni veri de oluşamaz.

**Sayfalama (3B):** drain her turda en fazla `pageSize × maxPages` (50×2)
belge okur. Kapatılan kayıt `reservationExpiresAt` alanını kaybettiği için
sorgudan düşer; bu yüzden her tur baştan sorgulanır ve ilerleme garanti
edilir (değer tabanlı imleç kullanılmaz — aynı zaman damgasını paylaşan
kayıtların tamamı atlanabilirdi). Sayfa bütçesi dolarsa drain `exhausted`
bildirir: **görülmemiş kayıt olabileceği için asla "kalan yok" denmez.**
"Kalan yok" iddiası yalnız son sayfanın görüldüğü turda kabul edilir.

**Top-level doğrulama:** Auth'a geçmeden önce `users/{uid}` ağacı **ve**
`rateLimits/{uid}` + `rateLimits/{uid}:reward` belgelerinin gerçekten
silindiği doğrulanır.

**Ödül rate-limit'i (3B):** `rateLimits/{uid}:reward` de UID'ye bağlı bir
kullanıcı kaydıdır. `createRewardTicket`'ın rate-limit transaction'ı
bariyeri **aynı transaction içinde** okur; UID anahtardan ayrıştırılmaz,
typed parametre olarak geçirilir.

**Korunanlar:**
- `ops/*` global sayaçları (günlük harcama/token/analiz limitleri) — kullanıcıya
  ait değildir, silinmez; silinseydi global kota tavanı sıfırlanırdı.
- Başka hiçbir kullanıcının yolu oluşturulmaz.

**İdempotency:** olmayan belge/kullanıcı no-op'tur; `auth/user-not-found`
başarı sayılır. İstemci timeout'undan sonra tekrar denemek güvenlidir.

**Rules DEĞİŞTİ (İş Paketi 3):** kaskad Admin SDK ile çalışır ve Rules'u
bypass eder — bu yüzden Rules tek başına yeterli değildi ve iki katmanlı
zorlama uygulandı (§8.1). `firestore.indexes.json` değişmedi: bariyer
doğrudan belge kimliğiyle okunur ve drain sorgusu tek alanlı sıralama
kullanır, ikisi de bileşik indeks gerektirmez.

**Cihaz tarafı:** `journey.followUpOptedIn` (SharedPreferences) silinir ve
planlı tüm yerel takip bildirimleri iptal edilir. Ardından oturum kapatılır ve
YENİ, BOŞ bir anonim oturum açılır — kullanıcı silinmiş hesapta mahsur kalmaz.

**Deploy sırası (zorunlu):**

1. `firebase deploy --only functions:deleteAccount --project <proje>`
2. Fonksiyon canlıya çıktıktan SONRA istemci sürümü yayınlanır.

Ters sırada yayınlanırsa istemcideki silme düğmesi `not-found` alır ve mağaza
incelemesi çalışmayan bir silme akışı görür.
