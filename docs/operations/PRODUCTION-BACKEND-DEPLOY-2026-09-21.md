# Production Backend Hedefli Deploy — 21 Eylül 2026

| | |
|---|---|
| **İş paketi** | 6B0 |
| **Sonuç** | **BAŞARILI** — `analyzeDecision` ve `deleteAccount` güncel koda taşındı |
| **Kapsam** | Yalnız iki callable; başka hiçbir canlı kaynak |
| **Zaman dilimi** | Bu belgedeki tüm saatler **UTC**'dir |
| **İlişkili** | `docs/RELEASE-RUNBOOK.md` §7, `docs/MONITORING-PANOSU.md` §1 |

> **Public repo kuralı.** Bu belge e-posta adresi, tam policy/channel/budget
> kimliği, billing hesap kimliği, service account benzersiz kimliği, build
> operation kimliği, credential, ham log payload'ı veya kullanıcı verisi
> **içermez**.

---

## 1. Neden

Production'daki iki callable **5 Eylül** tarihli koddan çalışıyordu. O tarihten
sonra birleşen en önemli değişiklik, **AI işleme izninin sunucu tarafında
zorunlu kılınmasıydı** (İş Paketi 5). İstemcideki izin kapısı atlatılabilir
olduğu için, kullanıcı içeriğinin üçüncü taraf bir sağlayıcıya aktarılmasını
gerçekten engelleyen tek kapı sunucudadır — ve o kapı canlıda **yoktu**.

## 2. Zaman çizelgesi

| Saat (UTC) | Olay |
|---|---|
| 22:43:14 | Deploy komutu başladı |
| 22:44:30 | `analyzeDecision` yeni revizyona geçti |
| 22:44:34 | `deleteAccount` yeni revizyona geçti |
| 22:44:37 | Deploy tamamlandı |

Komut **bir kez** çalıştırıldı, retry yapılmadı.

## 3. Kaynak

Deploy, onaylanan tek bir commit'ten yapıldı: `origin/main` (PR #47 merge'ü)
üzerine eklenen **tek bir test commit'i**. O commit `analyzeDecision`'ın App
Check sözleşmesini regresyona kapatır ve seçenek **değerlerini değiştirmez**
(satır içi nesne, dışa verilen bir sabite taşındı).

## 4. Ne değişti

| Fonksiyon | Önceki revizyon | Yeni revizyon | Önceki kod |
|---|---|---|---|
| `analyzeDecision` | `…-00008-ped` | `…-00009-vek` | 5 Eylül 20:22 |
| `deleteAccount` | `…-00007-xag` | `…-00008-cif` | 5 Eylül 22:09 |
| `checkBackupFreshness` | `…-00001-fup` | **değişmedi** | — |

Deploy çıktısı yalnız iki fonksiyon için **update** bildirdi.

### Canlıya ilk kez giren davranışlar

- **AI işleme izni sunucuda zorunlu.** İzin yoksa istek, karar içeriği
  okunmadan reddedilir.
- **İzin sürümlüdür.** Eski sürümlü bir onay geçerli sayılmaz.
- **İzin kaydı silme kaskadına dahil.** Hesap silinince izin belgesi de
  temizlenir ve "veri kaldı mı" doğrulaması onu kapsar.
- **Logger secret redaksiyonu** ve genişletilmiş hata taksonomisi.
- `analyzeDecision` ayrıca, `deleteAccount`'ta 5 Eylül'de canlıya alınmış olan
  **silme bariyeri sertleştirmesini** ilk kez aldı.

## 5. Config eşitliği

Deploy'dan sonra her üç fonksiyonun tüm yapılandırma alanları deploy öncesi
taban çizgisiyle karşılaştırıldı. İki hedef fonksiyonda **yalnız `revision` ve
`updateTime`** değişti; şu alanların hepsi **aynı kaldı**: bölge, runtime,
bellek, CPU, timeout, concurrency, min/max instance, ingress, runtime service
account ve secret bağları. `checkBackupFreshness`'te **hiçbir alan**
değişmedi.

## 6. Artifact kanıtı

Deploy edilen kaynak paketi GCS'ten indirildi ve açıldı. İki fonksiyon **aynı
artifact'ı** paylaşıyor (tek build).

**Artifact = onaylanan commit.** İlgili altı kaynak dosyanın SHA-256'sı
artifact içinde ve commit'te **birebir aynı**.

**İzin kapısı artifact'ın içinde ve doğru sırada.** Derlenmiş
`lib/ai/analyze_service.js` içinde:

| Satır | Çağrı |
|---|---|
| **61** | **`assertAiConsent(...)`** |
| 63 | `readDecisionContent` — karar içeriği ilk kez okunur |
| 93 | `readJournal` |
| 106 | `reserve` — kredi rezervasyonu ve journal yazımı |
| 138 | `completeAnalysis` — sağlayıcı çağrısı |

İzin yoksa bunların **hiçbiri** çalışmaz: içerik okunmaz, journal yazılmaz,
kredi rezerve edilmez, sağlayıcıya dokunulmaz.

Derlenmiş `lib/privacy/ai_consent.js` içinde: sürüm sabiti, izinli alan
kümesi, `granted !== true` reddi ve eski sürüm reddi mevcut.

**Silme bariyerleri artifact'ın içinde.** `raiseDeletionBarrier`,
`completeDeletionBarrier`, `deleting`/`deleted` terminal durumları,
"devam ediyor" hatası ve `barrierFinalized` kontrolü derlenmiş çıktıda
doğrulandı. Silme doğrulama listesi izin koleksiyonunu kapsıyor.

**App Check korunuyor.** `enforceAppCheck` ve `consumeAppCheckToken` her iki
fonksiyonun derlenmiş seçeneklerinde `true`.

## 7. Test kapıları (deploy öncesi)

| Kapı | Sonuç |
|---|---|
| dependency audit | 0 açık |
| lint / build / typecheck | temiz |
| Functions unit | 340 geçti |
| Firestore rules (emulator) | 85 geçti |
| Privacy / izin (emulator) | 10 geçti |
| Emulator entegrasyon | 65 geçti |
| Mutasyon | **8/8 yakalandı** |

Mutasyonlar izin kapısının konumunu ve varlığını, izin sürüm kontrolünü, iki
callable'ın App Check bayraklarını, seçenek nesnesinin gerçekten bağlandığını
ve izin kaydının silme doğrulamasında bulunmasını kapsar.

## 8. Deploy sonrası gözlem

- Her iki servis **ACTIVE**, yeni revizyonlar trafiğin **%100'ünü** alıyor.
- **Güvenli negatif smoke:** kimliksiz ve App Check token'sız POST istekleri
  her iki fonksiyondan da **HTTP 401** aldı — enforcement yeni revizyonlarda
  da çalışıyor. Kullanıcı verisi oluşturulmadı, App Check gevşetilmedi,
  sahte production kullanıcısı yaratılmadı.
- **Backup heartbeat kesintisiz.** Saatlik kontrol deploy sırasında ve
  sonrasında `fresh` üretmeye devam etti.
- **11 metric / 11 alert policy** değişmedi; hepsi etkin, açık incident yok.
- **App Check yapılandırması değişmedi**; kayıtlı debug token sayısı hâlâ
  sıfır.

### Revizyon başlangıcındaki ERROR kayıtları — beklenen ve zararsız

Her yeni revizyonun başlangıcında iki adet `Error: Invalid request, unable to
process.` kaydı oluştu (toplam dört). Bunlar Cloud Run'ın başlangıç
probe'unun, yalnız POST kabul eden callable yüzeyine çarpmasıdır; kalıp
`MONITORING-PANOSU.md` §3.1'de zaten belgelidir. Kayıtlar `textPayload`
biçimindedir, `jsonPayload.message` taşımaz ve **AL-01 filtresiyle
eşleşmez** — filtreyle eşleşen kayıt sayısı sıfırdır. Hiçbir alarm
tetiklenmedi.

## 9. Smoke sınırları — dürüstçe

- **Uçtan uca pozitif akış test EDİLEMEDİ.** Başarılı bir analiz veya hesap
  silme çağrısı, gerçek bir cihazdan alınmış geçerli App Check token'ı
  gerektirir; App Check provider kayıtları henüz doğrulanmadı (Paket 6E) ve
  fiziksel cihaz testi yapılmadı (Paket 6F). Doğrulama bu yüzden yapısaldır:
  artifact içeriği, yapılandırma eşitliği, revizyon durumu ve negatif ret.
- **İzin kapısının canlıda gerçekten tetiklendiği gözlenmedi.** Kod ve
  artifact kanıtı vardır; canlı bir `ai-consent-required` reddi, ancak gerçek
  bir istemci çağrısıyla görülebilir.
- Production için otomatik smoke betiği **yoktur**; mevcut smoke betiği dev
  projesine bağlıdır.
- Deploy öncesi 24 saatte iki callable'a **hiç istek gelmemişti**; bu yüzden
  "trafik altında regresyon yok" denemez, yalnız "regresyon belirtisi yok"
  denebilir.

## 10. Rollback

Önceki revizyonlar ayakta tutuluyor. Geri alma, trafik yönlendirmesiyle
saniyeler içinde yapılır: `analyzeDecision` için `…-00008-ped`,
`deleteAccount` için `…-00007-xag` revizyonuna %100 trafik verilir. Komutlar
runbook §15'tedir. Daha yavaş alternatif, önceki commit'ten aynı hedefli
deploy'dur.

Bu turda rollback **gerekmedi ve çalıştırılmadı**.

## 11. Dokunulmayanlar

`checkBackupFreshness`, Firestore, Rules, Hosting, Storage, Cloud Scheduler,
log-based metric'ler, alert policy'ler, notification channel, budget'lar, IAM
ve service account yetkileri, App Check ayarları ve secret değerleri.
