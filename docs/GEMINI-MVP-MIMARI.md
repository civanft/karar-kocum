# PR #6C-1 — Gemini MVP Mimarisi

| | |
|---|---|
| **Tarih** | 9 Temmuz 2026 |
| **Statü** | Tasarım — implementasyon PR #6C-2 |
| **Değiştirir** | AI-MVP-MIMARI.md'nin OpenAI bölümlerini; akış/veri modeli/UI AYNEN kalır |
| **Etki yarıçapı** | Yalnız gateway katmanı — `AiGateway` arayüzü sayesinde rate limit, kota, hata taksonomisi, rules, Flutter UI (6D-1) DOKUNULMADAN kalır |

## 1. Gemini Model Seçimi

| Aday | Fiyat (giriş/çıkış, 1M token) | Analiz başına* | Değerlendirme |
|---|---|---|---|
| **gemini-2.0-flash ✅ SEÇİM** | $0,10 / $0,40 | **~$0,00039** | Kalite/maliyet dengesi; Türkçe çıktısı güçlü; structured output + systemInstruction tam destekli |
| gemini-2.0-flash-lite | $0,075 / $0,30 | ~$0,00029 | %25 daha ucuz ama uzun-form Türkçe analiz kalitesi riski; B planı (env ile geçilebilir) |
| gemini-1.5-pro sınıfı | ~$1,25 / $5 | ~$0,005 | MVP için gereksiz — premium tier döndüğünde aday |

\* ~1.500 giriş + ~600 çıkış token varsayımıyla. **gpt-4o-mini'ye göre ~%40 daha ucuz.**

**Erişim yolu kararı: Gemini API (Google AI) + API anahtarı Secret Manager'da (`GEMINI_API_KEY`) — ÜCRETLİ katman.**
- **Ücretsiz katman bilinçli REDDEDİLDİ:** Google AI free tier'da istek verileri model iyileştirmede kullanılabilir — kullanıcıların kişisel karar içerikleri için KVKK/gizlilik açısından kabul edilemez. Ücretli katmanda veri eğitimde kullanılmaz. (Maliyet zaten önemsiz: §7.)
- **Vertex AI alternatifi** (API anahtarsız, IAM/service-account, bölgesel) not edildi: operasyonel olarak daha temiz ama SDK/kurulum yükü MVP'ye fazla; ölçekte geçiş yolu olarak dokümante edildi. Mevcut OpenAI gateway'i anahtar-tabanlı olduğundan Gemini API en küçük kod farkı.
- **Firebase AI Logic (istemciden doğrudan Gemini) REDDEDİLDİ:** Cloud Function proxy'siz kota/moderasyon/maliyet tavanı istemciye taşınır = atlatılabilir. Sunucu-taraflı kota adaleti mimarinin temel taşı.

## 2. Cloud Function Akışı (analyzeDecision — değişen yalnız [6]-[7])

```
[1] App Check + Auth (değişmedi)
[2] decisionId zod doğrulama (değişmedi)
[3] Kararı Firestore'dan oku (değişmedi)
[4] İçerik doğrulama — Y-3 limitleri (değişmedi)
[5] Rate limit + aylık kota ön kontrolü + günlük tavan (değişmedi)
[6] GEMİNİ ÇAĞRISI — TEK istekte üretim + güvenlik:            ← DEĞİŞTİ
      generateContent({
        systemInstruction: SABİT_PROMPT,        ← OpenAI system mesajının karşılığı
        contents: [user_data bloğu],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: <analiz şeması>,      ← structured output, native
          maxOutputTokens: 800, temperature: 0.4,
        },
        safetySettings: [BLOCK_MEDIUM_AND_ABOVE × 4 kategori],
      })
      → OpenAI'daki AYRI moderasyon adımı ([7]) KALKTI:
        Gemini safetySettings üretimle aynı çağrıda filtreler
        (promptFeedback.blockReason / finishReason=SAFETY)
        → bir ağ turu daha az, gecikme ~%30 düşer
[7] Yanıt işleme: finishReason kontrolü + JSON parse + zod     ← DEĞİŞTİ
[8] Tek transaction: aiAnalyses/latest + status + kota (değişmedi)
[9] Maliyet kaydı + log + {analysisId:'latest'} (değişmedi)
```

Moderasyonun üretim çağrısına katlanmasının ödünleşimi: engellenen istekte de giriş token'ı ücretlendirilir (~$0,00015) — ihmal edilebilir; kota yine yanmaz (kural korunur).

## 3. Firestore Veri Modeli

**Değişiklik YOK.** `users`, `decisions`, `aiAnalyses/latest`, `rateLimits`, `ops/dailySpend` aynen. Rules'a dokunulmaz (canlıda 13/13 + smoke 6/6 doğrulanmış kurallar geçerli kalır). Tek fark belge içindeki `model` alanının değeri.

## 4. Analysis Document Şeması (`aiAnalyses/latest`)

| Alan | Tip | Not |
|---|---|---|
| `summary` | string ≤2.000 | |
| `strengths` / `weaknesses` / `risks` | string[] ≤5×300 | |
| `recommendation` | string ≤500 | "veriler gösteriyor" çerçevesi |
| `confidence` | `low\|medium\|high` | |
| `model` | `'gemini-2.0-flash'` | |
| `promptVersion` | `'mvp-1'` | prompt metni AYNEN taşınır (sağlayıcı-bağımsız yazılmıştı) |
| `generatedAt` | serverTimestamp | |

Gemini `responseSchema` notu: OpenAPI-alt kümesi kullanır — mevcut JSON şemamız birebir çevrilir (`enum` ve `required` destekli); OpenAI'ın `strict:true`/`additionalProperties:false` alanları Gemini'de gereksizdir, şema zaten kapalı yorumlanır. Sunucuda zod ikinci doğrulama aynen kalır.

## 5. Hata Senaryoları (Gemini → mevcut AppError taksonomisi)

| Gemini sinyali | Anlamı | Eşlenen kod | Retry | Kota |
|---|---|---|---|---|
| HTTP 429 `RESOURCE_EXHAUSTED` | upstream RPM/TPM | `ai-unavailable` (retryable) | 1× (1 sn) | yanmaz |
| HTTP 500/503 / timeout | servis sorunu | `ai-unavailable` (retryable) | 1× | yanmaz |
| HTTP 400 `INVALID_ARGUMENT` | istek hatası (şema/parametre) | `internal` + log | yok | yanmaz |
| `promptFeedback.blockReason` | GİRDİ güvenlik bloğu | `moderated`; kategori `DANGEROUS_CONTENT`+kendine-zarar deseni → güvenli yönlendirme metni (182) | yok | **yanmaz** |
| `finishReason: SAFETY` | ÇIKTI güvenlik bloğu | `moderated` (nötr metin) | yok | yanmaz |
| `finishReason: RECITATION` | telif/alıntı bloğu | 1× yeniden dene → `ai-unavailable` | 1× | yanmaz |
| `finishReason: MAX_TOKENS` | çıktı kesildi → JSON bozuk | `internal` + `schemaFailure` logu | yok | yanmaz |
| Boş `candidates` / JSON parse hatası | beklenmedik yanıt | `internal` | yok | yanmaz |

İstemci (6D-1 UI) değişmez: `moderated` → hata kartındaki mesaj alanı, `resource-exhausted` → kota kartı, `ai-unavailable` → retryable hata kartı — eşleme zaten durum makinesinde.

## 6. Rate Limit Stratejisi

- **Kullanıcı başına (değişmedi):** 3/dk + 10/saat (Firestore transaction sayacı) + aylık 5 kota (yalnız başarıda düşer).
- **Upstream:** Gemini ücretli tier-1 ~2.000 RPM / 4M TPM — bizim teorik tavan (maxInstances 10 × concurrency 20 = 200 eşzamanlı) bunun çok altında; 429 beklenmez, gelirse taksonomi karşılar. (Ücretsiz katmanın 15 RPM sınırı, ücretli katman kararının ikinci gerekçesi.)
- **Global fren (değişmedi):** maxInstances 10 + günlük maliyet kesici $0,35.

## 7. Günlük/Aylık Maliyet Tahmini

Analiz başına: 1.500×$0,10/M + 600×$0,40/M = **$0,00039** (moderasyon ayrı çağrı olmadığı için ek maliyet yok).

| Kullanıcı | Analiz/gün (~2,5/kullanıcı-ay) | Günlük | **Aylık Gemini** | (OpenAI idi) |
|---|---|---|---|---|
| 100 | ~8 | $0,003 | **~$0,10** | $0,15 |
| 500 | ~42 | $0,016 | **~$0,49** | $0,75 |
| 1000 | ~83 | $0,033 | **~$0,98** | $1,50 |

Günlük tavan $0,35 = 1000-kullanıcı gerçek gününün ~10 katı marj (değiştirmeye gerek yok). Firestore/Functions $0 (ücretsiz kota) — **toplam aylık ≤ $10 hedefi 10-100× marjla korunuyor.** Fiyat tablosu (`cost_control`) tek satır güncellenir; bilinmeyen-model muhafazakâr tarife kuralı kalır.

## 8. Dosya etkisi (6C-2 için önizleme — kod bu PR'da yok)

Değişen: `openai_gateway.ts → gemini_gateway.ts` (SDK: `@google/generative-ai`; retry sınıflandırması Gemini hata/finishReason'larına), `core/secrets.ts` (`GEMINI_API_KEY`), `cost_control.ts` fiyat satırı, `schema.ts` responseSchema çevirisi, gateway testleri. **Değişmeyen:** analyze akış iskeleti, rate limiter, kota, errors/logger/context, rules, tüm Flutter (6D-1 UI dahil). Kullanıcı tarafı kurulum: `functions:secrets:set GEMINI_API_KEY` (OpenAI anahtarı gereksizleşir).
