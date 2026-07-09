# PR #6B — Sadeleştirilmiş AI Mimarisi (MVP)

| | |
|---|---|
| **Tarih** | 9 Temmuz 2026 |
| **Statü** | Tasarım — implementasyon PR #6C |
| **Bu doküman** | [AI-ANALIZ-TASARIMI.md](AI-ANALIZ-TASARIMI.md)'nin MVP kapsamında YERİNE GEÇER (tam tasarım ölçek büyüyünce referans olarak kalır) |
| **Girdi** | [MALIYET-AUDIT.md](MALIYET-AUDIT.md) kararları (tek model, BQ yok, $0,35/gün kesici) |

## 1. Yeni akış ve mimari diyagram

```
┌──────────────────────── FLUTTER ────────────────────────┐
│  Sonuç Ekranı                                           │
│  [✦ AI Analizi] butonu ──────────────┐                  │
│       ▲                              │ callable çağrısı │
│       │ K-2 canlı akışı              │ {decisionId}     │
│       │ (watchById zaten var)        ▼                  │
└───────┼──────────────────────────────┼──────────────────┘
        │                              │ App Check + Auth
        │              ┌───────────────▼───────────────┐
        │              │  analyzeDecision (tek dosya)  │
        │              │  1. auth + bağlam             │
        │              │  2. kararı Firestore'dan OKU  │
        │              │  3. zod doğrula               │
        │              │  4. rate limit + aylık kota   │
        │              │     + günlük maliyet tavanı   │
        │              │  5. moderasyon (ücretsiz uç)  │
        │              │  6. OpenAI gpt-4o-mini        │
        │              │     structured output         │
        │              │     (1 basit retry)           │
        │              │  7. TEK transaction:          │
        │              │     analiz + status + kota    │
        │              └───────┬───────────────────────┘
        │                      │ yazım
┌───────┴──────────────────────▼──────────────────────────┐
│ FIRESTORE                                               │
│  users/{uid}/decisions/{id}                             │
│    └─ aiAnalyses/latest   ← SABİT belge kimliği (yeni)  │
│  users/{uid}.quota        ← aylık 5 (değişmedi)         │
│  rateLimits/{uid}         ← değişmedi                   │
│  ops/dailySpend           ← günlük tavan $0,35          │
└─────────────────────────────────────────────────────────┘
```

Yanıt iki kanaldan aynı anda döner: callable yanıtı (anında render) + `aiAnalyses/latest` yazımı (K-2 akışı, kalıcılık). Ekran hangisi önce gelirse onu gösterir — ekstra mekanizma gerekmez, K-2 altyapısı zaten var.

## 2. Kaldırılanlar ve yerine konan basit karşılıklar

| Kaldırılan | Yerine (MVP) | Kabul edilen ödünleşim |
|---|---|---|
| **BigQuery + aiJobs koleksiyonu** | Maliyet görünürlüğü: OpenAI usage panosu + `ops/dailySpend` tek belgesi | Tier/prompt kırılımlı analitik yok — 1000 kullanıcı altında gereksizdi |
| **Cache sistemi (inputHash)** | `aiAnalyses/latest` SABİT belge: yeniden analiz üzerine yazar (belge çoğalmaz); istemci butonu istek sürerken pasif | Aynı içeriğe ikinci istek kota yakar → UI koruması: son analiz varken buton "Yeniden analiz et"e döner ve onay ister |
| **Prompt versioning (registry + Remote Config)** | Tek dosya `prompt.ts` (sabit sistem talimatı + user_data derleyici); analiz belgesine düz `promptVersion:'mvp-1'` string'i yazılır (ileri dönük iz) | A/B ve deploy'suz rollback yok — prompt değişikliği = deploy |
| **Karmaşık pipeline (AnalyzeService + 5 port + DI grafiği)** | Tek dosyada sıralı handler (~150 satır); test edilebilirlik için yalnız 2 enjeksiyon kalır: OpenAI istemcisi + saat | Port-bazlı birim test matrisi küçülür; kritik yollar (kota adaleti, moderasyon) yine test edilir |
| **Şema onarım denemesi** | Structured output strict modda tek deneme; bozulursa `ai-unavailable` | Nadir onarım vakaları hata olur (ölçüm: <%1'di) |
| **Retry matrisi (429×2 + 5xx×1 + jitter)** | Tek kural: 429/5xx/timeout → **1** yeniden deneme (1 sn) | Uç durum başarı oranı hafif düşer |
| **Metrik modülü + 7 log-based metric + 9 alarm** | Düz log (uidHash'li) + **2 alarm**: Functions hata oranı (Console hazır grafiği) + günlük maliyet tavanı zaten kod içinde kesiyor | Ayrıntılı p95/cache panoları yok |
| **`suggestCriteria` + `scoreOptions` fonksiyonları** | Statik şablon kriterleri (templates zaten planlıydı); AI puanlama premium'la birlikte döner | — |
| **Tier sistemi (basic/advanced)** | Tek model: `gpt-4o-mini`, max_tokens 900 | Premium analizi Sprint 5'te geri gelir |

**Korunanlar (değişmeden):** Firebase Auth (anonim+Google) · Firestore veri modeli ve rules (aiAnalyses `write: if false` dahil — sabit belge kimliği rules'ı etkilemez) · App Check + `enforceAppCheck` · rate limiter (1 dosya, bütçe koruması) · aylık kota + "yalnız başarıda düşer" adaleti · moderasyon (ücretsiz, güvenlik) · günlük maliyet kesici (**yeni varsayılan $0,35/gün** — 6A/R1) · hata taksonomisi (`errors.ts`) ve logger (küçülür ama kalır).

## 3. Dosya planı

### functions/ — SİLİNECEK (7 dosya + 2 test)
```
src/ai/cache.ts                     (inputHash)
src/ai/analyze_service.ts           (orkestratör + portlar)
src/ai/firestore_ports.ts           (adapter)
src/ai/prompts/registry.ts          (sürüm sistemi)
src/ai/config.ts                    (tier eşlemesi → sabitlere iner)
src/ai/suggestCriteria.ts
src/ai/scoreOptions.ts
src/core/metrics.ts                 (emitMetric/finishRequest)
test/analyze_service.test.ts        → yerini analyze.test.ts alır
test/cache_cost.test.ts             → maliyet kısmı cost.test.ts'e iner
```

### functions/ — DEĞİŞECEK (5)
```
src/ai/analyze.ts        ← TEK handler: akıştaki 7 adım sıralı (~150 satır);
                            OpenAI istemcisi + clock enjekte edilebilir
src/ai/prompt.ts         ← prompts/analyze_v1.ts buraya sadeleşir (tek sabit)
src/ai/openai_gateway.ts ← retry tek kurala iner; moderasyon + structured
                            output kalır; onarım denemesi silinir
src/ai/cost_control.ts   ← fiyat tablosu tek satıra (mini), varsayılan
                            limit 0.35; breaker mantığı aynen
src/index.ts             ← export listesi küçülür (analyze + privacy + webhook)
```

### functions/ — TESTLER (hedef ~25 test; mevcut 46'dan)
```
test/analyze.test.ts     ← kota adaleti (3), moderasyon (2), doğrulama (3),
                            mutlu yol + latest üzerine yazma (2), kesici (2)
test/openai_gateway.test.ts ← retry tek kural (3) + structured output (2)
test/cost.test.ts        ← birim maliyet + tavan (3)
test/rate_limiter.test.ts / errors_logger.test.ts / exports.test.ts ← kalır
```

### Flutter — YENİ (PR #6C'de yazılacak, 4 dosya)
```
lib/features/ai_analysis/domain/entities/ai_analysis.dart      ← okuma modeli
lib/features/ai_analysis/data/ai_analysis_client.dart          ← callable çağrısı
                                                                  + Failure eşleme
lib/features/ai_analysis/presentation/providers/analysis_providers.dart
                                                                ← istek durumu +
                                                                  aiAnalyses/latest akışı
lib/features/ai_analysis/presentation/widgets/analysis_card.dart
                                                                ← sonuç ekranındaki
                                                                  pasif kartın gerçeği
```

### Dokümanlar
```
MONITORING-PANOSU.md  ← §3-5 sadeleşir: 2 alarm, BQ bölümü "1000+ kullanıcıda" notuna
TEKNIK-MIMARI.md      ← §5 fonksiyon envanteri güncellenir (2 fonksiyon MVP-dışı)
```

## 4. Silme sırası (PR #6C uygulama planı)

1. `cost_control` varsayılanını 0,35'e çek (bağımsız, riskiz)
2. `suggestCriteria`/`scoreOptions` export'larını kaldır → testleri güncelle
3. `analyze.ts`'i yeni tek-dosya akışa yaz, eski servis/port/cache dosyalarını sil
4. Prompt'u tek dosyaya indir, registry'yi sil
5. `metrics.ts`'i sil, logger çağrılarına indir
6. pubspec temizliği (6A: `dio`, `firebase_storage`) — aynı PR'a binebilir
7. Flutter AI istemcisi + kart (yukarıdaki 4 dosya)
8. Gates + emulator + canlı smoke'a "analiz" adımı

## 5. Bilinçli riskler (kabul edilen)

1. **Çift istek = çift kota/maliyet** (cache yok) — UI koruması + rate limit + $0,35 tavan üçlüsü zararı sınırlar; kota adaleti kuralı (hatada yanmaz) korunur.
2. **Analiz geçmişi yok** (`latest` üzerine yazar) — karşılaştırma UI'ı (v1.2) gelirse alt koleksiyon zaten hazır, yalnız kimlik üretimi değişir.
3. **Prompt rollback = deploy** — MVP hızında kabul; kalite regresyon seti (20 senaryo) deploy öncesi elle koşulur.
