# Restore Tatbikatı — 2026-09-14

| | |
|---|---|
| **Tarih** | 2026-09-14 (UTC) |
| **İş paketi** | 6B2 (yürütme) · 6B3 (kanıt kaydı) |
| **Sonuç** | **PASS** |
| **İlgili** | [../RELEASE-RUNBOOK.md](../RELEASE-RUNBOOK.md) §4–§5 |

> **Veri minimizasyonu.** Bu repo public kabul edilir. Belge **sanitize**
> edilmiştir: veritabanı UID'leri, tam backup/operation kaynak adları, quota
> project numarası, e-posta adresleri, ham audit log ve yerel dosya yolları
> **kasten yazılmamıştır**. Tam değerler repo dışında saklanmaktadır.

---

## 1. Amaç ve kapsam

Yedeklerden **gerçekten** geri dönülebildiğini, production'a dokunmadan
kanıtlamak. Yedek programı ve PITR'ın var olması tek başına bir kurtarma
yeteneği **değildir**; tatbikat edilmemiş bir yedek doğrulanmamış bir
varsayımdır.

**Kapsam içi:** managed backup'tan **yeni bir hedef veritabanına** restore,
yapısal doğrulama, production izolasyonunun kanıtlanması, koşullu temizleme.

**Kapsam dışı:** kullanıcı belgesi veya veri içeriği okuma · production
`(default)` üzerinde herhangi bir değişiklik · deploy · rules/indexes/Functions
· App Check, IAM, alert, notification, budget veya secret değişikliği ·
Auth kullanıcı verisi · imzalama materyali.

Tatbikat sırasında **hiçbir kullanıcı belgesi veya veri içeriği okunmadı**;
tüm doğrulamalar metadata, toplam sayım ve audit log üzerinden yapıldı.

## 2. Onaylanan kaynak ve hedef

| | |
|---|---|
| Kaynak proje | `karar-kocum-production` (istemci config'lerinde zaten public) |
| Kaynak veritabanı | `(default)` — `eur3`, Standard, Firestore Native |
| Kullanılan yedek | **daily READY backup**, snapshot `2026-09-14T04:46:08Z` |
| Hedef veritabanı | `restore-drill-20260914` (geçici) |
| Hedef bölgesi | `eur3` |
| Operation kimliği | `redacted` |
| Kaynak UID / hedef UID | **farklı** — tam değerler public repoda tutulmuyor |

Hedef veritabanı **önceden oluşturulmadı**; restore operation'ı onu kendisi
oluşturdu.

## 3. Zaman çizelgesi (UTC)

| Saat | Olay |
|---|---|
| 04:46 | Kullanılan yedeğin snapshot anı |
| 12:50 | `RestoreDatabase` admin çağrısı — audit log kaydı, durum `ok` |
| 12:51 | Long-running operation başladı |
| ~13:06 | 15. dakika: operation hâlâ `PROCESSING`, ilerleme `30/100` |
| ~13:06 | `databases describe` → `sourceInfo.progress = COMPLETED` (operation ile **ayrışma**) |
| 13:07 | Operation `done=true`, `SUCCESSFUL`, `100/100` |
| 13:15 | Tüm kapılar PASS → drill veritabanı silindi |

**Platform restore süresi: 16 dakika 56 saniye.** Bu tek bir gözlemdir;
insan karar ve doğrulama süresi **hariçtir** ve bir SLA değildir.

## 4. Restore sonucunun özeti

- Operation: `done = true` · `SUCCESSFUL` · `100/100` · hata **yok**.
- Kaynak yedek ve hedef kimliği, operation metadata'sında **birebir** doğrulandı.
- Hedef: `eur3` / Standard / Firestore Native — kaynakla aynı.
- Hedef UID, kaynak UID'den **farklı** (gerçekten yeni bir veritabanı).
- Hedef, restore sonucu **delete protection AÇIK** olarak oluştu.

**Süre hakkında dürüst kayıt.** Operation 15 dakikalık gözlem penceresini
aştı. İptal edilmedi, yeniden başlatılmadı, silinmedi. Veritabanı kaynağı
`COMPLETED` derken operation `PROCESSING` diyordu; bu çelişkiyi çözmek için
**kısa ve sınırlı** bir ek kontrol yapıldı ve operation başarıyla kapandı.
Karar, **operation** durumuna göre verildi.

## 5. PASS/FAIL matrisi

| # | Zorunlu kontrol | Sonuç |
|---|---|---|
| 1 | Restore operation `done=true`, hatasız, `SUCCESSFUL` | **PASS** |
| 2 | Operation metadata'sında kaynak yedek ve hedef birebir doğru | **PASS** |
| 3 | Hedef kimliği doğru ve UID kaynaktan farklı | **PASS** |
| 4 | Hedef location / edition / type kaynakla aynı | **PASS** |
| 5 | Composite index configuration eşleşiyor | **PASS** |
| 6 | TTL beklentisi (aktif politika yok) | **PASS** |
| 7 | Security Rules beklentisi (taşınmadı) | **PASS** |
| 8 | Production izolasyonu | **PASS** |
| 9 | Audit log kaydı ve tam hedef kimliği | **PASS** |
| 10 | Beklenmeyen admin mutasyonu yok | **PASS** |

**Zorunlu kontrollerin tamamı PASS.**

**Zorunlu olmayan, üretilemeyen gözlem.** Kaynak/hedef **depolama boyutu
karşılaştırması yapılamadı**: Cloud Monitoring depolama metriği tatbikat
süresince hedef veritabanı için veri noktası üretmedi ve drill veritabanının
ömrü ~25 dakikaydı. Bu bir zorunlu kapı **değildir** ve **restore başarısızlığı
olarak yorumlanmadı**.

> **Düzeltme (2026-09-16, 6C1 ölçümü).** Bu bölümün ilk sürümü metriğin
> "yaklaşık günlük" örneklendiğini söylüyordu; bu yanlıştı. Native descriptor
> örnekleme periyodu **60 saniyedir**, ancak gerçek seri **aralıklı**
> yayınlanır ve saatlerce boşluk olabilir (6C1: son 240 saatin 91'inde veri).
> Kısa ömürlü bir drill veritabanının bu boşluğa denk gelip metrikte hiç
> görünmemesi beklenen bir yanlış negatiftir. Tatbikat sonucu ve diğer
> kanıtlar bu düzeltmeden etkilenmez.

## 6. Index / TTL / rules gözlemleri

| Öğe | Backup ile geldi mi? | Gözlem |
|---|---|---|
| Composite index configuration | **Evet** | Kaynak 3 ↔ hedef 3; queryScope/apiScope/fieldPath/order normalize edilerek karşılaştırıldı, tanımlar aynı |
| Security Rules | **Hayır** | Hedef veritabanı için rules release'i yok |
| TTL policies | **Hayır** | Kaynak 0 ↔ hedef 0 **aktif** politika |

**TTL sonucunun zayıflığı — dürüst kayıt.** Kaynakta aktif TTL politikası
**zaten yoktu**. Bu yüzden hedefte TTL bulunmaması beklenen sonuçtur ve
**tek başına güçlü bir restore kanıtı değildir**. TTL'in kapsam dışı olduğu,
ancak kaynakta aktif bir politika varken anlamlı biçimde gözlemlenebilir.

**Operasyonel sonuç:** rules taşınmadığı için restore edilen bir veritabanı
**kendi başına servis edilebilir durumda değildir**; rules ayrıca deploy
edilmelidir.

## 7. Production izolasyon kanıtının yöntemi

İzolasyon **write-count metriğiyle kanıtlanmadı** — canlı trafik bu metriği
zaten değiştirir ve tek başına ne kanıt ne de karşı-kanıttır.

Kullanılan yöntem:

1. **Operation metadata** — kaynak yedek ve hedef veritabanı kimliği birebir
   karşılaştırıldı; hedefin `(default)` olmadığı programatik olarak doğrulandı.
2. **Audit log** — `RestoreDatabase` çağrısında `resourceName` ve
   `databaseId` alanlarının **tam hedef kimliğini** taşıdığı, durumun `ok`
   olduğu doğrulandı.
3. **Mutasyon taraması** — ilgili pencerede Firestore admin mutasyonu
   **1 adet** ve hedefi **drill veritabanı**; `(default)` hedefli mutasyon
   **0**.
4. **Yapılandırma karşılaştırması** — `(default)` veritabanının tüm
   yapılandırma alanları tatbikat öncesi/sonrası **değişmedi**.

**Metodolojik düzeltme — dürüst kayıt.** İlk rules kontrolünde bir **HTTP 403
yanıtı yanlışlıkla "boş liste" olarak yorumlandı** ve geçici olarak yanlış bir
sonuç üretti. Hata fark edildi ve düzeltildi: kota atfı yanlış bir tüketici
projesine gidiyordu. **Global CLI yapılandırması değiştirilmeden**, istek
başına kota atfı (`x-goog-user-project`) kullanılarak gerçek liste alındı.
Bundan çıkan kalıcı kural: **her API çağrısında HTTP durum kodu ve
yapılandırılmış hata gövdesi ayrıştırılmalı**; "sonuç yok" ile "erişemedim"
aynı şey değildir.

## 8. Koşullu temizleme sonucu

Temizleme **yalnız tüm zorunlu kontroller PASS olduğu için** yapıldı.

Silme öncesi kapılar: hedef kimliği drill deseniyle eşleşiyor ✓ · UID kaynak
UID'den farklı ✓ · komutta `(default)` geçmiyor ✓ · kaynak `(default)` delete
protection'ı **açık** ✓

Drill veritabanı **delete protection açık** geldiği için, **yalnız onun için**
kapatıldı; ardından veritabanı silindi.

| İşlem | Kaynak |
|---|---|
| **Oluşturuldu** | `restore-drill-20260914` (restore operation'ı tarafından) |
| **Değiştirildi** | Yalnız aynı drill veritabanının delete protection'ı |
| **Silindi** | `restore-drill-20260914` |

**Silme sonrası production durumu:** yalnız `(default)` kaldı · UID, PITR
(açık, 7 gün), delete protection (açık), retention, konum, edition ve type
**değişmedi** · **2 yedek programı** korundu (`updateTime` değişmedi) ·
mevcut yedeklerin **tamamı READY** ve hiçbiri silinmedi.

**Net kalıcı drill kaynağı: yok.**

## 9. Öğrenilen dersler

1. **Restore hedefi önceden oluşturulmaz.** Operation onu kendisi oluşturur.
   Önceki tur planında sıralama tersti — hedefin restore'dan önce elle
   hazırlanacağı varsayılmıştı; bu **yanlıştı** ve düzeltildi.
2. **`--destination-database` `(default)` değerini sözdizimsel olarak kabul
   eder.** CLI bunu yazım hatası saymaz. Tek karakterlik bir hata production'ı
   hedefler. Destination hem gözle hem **programatik** doğrulanmalıdır.
3. **Restore edilen veritabanı delete protection AÇIK gelir.** Temizleme adımı
   bunu kapatmayı gerektirir ve bu kapatma **yalnız drill hedefine**
   uygulanmalıdır. *(Bu tatbikatta ilk kez gözlemlendi.)*
4. **Başarı otoritesi long-running operation'dır.** `databases describe`
   `COMPLETED` derken operation birkaç dakika daha `PROCESSING` kalabilir;
   bu ayrışma normaldir. *(Bu tatbikatta ilk kez gözlemlendi.)*
5. **Sabit bir 15 dakika sınırı başarısızlık ölçütü değildir.** Uzayan bir
   operation iptal edilmez, yeniden başlatılmaz; kimliği korunup izleme
   sürdürülür ve aynı hedefe ikinci restore başlatılmaz.
6. **Hata yanıtı boş sonuç değildir.** 403, "kayıt yok" diye okunursa eksik
   bir doğrulama "temiz" diye raporlanır.
7. **Aralıklı metrikler yanlış negatif üretir.** Dakikalık örneklenen ama
   saatlerce boşlukla yayınlanan bir depolama metriği, dakikalar yaşayan bir
   kaynağı hiç göstermeyebilir.
8. **Beklenen sonuç her zaman güçlü kanıt değildir.** Kaynakta hiç aktif TTL
   yokken hedefte TTL çıkmaması, TTL'in kapsam dışı olduğunu tek başına
   kanıtlamaz.

## 10. Sonraki tatbikat

Tatbikat sıklığı: **6 haftada bir**.

- Son tatbikat: **2026-09-14** — **PASS**
- Sıradaki için **takvim önerisi: 2026-10-26**

Bu bir **öneridir**. Hatırlatma, zamanlanmış görev veya otomasyon
**kurulmamıştır**; takip insan sorumluluğundadır.

## 11. Açık kalan işler

| İş | Durum | Kapsam |
|---|---|---|
| **Yedek başarı/başarısızlık alarmı** | **YOK.** Başarısız bir programlı yedek şu anda **sessizce** kaybolur. | **6C** |
| **Notification channel ve incident owner** | **YOK.** Alarm kurulsa bile gideceği bir yer yok. | **6C** |
| **Auth kullanıcı verisi felaket kurtarma** | **YOK.** Firebase Auth kullanıcıları bu yedekleme kapsamında **değildir**; Firestore restore'u Auth kaybını telafi etmez. | Ayrı iş |
| **İmzalama materyali felaket kurtarma** | **YOK.** Signing key, keystore ve provisioning profile yedekleme kapsamında **değildir**; kaybı mağaza güncellemelerini kalıcı olarak engelleyebilir. | Ayrı iş |
| **Belge düzeyinde içerik doğrulaması** | **Yapılmadı** (veri minimizasyonu gereği kasten). Tatbikat **yapısal** düzeyde doğrulanmıştır. | Ayrı [KARAR] |

**Bu tatbikat, yukarıdaki işlerin hiçbirini kapatmamıştır.**
