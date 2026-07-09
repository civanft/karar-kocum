# PR #6A — Maliyet Auditi

| | |
|---|---|
| **Tarih** | 9 Temmuz 2026 · denetlenen sürüm: `a4b59d6` (main) |
| **Hedef** | Aylık toplam ≤ **10 USD** |
| **Sonuç** | ✅ 1000 kullanıcıda tahmini **~2 USD/ay** — hedefin ~5× altında. Ancak 2 yapılandırma düzeltilmezse tek olayda bütçe aşılabilir (§5 R1-R2) |

## 1. Kullanım modeli (varsayımlar)

Tüm hesaplar şu davranış modeline dayanır (PRD hedefleri + kod davranışı):

| Varsayım | Değer | Dayanak |
|---|---|---|
| Aktif kullanıcı başına karar/ay | 2 | PRD etkileşim hedefi |
| Karar başına düzenleme yazımı | ~18 (oluşturma 1 + seçenek/artı-eksi ayrık patch'ler ~12 + slider flush ~4 + favori/başlık ~1) | editor kodu: her `addProCon` ayrı `applyPatch`; slider'lar debounce'lu (Y-2 sayesinde ~40 yerine ~4) |
| Oturum/ay | 8; oturum başına liste okuması ~10 belge | watchAll snapshot'ı |
| AI analiz/kullanıcı-ay | 2,5 istek; %20 önbellek isabeti → **2,0 LLM çağrısı** | kota 5, gerçek kullanım ~yarısı; inputHash cache |
| suggestCriteria/kullanıcı-ay | 2 | karar başına 1 |
| Model | %100 free tier → gpt-4o-mini (premium YOK — MVP) | config.ts |
| Analiz token'ları | ~1.500 giriş / ~700 çıkış | PR #4 test doğrulaması: **$0,000645/analiz** |

**Kullanıcı başına aylık Firestore:** ~120 okuma, ~50 yazma, ~5 silme.
(Yazma kalemi: düzenleme 36 + analiz commit'i 3×2,5 + aiJobs 2,5 + rateLimits 2,5 + kullanıcı belgesi ~2.)

## 2. Senaryo tablosu (aylık, USD)

| Kalem | Birim fiyat* | 100 kullanıcı | 500 | 1000 |
|---|---|---|---|---|
| Firestore okuma | $0,06/100K (ücretsiz: 50K/gün) | 12K → **$0** | 60K → **$0** | 120K → **$0** |
| Firestore yazma | $0,18/100K (ücretsiz: 20K/gün) | 5K → **$0** | 25K → **$0** | 50K → **$0** |
| Firestore depolama | $0,18/GB (ücretsiz: 1 GB) | ~4 MB → $0 | ~20 MB → $0 | ~40 MB → **$0** |
| Cloud Functions çağrı | ücretsiz: 2M/ay | 450 → $0 | 2,3K → $0 | 4,5K → **$0** |
| Functions işlem (GB-sn) | ücretsiz: 400K GB-sn | ~2K → $0 | ~9K → $0 | ~18K → **$0** |
| **OpenAI — analiz** | $0,000645/adet | 200 → $0,13 | 1.000 → $0,65 | 2.000 → **$1,29** |
| **OpenAI — suggestCriteria** | ~$0,00018/adet | 200 → $0,04 | 1.000 → $0,18 | 2.000 → **$0,36** |
| OpenAI — moderasyon | ücretsiz | $0 | $0 | $0 |
| Auth (anonim+Google) / App Check / Analytics / Crashlytics | ücretsiz | $0 | $0 | $0 |
| Secret Manager | 6 sürüm ücretsiz | $0 | $0 | $0 |
| Artifact Registry + Cloud Build (functions deploy kalıntısı) | — | ~$0,10 | ~$0,10 | ~$0,10 |
| Cloud Logging | ücretsiz: 50 GiB/ay | $0 | $0 | $0 |
| **TOPLAM** | | **≈ $0,3** | **≈ $1,0** | **≈ $1,9** |

\* Fiyatlar bölgeye göre ±%20 oynar (eur3 hafif pahalı); Firestore günlük ücretsiz kotası Blaze'de de geçerlidir ve 1000 kullanıcı hacmimizin ~10 katını karşılar.

**Sonuç: üç senaryoda da bütçenin çok altındayız; belirleyici tek değişken maliyet OpenAI'dır ve o da hedefin %20'sinde.**

## 3. En pahalı bileşenler (1000 kullanıcı sırası)

1. **OpenAI analiz** — $1,29 (%68) → tek anlamlı değişken maliyet
2. **OpenAI suggestCriteria** — $0,36 (%19)
3. **Artifact Registry/Build kalıntısı** — ~$0,10 (sabit)
4. Firestore/Functions/geri kalan her şey — $0 (ücretsiz kota içinde)

## 4. Gereksiz servis/bağımlılık tespiti

| Tespit | Kanıt | Aksiyon |
|---|---|---|
| `firebase_storage` paketi | kodda 0 referans; görsel yükleme hiç uygulanmadı | pubspec'ten çıkar; Storage'ı Console'da hiç etkinleştirme (bucket oluşmasın) |
| `dio` paketi | kodda 0 referans (network katmanı hiç gerekmedi — Firestore SDK + callable yetiyor) | pubspec'ten çıkar |
| `printing`/`pdf`/`purchases_flutter` | Sprint 5-6 işi; şimdilik ölü ağırlık (maliyet değil, derleme süresi) | kalabilir; not düşüldü |
| Firestore→BigQuery export uzantısı | MONITORING-PANOSU.md'de öneriliyordu; her aiJobs yazımında fonksiyon tetikler + Eventarc altyapısı kurar | **MVP'de kurma** — bu hacimde `aiJobs`'u Console/sorgu ile incelemek yeterli |
| 2 collectionGroup indeksi (`aiAnalyses`, `subscriptions` — ops panoları için) | indeks yazım maliyeti (bugün $0, prensip olarak gereksiz) | subscriptions olanını Sprint 5'e kadar kaldır |
| Mimarideki "prod'da `minInstances: 1`" önerisi | kodda set edilmemiş (✅ doğru durum) | **öyle kalsın** — 512 MB sıcak instance tek başına ~$5-12/ay = bütçenin yarısı-tamamı; soğuk başlatma (~2-4 sn) bu bütçede kabul edilen ödünleşim. TEKNIK-MIMARI §1.1 notu güncellenecek |

## 5. Bütçe riskleri ve düşürme önerileri

| # | Öneri | Etki |
|---|---|---|
| **R1 — KRİTİK** | **Devre kesici varsayılanı $50/gün** (`AI_DAILY_SPEND_LIMIT_USD`, config.ts) — $10/AY hedefiyle çelişiyor: tek kötü gün bütçenin 5 katı. → **$0,35/gün'e indir** (≈$10/ay tavan) | felaket senaryosu tavanı 150× düşer |
| **R2 — KRİTİK** | **OpenAI proje hard cap'ini $10/ay yap** (platform.openai.com → proje limitleri) — kod hatası/istismar durumunda faturanın fiziksel tavanı | mutlak güvence |
| R3 | suggestCriteria'yı istemcide önbelleğe al / şablon önerileriyle birleştir (şablonlar zaten statik kriter önerir) | −$0,36 @1000; LLM'siz alternatif mevcut |
| R4 | Analiz `max_tokens` 900→700 denemesi (kalite regresyon setiyle) | −%20 çıkış maliyeti |
| R5 | `consumeAppCheckToken` (limited-use) her istekte token üretimi istiyor — para maliyeti yok ama gecikme; hacim büyüyünce standart token'a dönüş değerlendirilebilir | UX; maliyet $0 |
| R6 | OpenAI prompt caching zaten devrede (statik sistem prompt önde) — girişin ~%60'ı %50 indirimli; tabloya İHTİYATLA katılmadı | fiili maliyet tablodakinden ~%25 düşük olabilir |

## 6. MVP'den çıkarılması önerilenler ($10 disiplini için)

1. **`advanced` tier (gpt-4o)** — analiz başına $0,012 (mini'nin 18×). Premium zaten satılmıyor; `scoreOptions` fonksiyonu da (gpt-4o kullanıyor) MVP'de devre dışı kalmalı → **MVP'de tek model: gpt-4o-mini**
2. **Görsel yükleme + Storage** — hiç açılmasın (kod da yok)
3. **BigQuery export + Looker panoları** — Console yeterli; 1000 kullanıcıyı geçince kur
4. **suggestCriteria (tartışmalı)** — $0,36'lık maliyeti küçük ama şablon kriterleri %80'ini bedavaya karşılıyor; ilk sürümde kapalı başlatılıp talebe göre açılabilir

## 7. İzleme bağlantısı

`ai_cost_daily` metriği + A4 alarmı (MONITORING-PANOSU.md) eşiği R1 ile uyumlu güncellenmelidir: ön-uyarı **$0,28/gün** (yeni limitin %80'i).
