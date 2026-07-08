# Karar Veriyorum — Sprint Planı

14 haftalık yol haritası (PRD §15) → **7 sprint × 2 hafta**. Her sprintin tanımı: hedef, kapsam (PRD user story referanslarıyla), bitti tanımı (DoD).

| Sprint | Faz | Tema | Çıktı |
|---|---|---|---|
| **1** | Faz 0→1 | Çekirdek karar akışı (yerel) | Cihazda uçtan uca: karar → seçenek → kriter → puan → sonuç (AI'sız, Firebase'siz) |
| **2** | Faz 1 | Firebase temeli + AI proxy | Anonim oturum, Firestore kalıcılığı, `analyzeDecision` fonksiyonu çalışır |
| **3** | Faz 1 | AI analiz deneyimi | Streaming analiz ekranı, eksik kriter önerisi, sonuç ekranında AI yorumu, what-if |
| **4** | Faz 2 | Hesap & senkron | Google/Apple/e-posta girişi, anonim→hesap linkleme, geçmiş: arama/filtre/favori |
| **5** | Faz 2 | Gelir | RevenueCat, paywall, kota duvarı, premium AI tier'ı |
| **6** | Faz 2 | Rapor & uyum | PDF rapor, paylaşım kartı, onboarding, hesap silme + veri indirme (KVKK) |
| **7** | Faz 3 | Sertleştirme & lansman | Performans/erişilebilirlik geçişi, mağaza varlıkları, beta düzeltmeleri, gönderim |

---

## Sprint 1 — Çekirdek Karar Akışı (yerel)

**Sprint hedefi:** Bir kullanıcı, internet ve hesap olmadan, uygulamada baştan sona bir karar oluşturup ağırlıklı skor sonucunu görebilsin. Aktivasyon deneyiminin omurgası bu sprintte kurulur; sonraki her şey bunun üstüne eklenir.

### Kapsam

| # | İş | Story | Not |
|---|---|---|---|
| 1.1 | Domain entity'leri: `Decision`, `Option`, `Criterion`, `CellScore` (Freezed) | — | mimari AD-6 |
| 1.2 | Domain validasyonları (başlık 3-100, seçenek 2-10, madde ≤140, ağırlık/puan 1-10) | US-A1, A3, B1, B2 | saf Dart + birim test |
| 1.3 | Skor motoru entegrasyonu: `ComputeResult` use case (Decision → DecisionResult) | US-C2 | motor Sprint 0'da yazıldı |
| 1.4 | `DecisionRepository` arayüzü + in-memory implementasyon | — | Firestore Sprint 2'de aynı arayüze takılır |
| 1.5 | `DecisionEditor` durum yönetimi (Riverpod AsyncNotifier; her mutasyonda kaydet) | US-B1-B4 | autosave debounce Sprint 2 (Firestore ile) |
| 1.6 | Ekranlar: Ana ekran (liste + boş durum), Yeni Karar (başlık), Düzenleme (seçenekler / kriterler / puanlar), Sonuç | US-A1, A3, B1, B2, B4, C2 | Material 3, dark mode |
| 1.7 | Router'a gerçek ekranların bağlanması | — | analyze/paywall placeholder kalır |
| 1.8 | Birim + provider testleri (validator, repository, editor) | — | kapsam kapısına giriş |

### Bilinçli olarak Sprint 1 DIŞINDA
Firebase (tümü), AI analizi, şablonlar (statik kart görselleri hariç), görsel yükleme, giriş, kota, geçmişte arama/filtre, PDF, l10n arb dosyaları (metinler şimdilik Türkçe sabit — Sprint 6'da arb'a taşınır).

### Bitti Tanımı (DoD)
- `flutter analyze --fatal-infos` temiz, katman denetimi yeşil
- Tüm testler geçiyor; skor motoru + validator %100 kapsam
- Simülatörde akış elle doğrulandı: yeni karar → 2 seçenek → 2 kriter → puanlama → sonuç ekranında doğru sıralama
- Eksik puan varken "Sonucu Gör" pasif ve açıklayıcı

---

## Sprint 2 — Firebase Temeli + AI Proxy

**Hedef:** Veriler cihaz yeniden başlatınca kaybolmasın; ilk gerçek AI analizi üretilsin.

- Firebase projeleri (dev/staging/prod) + `flutterfire configure` + App Check
- Anonim oturum otomatik açılır (US-E1'in ilk yarısı)
- `FirestoreDecisionRepository` (offline persistence açık) — in-memory ile arayüz değişmeden yer değiştirir; autosave debounce (800 ms)
- `searchTokens` üretimi (yazma anında)
- Cloud Functions: `analyzeDecision` v1 (moderasyon + kota + structured output + zod doğrulama), `suggestCriteria`
- Firestore rules deploy + rules birim testleri
- Şablon koleksiyonu + 5 temel şablon (US-A2)
- **DoD:** uygulama silinip yüklenince kararlar duruyor (senkron sonrası); emulator suite'te analiz ucu çalışıyor; rules testleri geçiyor

## Sprint 3 — AI Analiz Deneyimi

**Hedef:** "Analiz Et" düğmesi ürünün sihir anı olsun.

- Streaming analiz ekranı (ilk chunk < 2 sn algısı), hata/yeniden dene, kesinti kurtarma (idempotent çağrı)
- Eksik kriter önerisi UI'ı (tek dokunuşla ekle) (US-B3)
- Sonuç ekranı v2: AI yorumu, riskler, güçlü/zayıf yönler, güven gerekçesi (US-C1, C2)
- What-if simülatörü: ağırlık slider'ı → anlık yeniden sıralama (US-C3)
- Analytics olay şeması ilk yarısı (aktivasyon hunisi)
- **DoD:** 20 senaryoluk prompt değerlendirme setinde beğeni ≥ %75; p95 < 15 sn (staging)

## Sprint 4 — Hesap & Senkron

- Google / Apple / e-posta girişi; anonim→hesap `linkWithCredential` (çakışmada `mergeAccounts`) (US-E1)
- Geçmiş: arama (searchTokens), filtre (tarih/durum/favori), favori (US-D1)
- Çoklu cihaz senkron doğrulaması
- **DoD:** anonim veriyle giriş yapınca veri kaybı sıfır; E2E altın yol #1 yeşil

## Sprint 5 — Gelir

- RevenueCat entegrasyonu + webhook → `users/{uid}.plan` (US-E2)
- Paywall ekranı (Remote Config varyantlı), kota sayacı + duvarı, `PremiumGate`
- Premium AI tier'ı (`scoreOptions` dahil) + sunucu tarafı plan/kota zorlaması
- **DoD:** sandbox'ta satın alma / restore / iptal üç akış da doğrulandı; kota istemciden atlatılamıyor (rules + Functions testi)

## Sprint 6 — Rapor & Uyum

- PDF rapor (premium; ücretsizde filigranlı önizleme) (US-D2)
- Paylaşım kartı (`RepaintBoundary` render) (US-D3)
- Onboarding (2 ekran, atlanabilir)
- Hesap silme + veri indirme + consent gate (US-E3); gizlilik politikası & ToS bağlantıları
- l10n: metinlerin arb'a taşınması (tr + en)
- **DoD:** hesap silme kaskadı emulatorda doğrulandı; App Store gizlilik etiketleri dolduruldu

## Sprint 7 — Sertleştirme & Lansman

- Performans bütçeleri ölçüm + düzeltme (soğuk açılış < 2 sn, 60 FPS)
- Erişilebilirlik geçişi (ekran okuyucu, kontrast, dokunma hedefleri)
- Mağaza varlıkları: ikon, ekran görüntüleri, açıklamalar, ASO (TR+EN)
- Kapalı beta geri bildirim düzeltmeleri; crash-free ≥ %99,5
- App Store + Play gönderimi (Go/No-Go kriterleri PRD §15)
- **DoD:** iki mağazada da inceleme kuyruğunda 🚀
