# Monitoring Panosu ve Alarm Eşikleri

| | |
|---|---|
| **Sürüm** | v1.0 — 8 Temmuz 2026 |
| **İlişkili** | AI-ANALIZ-TASARIMI.md §9, TEKNIK-MIMARI.md §9 |
| **Araçlar** | Firebase Analytics + Crashlytics · Cloud Monitoring (log-based metrics) · BigQuery + Looker Studio |

## 1. Veri kaynakları ve akış

```
Flutter istemci ──► Firebase Analytics (olay şeması §2) ──► BigQuery export
                └─► Crashlytics (crash-free users)
Cloud Functions ──► Yapılandırılmış log (event:"metric") ──► Log-based metrics ──► Cloud Monitoring
                └─► aiJobs koleksiyonu ──► Firestore→BigQuery export ──► maliyet panoları
```

## 2. İstemci olay şeması (uygulandı — analytics_service.dart)

| Olay | Parametreler | Ne zaman |
|---|---|---|
| `decision_created` | `source: blank\|template` | karar oluşturma başarılı |
| `options_completed` | `option_count` | 2. seçenek eklendiğinde (eşik geçişi, tek atış) |
| `criteria_completed` | `criterion_count, ai_suggested_count` | ilk kriterde |
| `scoring_completed` | — | puan matrisi tamamlandığında |
| `result_viewed` | — | **v1 aktivasyon olayı** — sonuç ekranı açılışı |
| `analysis_requested` / `analysis_completed` | `tier` / `tier, latency_ms, cached` | PR #6'da ekrana bağlanır |
| `analysis_feedback` | `thumbs: up\|down` | PR #6 |
| `result_shared` | `channel, format` | Sprint 6 |
| `paywall_viewed` | `source` | Sprint 5 |

Kullanıcı özellikleri: `plan` (`free/premium`), `decisions_total` (kova: `1-2 / 3-5 / 6+`).
**KVKK:** tüm olaylar consent kapısının arkasında (`analyticsConsentProvider`, varsayılan KAPALI — Sprint 6 onboarding'i sorar). Parametrelerde içerik/PII taşınmaz.

## 3. Sunucu log-based metric tanımları (Cloud Monitoring)

Fonksiyon loglarımız `event:"metric"` satırları üretir (PR #3-4'te uygulandı). Console → Logging → Log-based metrics'te şu tanımlar oluşturulur:

| Metric adı | Filtre | Tip |
|---|---|---|
| `ai/latency_total` | `jsonPayload.metric="ai_latency_total_ms"` → value alanı | Distribution |
| `ai/cost_daily` | `jsonPayload.metric="ai_cost_usd"` → value | Counter (sum) |
| `ai/cache_hit` | `jsonPayload.metric="ai_cache_hit"` | Counter |
| `ai/errors` | `jsonPayload.metric="ai_error"` (etiket: `code`) | Counter |
| `ai/schema_failures` | `jsonPayload.metric="ai_schema_failure"` | Counter |
| `ai/rate_rejections` | `jsonPayload.metric="rate_limit_rejection"` | Counter |
| `fn/request_duration` | `jsonPayload.metric="request_duration_ms"` (etiket: `fn, outcome`) | Distribution |

## 4. Pano yerleşimi

### Pano A — Ürün Sağlığı (Looker Studio, kaynak: Analytics BigQuery)
1. **Aktivasyon hunisi** (günlük): `decision_created → options_completed → criteria_completed → scoring_completed → result_viewed` — dönüşüm % + hedef çizgisi (ilk karar tamamlama ≥ %45)
2. Kuzey yıldızı: haftalık tamamlanan karar sayısı (`result_viewed`, ileride `analysis_completed`)
3. D1/D7/D30 retention kohortları
4. `decisions_total` kova dağılımı + plan kırılımı

### Pano B — AI Operasyon (Cloud Monitoring)
1. `ai/latency_total` p50/p95 (hedef çizgi 15 sn) + `fn/request_duration` fn kırılımı
2. `ai/errors` oranı, `code` etiketiyle yığılmış (moderated/quota hariç tutulabilir)
3. `ai/cache_hit` oranı = cache_hit / (cache_hit + ok-jobs)
4. `ai/rate_rejections` + `ai/schema_failures` (prompt kalite sinyali)

### Pano C — Maliyet (Looker Studio, kaynak: aiJobs→BigQuery)
```sql
-- günlük maliyet, tier/model/promptVersion kırılımı
SELECT DATE(createdAt) d, tier, model, promptVersion,
       SUM(costUsd) cost, COUNT(*) jobs,
       COUNTIF(status='cache_hit')/COUNT(*) cache_rate,
       AVG(durationMs) avg_ms
FROM `karar_prod.firestore_export.aiJobs*`
GROUP BY d, tier, model, promptVersion ORDER BY d DESC
```
Kartlar: maliyet/analiz (hedef: basic < $0,001), maliyet/aktif kullanıcı-ay, devre kesici doluluk % (ops/dailySpend ÷ limit).

### Pano D — Kararlılık (Firebase Console)
Crash-free users (hedef ≥ %99,5), `decision_patch_failed` non-fatal sayısı (Y-1 yolu — artışı senkron sorunu işaret eder), sürüm bazlı kırılım.

## 5. Alarm eşikleri

| # | Alarm | Koşul | Pencere | Kanal | Runbook |
|---|---|---|---|---|---|
| A1 | AI hata oranı | `ai/errors`(moderated+quota hariç) / istek > **%2** | 15 dk | e-posta (+Slack S3) | ai-kesinti |
| A2 | AI gecikme | `ai/latency_total` p95 > **20 sn** | 15 dk | e-posta | ai-kesinti |
| A3 | Şema başarısızlığı | `ai/schema_failures` / istek > **%1** | 30 dk | e-posta | prompt-regresyon |
| A4 | Günlük maliyet ön-uyarı | `ai/cost_daily` > **limitin %80'i** (40$) | anlık | e-posta | devre-kesici |
| A5 | Devre kesici tetiklendi | `ai_error{code=ai-unavailable, circuitBreaker}` > 0 | anlık | e-posta+SMS | devre-kesici |
| A6 | Upstream 429 | 429 sınıfı retry oranı > **%5** | 30 dk | e-posta | openai-limit |
| A7 | Crash-free düşüşü | crash-free users < **%99** (sürüm bazlı) | Crashlytics velocity | e-posta | rollback |
| A8 | Rate reject patlaması | `ai/rate_rejections` > **50/saat** | 1 saat | e-posta | abuse-inceleme |
| A9 | patch hatası artışı | `decision_patch_failed` non-fatal > **20/saat** | 1 saat | e-posta | senkron-inceleme |

Runbook'lar `docs/runbooks/` altında Sprint 3'te yazılacak (ilk üçü: ai-kesinti, devre-kesici, openai-limit). Her alarm bildirimi runbook bağlantısı taşımalı.

## 6. Kurulum adımları (Console — tek seferlik)

1. Firebase → Analytics → BigQuery bağlantısını aç (Blaze plan gerekir).
2. Firestore → BigQuery export uzantısını `aiJobs` için kur (ya da scheduled export).
3. §3'teki log-based metric'leri oluştur (7 tanım).
4. §5 alarm politikalarını Cloud Monitoring'de tanımla; bildirim kanalı e-posta: civanftsocial@gmail.com.
5. Crashlytics velocity alert'lerini aç (varsayılan eşikler yeterli).
