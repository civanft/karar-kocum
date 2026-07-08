# Karar Veriyorum — Ürün Gereksinim Dokümanı (PRD)

| | |
|---|---|
| **Ürün Adı** | Karar Veriyorum |
| **Doküman Sürümü** | v1.0 |
| **Tarih** | 8 Temmuz 2026 |
| **Durum** | Taslak — Yatırımcı & Ekip İncelemesine Hazır |
| **Kategori** | Üretkenlik / Yaşam Tarzı — AI Destekli Karar Asistanı |
| **Platform** | iOS & Android (Flutter, tek kod tabanı) |

---

## 1. Problem Tanımı

### 1.1 Temel Problem

İnsanlar hayatlarının en önemli kararlarını **yapılandırılmamış, duygusal ve dağınık** bir süreçle veriyor:

- **Bilgi aşırı yüklemesi:** Bir telefon alacak kullanıcı ortalama 6+ saat inceleme videosu, karşılaştırma sitesi ve forum okuyor; sonunda çoğu zaman "en çok reklamı gördüğü" ürünü alıyor.
- **Karar felci (analysis paralysis):** Seçenek sayısı arttıkça karar verme süresi üstel olarak uzuyor ve karar kalitesi düşüyor (Schwartz, *Paradox of Choice*).
- **Bilişsel önyargılar:** Onay önyargısı (confirmation bias), sahiplik etkisi ve batık maliyet yanılgısı; kariyer, eğitim ve taşınma gibi geri dönüşü zor kararlarda ciddi maddi/manevi kayıplara yol açıyor.
- **Araç eksikliği:** Mevcut çözümler ya ilkel (kağıt-kalem artı/eksi listesi, Excel), ya tek alana kilitli (fiyat karşılaştırma siteleri sadece ürün için), ya da genel amaçlı sohbet botları (ChatGPT) — yapılandırılmış, tekrarlanabilir bir karar çerçevesi sunmuyor.

### 1.2 Problemin Boyutu

- Ortalama bir yetişkin günde ~35.000 mikro karar veriyor; yılda **20-30 adet "yüksek bahisli" karar** (satın alma >5.000 TL, kariyer, eğitim, taşınma, ilişki/yaşam) ile karşılaşıyor.
- Genç yetişkinlerin (18-34) %60'ından fazlası önemli kararlar öncesi "karar kaygısı" yaşadığını, %40'ı önemli bir kararı sırf zorlandığı için ertelediğini bildiriyor.
- ChatGPT'nin en yaygın kişisel kullanım senaryolarından biri "karar vermeme yardım et" — ancak deneyim yapılandırılmamış, kaydedilmiyor ve karşılaştırılabilir değil. **Talep kanıtlanmış, ürünleşme boşluğu açık.**

### 1.3 Neden Şimdi?

1. LLM maliyetleri düştü, kalite arttı → tarafsız ve derin analiz artık birim ekonomisi açısından mümkün.
2. "AI asistan" kategorisine tüketici alışkanlığı oluştu; kullanıcı AI'dan tavsiye almaya kültürel olarak hazır.
3. Dikey AI uygulamaları (genel chatbot yerine tek işi çok iyi yapan) mağazalarda yükseliş trendinde.

---

## 2. Çözüm Tanımı

**Karar Veriyorum**, kullanıcının önemli kararlarını dakikalar içinde yapılandırıp puanlayan, yapay zekâ ile tarafsız analiz sunan mobil karar asistanıdır.

### 2.1 Değer Önerisi (Value Proposition)

> "Saatler süren araştırmayı ve günler süren kararsızlığı, 5 dakikalık yapılandırılmış ve tarafsız bir analize dönüştürüyoruz."

### 2.2 Nasıl Çalışır? (Çekirdek Döngü)

1. **Karar oluştur** — "iPhone mu Samsung mu?", "Almanya mı Kanada mı?"
2. **Seçenekleri gir** — 2-10 seçenek, isteğe bağlı açıklama ve görsel.
3. **Artı/eksi ekle** — manuel veya AI önerili.
4. **Kriter belirle ve ağırlıklandır** — örn. Fiyat (9/10), Kamera (7/10); AI eksik kriterleri önerir.
5. **AI analizi al** — tarafsız değerlendirme, riskler, güçlü/zayıf yönler, gözden kaçan noktalar.
6. **Sonucu gör** — ağırlıklı skor, sıralama, güven seviyesi, önerilen seçenek, AI yorumu.
7. **Kaydet & paylaş** — karar geçmişi, PDF rapor, favoriler.

### 2.3 Çözümün Farkı

| Yaklaşım | Kağıt/Excel | ChatGPT | Karşılaştırma siteleri | **Karar Veriyorum** |
|---|---|---|---|---|
| Yapılandırılmış çerçeve | Kısmen | ✗ | ✗ | ✓ |
| AI tarafsız analiz | ✗ | ✓ (ham) | ✗ | ✓ (yapılandırılmış) |
| Ağırlıklı puanlama | Manuel, zahmetli | ✗ | ✗ | ✓ (otomatik) |
| Her karar tipi | ✓ | ✓ | ✗ (sadece ürün) | ✓ |
| Geçmiş & takip | ✗ | Zayıf | ✗ | ✓ |
| Paylaşılabilir rapor | ✗ | ✗ | ✗ | ✓ (PDF) |

---

## 3. Hedef Kullanıcılar

**Yaş aralığı:** 16-45

**Birincil segmentler:**

1. **Genç profesyoneller / beyaz yaka (24-38)** — yüksek bahisli satın almalar, kariyer değişimi, şehir değişimi. En yüksek ödeme istekliliği. **→ İlk hedef segment.**
2. **Üniversite öğrencileri ve adayları (16-24)** — bölüm/üniversite seçimi, yurtdışı eğitim, ilk iş teklifi. Viral yayılım potansiyeli en yüksek segment (tercih dönemleri mevsimsel zirve).
3. **Girişimciler / karar yoğun roller (28-45)** — tedarikçi seçimi, araç/ofis kiralama, işe alım karşılaştırması. B2B genişleme köprüsü.

**İkincil segmentler:** yurtdışına taşınmayı düşünenler, büyük satın alma öncesi çiftler (ortak karar), kariyer koçları ve danışmanlar (müşterileriyle kullanım).

**Coğrafya:** Faz 1 Türkiye (TR dili, yerel fiyatlama avantajı, App Store/Play'de zayıf yerel rekabet) → Faz 2 İngilizce konuşan pazarlar.

---

## 4. Kullanıcı Personaları

### Persona 1 — "Kararsız Profesyonel" Elif (29, İstanbul)
- Ürün pazarlama uzmanı, 65K TL/ay, iPhone kullanıcısı.
- **Durum:** İki iş teklifi arasında; biri yüksek maaş, diğeri remote + hisse.
- **Ağrı noktası:** Excel'de tablo yaptı ama ağırlıklandıramıyor; arkadaşlarının tavsiyeleri çelişkili; ChatGPT'ye sordu ama cevap "duruma göre değişir" düzeyinde kaldı.
- **Beklentisi:** Objektif, kriter bazlı bir sonuç + "gözden kaçırdığın şu" uyarısı.
- **Premium potansiyeli:** Yüksek — yılda 5-8 büyük karar, PDF'i mentoruyla paylaşmak istiyor.

### Persona 2 — "Tercih Dönemi" Mert (18, Ankara)
- YKS sonrası; Bilgisayar Müh. (Ankara) mı, Endüstri Müh. (İstanbul) mı?
- **Ağrı noktası:** Ailesi bir şey diyor, forumlar başka; iki haftadır uyuyamıyor.
- **Beklentisi:** Ücretsiz, hızlı, telefonda 5 dakikada sonuç; sonucu aile WhatsApp grubuna atmak.
- **Premium potansiyeli:** Düşük ama **viral değeri çok yüksek** — paylaşılan her sonuç ekranı organik edinim.

### Persona 3 — "Hesaplı Girişimci" Kaan (35, İzmir)
- 12 kişilik e-ticaret şirketi sahibi.
- **Durum:** Kargo anlaşması, muhasebe yazılımı, yeni depo lokasyonu — ayda 3-4 operasyonel karar.
- **Ağrı noktası:** Kararları içgüdüsel veriyor, sonra pişman oluyor; ekibiyle karar gerekçesini paylaşacak formatı yok.
- **Beklentisi:** Tekrarlanabilir şablonlar, PDF rapor, karar geçmişi.
- **Premium potansiyeli:** Çok yüksek — yıllık plana direkt geçer; ileride ekip planının (B2B) ilk müşterisi.

### Persona 4 — "Yurtdışı Hayali" Zeynep (26, Bursa)
- Hemşire; Almanya mı, İngiltere mi, kalmak mı?
- **Ağrı noktası:** Karar çok boyutlu (dil, maaş, vize, aile); YouTube videoları taraflı.
- **Beklentisi:** AI'ın bilmediği kriterleri hatırlatması ("dil sınavı maliyeti", "denklik süreci"), duygusal olmayan bir değerlendirme.

---

## 5. Kullanıcı Hikayeleri

### Epik A — Karar Oluşturma
- **US-A1:** Kullanıcı olarak, karar başlığımı tek satırda yazabilmek istiyorum ki hemen başlayabileyim. *(Kabul: başlık 3-100 karakter; boşsa devam edilemez; öneri örnekleri gösterilir.)*
- **US-A2:** Kullanıcı olarak, hazır karar şablonlarından (telefon, iş teklifi, üniversite, şehir, tatil) birini seçebilmek istiyorum ki sıfırdan düşünmek zorunda kalmayayım. *(Kabul: şablon seçilince örnek kriterler otomatik yüklenir.)*
- **US-A3:** Kullanıcı olarak, 2-10 arası seçenek ekleyebilmek istiyorum. *(Kabul: 2'den az seçenekle analiz başlatılamaz; 10'da ekleme kapanır.)*

### Epik B — Analiz Girdileri
- **US-B1:** Kullanıcı olarak, her seçeneğe artı ve eksi maddeleri ekleyebilmek istiyorum. *(Kabul: madde başına 1-140 karakter; sürükle-sırala; silme geri alınabilir.)*
- **US-B2:** Kullanıcı olarak, karara kriter ekleyip her kritere 1-10 önem puanı verebilmek istiyorum. *(Kabul: en az 1 kriter; slider ile puanlama; toplam ağırlık otomatik normalize edilir.)*
- **US-B3:** Kullanıcı olarak, AI'dan eksik kriter önerisi alabilmek istiyorum ki gözümden kaçanı fark edeyim. *(Kabul: öneriler tek dokunuşla eklenir; reddedilebilir.)*
- **US-B4:** Kullanıcı olarak, her seçeneği her kriterde 1-10 puanlayabilmek istiyorum; istersem bu puanlamayı AI'a devredebilmek istiyorum.

### Epik C — AI Analizi ve Sonuç
- **US-C1:** Kullanıcı olarak, "Analiz Et" dediğimde AI'ın tarafsız değerlendirme, risk ve güçlü/zayıf yön analizi üretmesini istiyorum. *(Kabul: yanıt < 15 sn; akış (streaming) ile gösterim; hata durumunda yeniden dene.)*
- **US-C2:** Kullanıcı olarak, sonuç ekranında ağırlıklı toplam skoru, sıralamayı, güven seviyesini ve önerilen seçeneği görmek istiyorum. *(Kabul: skorlar görsel bar/grafikle; güven seviyesi Düşük/Orta/Yüksek + gerekçe.)*
- **US-C3:** Kullanıcı olarak, kriter ağırlığını sonradan değiştirdiğimde skorların anında güncellenmesini istiyorum (what-if). *(Kabul: yeniden AI çağrısı olmadan, yerel hesapla < 100 ms.)*

### Epik D — Geçmiş, Rapor, Paylaşım
- **US-D1:** Kullanıcı olarak, geçmiş kararlarımı arayıp filtreleyebilmek ve favorilere ekleyebilmek istiyorum.
- **US-D2:** Kullanıcı olarak, karar sonucumu PDF rapor olarak oluşturup paylaşabilmek istiyorum. *(Kabul: PDF'te başlık, tarih, seçenekler, puan tablosu, AI özeti; sistem paylaşım sayfası açılır.)*
- **US-D3:** Kullanıcı olarak, sonuç ekranını görsel kart olarak sosyal medyada paylaşabilmek istiyorum. *(Viral döngünün motoru.)*

### Epik E — Hesap ve Premium
- **US-E1:** Kullanıcı olarak, Google/Apple/e-posta ile giriş yapabilmek istiyorum; **giriş yapmadan da ilk kararımı oluşturabilmeliyim** (anonim → sonradan hesaba bağlama).
- **US-E2:** Kullanıcı olarak, ücretsiz kotamı (aylık 5 karar) ve premium avantajlarını net görebilmek istiyorum.
- **US-E3:** Kullanıcı olarak, hesabımı silebilmeli ve verilerimi indirebilmeliyim. *(KVKK/GDPR zorunluluğu + mağaza politikası.)*

---

## 6. Kullanıcı Akışları

### 6.1 İlk Açılış → İlk Karar (Aktivasyon Akışı, hedef < 3 dokunuş)

```
Splash → (Onboarding: 2 kaydırmalı ekran, atlanabilir)
  → Ana Ekran [boş durum: "İlk kararını oluştur" + şablon kartları]
    → [Dokunuş 1] "Yeni Karar" veya şablon kartı
    → [Dokunuş 2] Başlık yaz / şablon başlığını onayla → Seçenekleri gir
    → [Dokunuş 3] "Analiz Et"
  → Sonuç Ekranı 🎉 (aktivasyon anı)
  → "Kaydetmek için giriş yap" (yumuşak kayıt duvarı)
```

### 6.2 Çekirdek Karar Akışı (dönen kullanıcı)

```
Ana Ekran → Yeni Karar → Başlık → Seçenekler (2-10)
  → Artı/Eksi (manuel + "AI ile doldur")
  → Kriterler (manuel + AI önerisi) → Önem puanları (slider)
  → Seçenek-kriter puanlama (manuel veya "AI puanlasın")
  → AI Analizi (streaming) → Sonuç Ekranı
  → [Kaydet] [PDF] [Paylaş] [What-if: ağırlık oyna]
```

### 6.3 Premium'a Geçiş Akışı

```
Tetikleyiciler:
  a) 6. karar denemesi → kota duvarı
  b) PDF butonu (ücretsizde filigranlı önizleme)
  c) "Gelişmiş AI analizi" rozeti
→ Paywall (aylık/yıllık; yıllıkta %40 indirim vurgusu; 7 gün deneme)
→ StoreKit / Play Billing satın alma → Başarı ekranı → kaldığı yere dön
```

### 6.4 Hesap Silme Akışı (mağaza zorunluluğu)

```
Profil → Hesap → Hesabı Sil → Uyarı + veri indirme teklifi
→ Onay (yeniden kimlik doğrulama) → Firestore + Auth kaydı silinir → Çıkış
```

---

## 7. MVP Kapsamı (v1.0)

**İlke:** Aktivasyon anı olan "ilk sonuç ekranını görme" deneyimini kusursuz yapmak; gerisini kesmek.

### Dahil ✓
| # | Özellik | Not |
|---|---|---|
| 1 | Karar oluşturma + 5 hazır şablon | telefon, iş, üniversite, şehir, tatil |
| 2 | Seçenek ekleme (2-10), açıklama, görsel | görsel isteğe bağlı |
| 3 | Manuel artı/eksi listeleri | |
| 4 | Kriter ekleme + 1-10 önem puanı + ağırlıklı skor motoru | tamamen yerel hesap |
| 5 | AI analizi (tek seviye): tarafsız değerlendirme, riskler, eksik kriter önerisi | sunucu proxy'li LLM çağrısı |
| 6 | Sonuç ekranı: skor, sıralama, güven seviyesi, öneri, AI yorumu | |
| 7 | Karar geçmişi: liste, arama, favori | |
| 8 | Anonim başlama + Google/Apple/e-posta girişi | Firebase Auth |
| 9 | Ücretsiz kota (aylık 5 karar) + Premium abonelik (aylık/yıllık) | RevenueCat veya native billing |
| 10 | PDF rapor (Premium) | ücretsizde filigranlı önizleme |
| 11 | Paylaşılabilir sonuç kartı (görsel) | ücretsizde de var — viral motor |
| 12 | Dark mode, TR + EN, temel erişilebilirlik | |
| 13 | Analytics + Crashlytics + Remote Config | |
| 14 | KVKK/GDPR: hesap silme, veri indirme, gizlilik politikası | |

### Hariç ✗ (bilinçli olarak v1 sonrasına)
- Ortak/grup kararı (arkadaşları davet edip oy verme)
- Karar sonrası takip ("kararından memnun musun?" hatırlatması)
- Web sürümü, widget'lar, Siri/Asistan kısayolları
- Karar koçu sohbet modu (serbest diyalog)
- B2B ekip planı
- Görselden otomatik seçenek tanıma (ör. ekran görüntüsünden ürün çıkarma)

---

## 8. Premium Kapsamı

| Özellik | Ücretsiz | Premium |
|---|---|---|
| Aylık karar hakkı | 5 | Sınırsız |
| AI analiz derinliği | Temel (özet analiz) | Gelişmiş (risk matrisi, senaryo analizi, "şeytanın avukatı" modu) |
| AI puanlama (seçenek×kriter otomatik) | ✗ | ✓ |
| PDF rapor | Filigranlı önizleme | Tam, paylaşılabilir |
| Karar geçmişi | Son 10 karar | Sınırsız + bulut senkronizasyonu |
| What-if ağırlık simülasyonu | ✓ (temel) | ✓ + senaryo kaydetme |
| Şablonlar | 5 temel | Tüm şablon kütüphanesi |
| Öncelikli AI kuyruğu | ✗ | ✓ |

**Fiyatlama hipotezi (test edilecek):**
- Aylık: 129,99 TL (~$3.99 küresel)
- Yıllık: 899,99 TL (~$29.99) — "ayda ~75 TL" çerçevelemesi, %40+ tasarruf vurgusu
- 7 gün ücretsiz deneme (yıllık planda)
- Fiyatlar Remote Config ile A/B test edilebilir; TR fiyatı satın alma gücüne göre ayrı ayarlanır.

---

## 9. Özellik Listesi (Tam Envanter)

### 9.1 Çekirdek
- [F-01] Karar CRUD (oluştur/düzenle/sil/arşivle)
- [F-02] Şablon sistemi (uzaktan güncellenebilir — Remote Config/Firestore)
- [F-03] Seçenek yönetimi (2-10; başlık, açıklama, görsel)
- [F-04] Artı/eksi listeleri (ekle/sil/sırala/geri al)
- [F-05] Kriter yönetimi + önem slider'ı (1-10)
- [F-06] Ağırlıklı puanlama motoru (yerel, deterministik, birim testli)
- [F-07] Seçenek×kriter puan matrisi (manuel/AI)

### 9.2 AI
- [F-10] AI analiz üretimi (streaming, yapılandırılmış çıktı: değerlendirme/risk/güçlü/zayıf/eksik kriter)
- [F-11] Eksik kriter önerisi
- [F-12] AI otomatik puanlama (Premium)
- [F-13] Gelişmiş analiz modları (Premium: senaryo, şeytanın avukatı)
- [F-14] Kötüye kullanım/moderasyon filtresi (kendine zarar, yasa dışı içerik → güvenli yönlendirme)

### 9.3 Sonuç & Paylaşım
- [F-20] Sonuç ekranı (skor barları, sıralama, güven seviyesi, öneri)
- [F-21] What-if ağırlık simülatörü
- [F-22] PDF rapor üretimi
- [F-23] Görsel sonuç kartı + sistem paylaşımı

### 9.4 Hesap & Veri
- [F-30] Anonim oturum → hesap yükseltme
- [F-31] Google / Apple / e-posta girişi
- [F-32] Bulut senkronizasyonu (Firestore)
- [F-33] Hesap silme + veri dışa aktarma (JSON)
- [F-34] Karar geçmişi: arama, filtre (tarih/kategori/favori)

### 9.5 Gelir
- [F-40] Abonelik altyapısı (App Store + Play Billing)
- [F-41] Paywall (Remote Config ile varyant testi)
- [F-42] Kota sayacı ve kota duvarı
- [F-43] Geri kazanım: deneme bitişi bildirimi, churn anketi

### 9.6 Platform & Kalite
- [F-50] Dark mode, Material 3, dinamik tip boyutu
- [F-51] TR + EN yerelleştirme
- [F-52] Erişilebilirlik (ekran okuyucu etiketleri, kontrast, dokunma hedefleri ≥ 44pt)
- [F-53] Çevrimdışı mod (yerel taslak; AI gerektiren adımlar kuyruklanır)
- [F-54] Analytics olay şeması + Crashlytics + performans izleme
- [F-55] Push bildirim altyapısı (taslak hatırlatma, deneme bitişi — spam değil)

---

## 10. Başarı Metrikleri

### Kuzey Yıldızı Metriği
> **Haftada tamamlanan karar sayısı** (sonuç ekranına ulaşan analiz adedi)

### Aktivasyon
| Metrik | Hedef (ilk 3 ay) |
|---|---|
| İndirme → ilk karar tamamlama | ≥ %45 |
| İlk kararın ilk oturumda tamamlanması | ≥ %35 |
| Onboarding tamamlama süresi | < 5 dk |

### Etkileşim & Tutundurma
| Metrik | Hedef |
|---|---|
| D1 / D7 / D30 retention | %35 / %18 / %10 |
| Kullanıcı başına aylık karar | ≥ 2,0 |
| Paylaşım oranı (sonuç başına) | ≥ %8 |

### Gelir
| Metrik | Hedef (6. ay) |
|---|---|
| Ücretsiz → deneme dönüşümü | ≥ %6 |
| Deneme → ücretli dönüşüm | ≥ %35 |
| Aylık churn (ücretli) | ≤ %8 |
| LTV / CAC | ≥ 3x |

### Kalite
- AI analiz beğeni oranı (👍/👎) ≥ %80
- Crash-free users ≥ %99,5
- Uygulama açılışı < 2 sn (soğuk), tüm ekranlar 60 FPS
- AI yanıt p95 < 15 sn
- Mağaza puanı ≥ 4,5

---

## 11. Rakiplerden Farklılaşma

### Rekabet Haritası
| Rakip | Ne yapıyor | Zayıf noktası |
|---|---|---|
| **ChatGPT / genel asistanlar** | Serbest sohbetle tavsiye | Yapı yok, kayıt yok, puanlama yok, her seferinde sıfırdan |
| **Decision Crafting / Pros&Cons uygulamaları** | Basit artı/eksi listeleri | AI yok, ağırlıklandırma ilkel, tasarım eski |
| **Fiyat karşılaştırma (Akakçe, Cimri vb.)** | Ürün fiyat odaklı | Sadece satın alma; kariyer/eğitim/yaşam kararları yok |
| **Excel / Notion şablonları** | Esnek matris | Zahmetli, mobil değil, AI yok |

### Savunulabilir Farklar (Moat)
1. **Yapı + AI birleşimi:** Ne salt sohbet ne salt tablo; ikisinin kesişimindeki tek yerel deneyim.
2. **Karar grafiği verisi:** Zamanla biriken anonimleştirilmiş kriter/tercih verisi → "senin gibi kullanıcılar bu kararda en çok şu kriteri önemsedi" içgörüsü (ağ etkisine giden yol).
3. **Türkçe ve yerel bağlam:** TR pazarında yerelleştirilmiş şablonlar (YKS tercihi, yurtdışı hemşirelik, kira vs. satın alma) — küresel oyuncuların girmeyeceği derinlik.
4. **Paylaşım döngüsü:** Sonuç kartı doğası gereği tartışma başlatır ("bak uygulama böyle dedi") → düşük CAC.
5. **Karar geçmişi kilidi:** Kullanıcının karar arşivi biriktikçe geçiş maliyeti artar.

---

## 12. Riskler ve Azaltma Planları

| # | Risk | Olasılık | Etki | Azaltma |
|---|---|---|---|---|
| R1 | **AI tavsiyesinin sorumluluğu** (kötü kariyer/finans kararı suçlaması) | Orta | Yüksek | "Karar destek aracıdır, nihai karar kullanıcınındır" çerçevesi; hassas alan tespiti (sağlık/hukuk/intihar vb.) → güvenli yönlendirme; ToS'ta açık sorumluluk reddi |
| R2 | **LLM maliyetinin birim ekonomiyi bozması** | Orta | Yüksek | Ücretsizde kota + küçük model; Premium'da büyük model; önbellekleme; prompt optimizasyonu; maliyet/karar metriği panoda izlenir |
| R3 | **Büyük oyuncu taklidi** (OpenAI/Google özelliği yerleşik sunar) | Orta | Orta | Hız + dikey derinlik + yerelleştirme + karar arşivi kilidi; platform değil ürün deneyimiyle yarış |
| R4 | **Düşük tutundurma** (karar verildi → uygulamaya dönüş yok) | Yüksek | Yüksek | Karar sonrası takip döngüsü (v1.1), şablon çeşitliliği, mevsimsel kampanyalar (YKS, Black Friday, yeni yıl kararları), bildirim stratejisi |
| R5 | **Mağaza reddi** (abonelik/veri politikaları) | Düşük | Orta | Hesap silme + gizlilik etiketleri baştan; App Review kurallarına ön uyum kontrol listesi |
| R6 | **KVKK/GDPR ihlali** | Düşük | Yüksek | Veri minimizasyonu, açık rıza, veri indirme/silme, işleme envanteri, aydınlatma metni |
| R7 | **AI halüsinasyonu** (yanlış fiyat/olgu iddiası) | Orta | Orta | AI çıktısı "görüş" olarak çerçevelenir, olgusal iddia formatından kaçınan prompt tasarımı; kullanıcı geri bildirim butonu |
| R8 | **Tek pazar bağımlılığı (TR kur/alım gücü)** | Orta | Orta | 6. aydan itibaren EN pazarlara açılım; fiyat bölgeselleştirme |

---

## 13. Teknik Gereksinimler

### 13.1 Mimari Özet
- **İstemci:** Flutter (iOS + Android tek kod tabanı), Clean Architecture (presentation / domain / data / core)
- **State:** Riverpod · **Routing:** GoRouter · **Network:** Dio · **Model:** Freezed + json_serializable
- **Backend:** Firebase — Auth, Firestore, Cloud Functions, Analytics, Crashlytics, Remote Config
- **AI:** LLM çağrıları **asla istemciden doğrudan yapılmaz**; Cloud Functions proxy'si üzerinden (API anahtarı sunucuda, rate limiting + kota kontrolü + moderasyon burada)
- **Abonelik:** StoreKit 2 + Google Play Billing (öneri: RevenueCat ile soyutlama)
- **PDF:** istemci tarafında üretim (`pdf` paketi), paylaşım sistem sayfasıyla

### 13.2 Veri Modeli (özet)
```
users/{uid}: profil, plan, kotaSayacı, tercihler
decisions/{id}: uid, başlık, kategori, şablonId, durum, oluşturma/güncelleme
  options[]: başlık, açıklama, görselUrl, artılar[], eksiler[]
  criteria[]: ad, ağırlık(1-10)
  scores{optionId×criterionId}: 1-10, kaynak(manuel|ai)
  aiAnalysis: özet, riskler[], güçlü[], zayıf[], önerilenKriterler[], güvenSeviyesi
  result: skorlar{}, sıralama[], önerilenSeçenek
```

### 13.3 Güvenlik & Uyum
- API anahtarları yalnızca sunucuda; istemcide secure storage yalnız oturum token'ları için
- Firestore security rules: kullanıcı yalnız kendi verisine erişir; Functions üzerinden yazılan alanlar istemciye kapalı
- Rate limiting (kullanıcı başına AI çağrısı/saat), input validation (uzunluk, içerik), SSL pinning değerlendirmesi
- KVKK/GDPR: hesap silme (Auth+Firestore kaskad), veri dışa aktarma (JSON), analitik için açık rıza

### 13.4 Kalite Standartları
- Unit + widget + integration testleri; **puanlama motoru %100, genel ≥ %80 kapsam hedefi**
- CI: her PR'da analiz + test; sürüm başına smoke test cihaz matrisi (min iOS 15 / Android 8)
- Performans bütçesi: soğuk açılış < 2 sn, ekran geçişleri 60 FPS, AI p95 < 15 sn

---

## 14. Monetizasyon Önerileri

### Birincil model: Freemium Abonelik (v1'de)
- Ücretsiz: aylık 5 karar, temel AI, filigranlı PDF önizleme, son 10 karar
- Premium: sınırsız karar, gelişmiş AI, tam PDF, sınırsız geçmiş + senkron
- Aylık ~129,99 TL / Yıllık ~899,99 TL; 7 gün deneme; bölgesel fiyatlama

**Neden abonelik:** AI maliyeti kullanımla ölçeklenir → tek seferlik satış zarar riski taşır; karar ihtiyacı süreklidir → abonelik meşrudur.

### İkincil / gelecek gelir kanalları (v1 sonrası, sırayla)
1. **Karar Paketi (consumable):** abonelik istemeyenlere 10 karar = tek seferlik ücret (dönüşüm merdiveni)
2. **B2B / Ekip planı:** girişimci ve danışmanlar için ortak karar alanı, kullanıcı başı fiyatlama
3. **Anlaşmalı içerik değil, etik sınır:** seçenek önerilerinde ücretli yerleştirme **yapılmaz** — tarafsızlık ürünün varlık sebebidir; bu bir pazarlama vaadi olarak da kullanılır ("önerilerimiz satılık değildir")

### Birim ekonomisi hipotezi (doğrulanacak)
- Karar başına AI maliyeti hedefi: temel < $0,01 · gelişmiş < $0,05
- Ücretsiz kullanıcı aylık maliyeti < $0,05 → 20 ücretsiz kullanıcıyı 1 premium finanse eder
- Hedef ARPU (karma): ≥ $0,35/ay · Premium ARPPU: ~$3

---

## 15. İlk Versiyon Yol Haritası

### Faz 0 — Temel & Doğrulama (Hafta 1-2)
- Teknik iskelet: Flutter + Clean Architecture + Riverpod + GoRouter + CI
- Tasarım sistemi: renk/tipografi/bileşen kütüphanesi (Material 3, dark mode)
- Prompt prototipi: 20 gerçek karar senaryosuyla AI çıktı kalitesi testi
- **Çıktı:** tıklanabilir çekirdek akış (yerel, AI'sız) + AI prompt v1

### Faz 1 — Çekirdek Döngü (Hafta 3-6)
- Karar/seçenek/artı-eksi/kriter ekranları + puanlama motoru (birim testli)
- Cloud Functions AI proxy + streaming analiz + sonuç ekranı
- Anonim oturum, yerel kayıt, karar geçmişi (temel)
- **Çıktı:** uçtan uca çalışan dahili beta (TestFlight/Internal Testing)

### Faz 2 — Hesap, Gelir, Cila (Hafta 7-10)
- Google/Apple/e-posta girişi + Firestore senkron + anonim→hesap taşıma
- Abonelik altyapısı + paywall + kota duvarı; PDF rapor; paylaşım kartı
- KVKK/GDPR akışları (silme/indirme), onboarding, boş durumlar, hata durumları
- **Çıktı:** kapalı beta (50-100 kullanıcı), aktivasyon hunisi ölçümü

### Faz 3 — Sertleştirme & Lansman (Hafta 11-14)
- Beta geri bildirimi ile UX düzeltmeleri; performans/erişilebilirlik geçişi
- Mağaza varlıkları (ikon, ekran görüntüleri, açıklama, ASO — TR+EN), inceleme gönderimi
- Analitik panosu + Remote Config deney altyapısı
- **Çıktı:** App Store + Google Play'de v1.0 🚀

### Lansman sonrası ilk çeyrek (v1.1 – v1.3 aday listesi)
- Karar sonrası takip döngüsü ("kararından memnun kaldın mı?") → tutundurma
- Şablon kütüphanesi genişletme + mevsimsel şablonlar (YKS, Black Friday)
- Görsel sonuç kartı varyantları + davetli ortak karar (grup oylaması) prototipi
- EN pazar açılımı ve fiyat deneyleri

### Lansman kriterleri (Go/No-Go)
- ✅ Aktivasyon ≥ %40 (beta), AI beğeni ≥ %75, crash-free ≥ %99,5
- ✅ Abonelik satın alma + geri yükleme + iptal akışları iki mağazada da doğrulandı
- ✅ Hesap silme + gizlilik politikası + veri indirme canlı
- ✅ p95 AI yanıtı < 15 sn, soğuk açılış < 2 sn

---

*Bu doküman yaşayan bir dokümandır; her faz sonunda metrik ve öğrenimlerle güncellenir.*
