# Backup Freshness Checker Rollout — 21 Eylül 2026

| | |
|---|---|
| **İş paketi** | 6C4 |
| **Sonuç** | **BAŞARILI** — saatlik kontrol canlıda, AL-10 / AL-11 kurulu |
| **Hedef** | Production Firestore `(default)` veritabanının günlük yedek tazeliği |
| **Zaman dilimi** | Bu belgedeki tüm saatler **UTC**'dir |
| **İlişkili** | `docs/MONITORING-PANOSU.md` §4, `docs/RELEASE-RUNBOOK.md` §6.1 |

> **Public repo kuralı.** Bu belge e-posta adresi, tam policy/channel/budget
> kimliği, billing hesap kimliği, service account benzersiz kimliği,
> credential, yedek UUID'si, ham log/audit payload'ı veya kullanıcı verisi
> **içermez**. Sayılar ve durumlar aggregate düzeyindedir.

---

## 1. Neden

Zamanlanmış yedeklerin **başarısı** için Cloud Logging'de kayıt, Firestore'da
da native bir freshness metriği yoktur (6C1 bulgusu). Bu yüzden başarısız bir
günlük yedek hiçbir bildirim üretmeden kaybolabiliyor ve RPO'yu sessizce
büyütüyordu. Release runbook'u bunu açık bir risk olarak kaydetmişti.

## 2. Ne kuruldu

| Adım | Sonuç |
|---|---|
| Cloud Scheduler API | Etkinleştirildi — **yalnız bu API**; başka kapalı API açılmadı |
| Adanmış service account | Oluşturuldu; **tek proje rolü**, yalnız yedek metadata'sı okuma yetkisi |
| Log-based metric | 2 adet (heartbeat + problem), label extractor **yok** |
| Fonksiyon | Yalnız yeni checker deploy edildi (hedefli deploy) |
| Scheduler job | 1 adet; saatte bir, UTC, ENABLED |
| Alert policy | AL-10 ve AL-11; ikisi de P1, doğrulanmış e-posta kanalına bağlı |

Sıra kasıtlıdır: **metric'ler deploy'dan önce** oluşturuldu, çünkü log-based
metric'ler geçmiş logları **backfill etmez** — sonradan oluşturulsalardı ilk
çalıştırmanın heartbeat'i sayılmazdı.

Beklenen Cloud Run servis adı deploy'dan önce repo export sözleşmesinden
türetildi ve deploy sonrası **gerçek servis etiketiyle yeniden doğrulandı**;
ikisi aynı çıktı.

## 3. En az yetki

Checker'ın service account'una verilen tek proje rolü yalnız iki izin taşır:
yedek **okuma** ve yedek **listeleme**. Verilmeyenler: veritabanı okuma/yazma,
Firestore yönetimi, Firebase yönetimi, secret erişimi, proje düzeyinde
editor/owner.

Mevcut callable'ların runtime service account'larının rolleri **değiştirilmedi**.

Deploy sırasında Firebase CLI, Scheduler'ın fonksiyonu çağırabilmesi için
**yalnız bu tek Cloud Run servisi üzerinde** kaynak düzeyinde bir invoker
bağlaması ekledi. Bu bir proje rolü değildir; checker'ın proje düzeyindeki rol
sayısı **bir** olarak kaldı.

Checker hiçbir secret'a bağlı değildir ve hiçbir Firestore belgesi okumaz.

## 4. Hedefli deploy kanıtı

Deploy hedefi repoda sabit bir değerdir ve testle korunur: tek bir fonksiyon
adı taşır, mevcut callable adlarını **içermez**. Deploy öncesi bu hem
programatik hem gözle doğrulandı.

Deploy çıktısı yalnız yeni fonksiyon için **create** işlemi bildirdi. Deploy
sonrası mevcut iki callable'ın `updateTime` değerleri deploy öncesi kaydedilen
taban çizgisiyle **birebir aynı** kaldı — yani analiz ve hesap silme yüzeyi
yeniden deploy edilmedi.

## 5. İlk kontrollü çalıştırma

Scheduler job'u **bir kez** elle çalıştırıldı. İlk `describe` çağrısı
`lastAttemptTime` alanını henüz boş döndürdü; tekrar çalıştırmak yerine
loglar ve job durumu okundu — sonuç birkaç saniye sonra tutarlı hâle geldi ve
çalıştırmanın başarılı olduğu görüldü. **Mükerrer çalıştırma üretilmedi.**

Üretilen tek satır:

| Alan | Değer |
|---|---|
| Olay | `backup_check_heartbeat` (INFO) |
| `checkResult` | `fresh` |
| `thresholdHours` | 30 |
| `ageHours` | ≈ 12,4 |
| `backupCount` | 9 |
| `readyDailyCount` | 7 |
| `unexpectedCount` | 0 |

Problem olayı **üretilmedi** — yedekler gerçekten tazeydi. Adanmış service
account'un dar rolü yetti; **403 alınmadı** ve yetki genişletilmedi.

Bir sonraki **zamanlanmış** çalıştırma (saat başı) manuel müdahale olmadan
ikinci heartbeat'i üretti: `checkResult=fresh`, yaş ≈ 12,6 saat. Böylece
kadansın kendi kendine işlediği doğrulandı.

Log satırlarında UID, belge içeriği, kullanıcı kimliği, credential, tam hata
metni veya yedek kaynak adı **yoktur**; alanlar düşük kardinalitelidir.

## 6. Metric propagation

Heartbeat metriğinde **gerçek bir veri noktası** görüldükten sonra AL-11
oluşturuldu. Problem metriğinde hiç veri noktası yoktur; yedekler taze olduğu
için bu beklenen durumdur ve **sentetik problem olayı üretilmedi**.

## 7. Alarmlar

| | AL-10 | AL-11 |
|---|---|---|
| Neyi yakalar | Checker **sorun buldu** | Checker **hiç çalışmadı** |
| Koşul | Problem sayacının saatlik toplamı sıfırın üstünde | Heartbeat metriği 3 saat boyunca yok |
| Öncelik | P1 | P1 |
| Bildirim | Doğrulanmış e-posta kanalı | Doğrulanmış e-posta kanalı |
| Eksik veri | INACTIVE | — (yokluk koşulunun kendisi) |
| Auto-close | 24 saat | 24 saat |
| Tekrar bildirim | Kapalı | Kapalı |

AL-10 üç olayı tek sayaçta toplar (`backup_freshness_stale`,
`backup_state_unexpected`, `backup_check_failed`): üçü de aynı müdahaleyi
gerektirir ve ayrı alarmlar aynı olayda üç bildirim üretirdi.

Her iki policy'nin belgelendirmesi runbook aksiyonunu taşır. AL-10'un
belgelendirmesi açıkça şunu yazar: **403 "yedek yok" anlamına gelmez**; ilk
soru "yedek başarısız mı" değil, "kontrol gerçekten çalıştı mı" olmalıdır.

Policy API'nin kısıtları nedeniyle eşdeğer dönüşüm gerekmedi: koşullar
istenen biçimde kabul edildi ve kaydedilen yapılandırma gönderilenle aynıdır.
Filtre veya semantik **gevşetilmedi**.

## 8. Son envanter

| Kaynak | Önce | Sonra |
|---|---|---|
| Notification channel | 1 | 1 |
| Log-based metric | 9 | 11 |
| Alert policy | 9 | 11 |
| Bildirimli policy | 8 | 10 |
| Fonksiyon | 2 callable | 2 callable + 1 checker |
| Scheduler job | 0 | 1 |

Değişmeyenler: PITR ve delete protection açık, yedek programları (günlük 7 gün
/ haftalık 28 gün, Pazar) aynı, App Check durumu aynı, secret listesi aynı,
iki budget da aynı (biri projeye özel, biri hesap geneli), mevcut
callable'ların `updateTime` değerleri aynı.

## 9. Dürüst sınırlar

- **AL-11'in tetiklendiği canlıda gözlenmedi.** Heartbeat'in üretildiği
  doğrulandı, ancak yokluk koşulunun gerçekten ateşlenmesi için checker'ın
  3 saat hiç çalışmaması gerekir; bu turda böyle bir kesinti üretilmedi.
  Log tabanlı metriklerde yokluk semantiği, serinin veri yazmayı gerçekten
  durdurmasına bağlıdır. Gerçek bir kesintide veya ayrı bir doğrulama turunda
  teyit edilmelidir.
- **AL-10'un üç problem olayı canlıda hiç oluşmadı** (CODE-CONTRACT-ONLY).
  Olay adları ve seviyeleri birim testleriyle, filtre kalıbı ise aynı serviste
  doğrulanmış heartbeat filtresiyle aynı biçimdedir.
- **30 saat bir başlangıç değeridir.** Gözlenen snapshot saati gün içinde
  kayar; 24 saat yanlış alarm üretirdi. Gerçek gözlemle ayarlanmalıdır.
- **Alarm yedeği kurtarmaz.** Kapatılan risk, başarısız bir yedeğin *sessizce*
  kaybolmasıdır; yedeğin kendisinin başarısız olması hâlâ mümkündür.
- Checker yalnız **günlük** program tazeliğini ölçer. Haftalık yedekler
  kapsamdadır ama daily tazeliği için aday sayılmaz.

## 10. Maliyet

Saatte bir çalışan, tek instance'lı, 256 MiB belleğe sahip ve saniyenin altında
süren bir fonksiyon ayda ~720 çağrı üretir. Cloud Scheduler'ın ücretsiz kotası
ayda üç job'dur. İki ek log-based metric ve iki policy için ayrı ücret
alınmaz; yazılan log hacmi satır başına birkaç yüz bayttır. Beklenen ek
maliyet **ihmal edilebilir** düzeydedir ve projeye özel budget bildirimi
zaten yürürlüktedir.

Bu bir tahmindir; gerçek fatura kalemleri ay sonunda doğrulanmalıdır.
