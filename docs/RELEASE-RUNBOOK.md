# Release Runbook

| | |
|---|---|
| **Sürüm** | v1.2 — 16 Eylül 2026 (canlı gerçeklik senkronu: App Check, monitoring) |
| **Kapsam** | Yayın adayı üretimi, canlı işlemlerin güvenli sırası, rollback sınırları |
| **Durum** | **Karma.** §4–§5 (backup/PITR/restore tatbikatı) **canlıda uygulandı ve doğrulandı** (6B1/6B2); §6 monitoring **kısmen canlıda** (6C2/6C3). Belgedeki **diğer** canlı adımlar hâlâ **plandır ve uygulanmadı**. |

> **Okuma kuralı.** Bu belgede üç ayrı ifade kullanılır ve karıştırılmaz:
> **[REPO]** repoda kanıtlanmış · **[CANLI]** canlı sistemde yapılacak ·
> **[KARAR]** insan onayı olmadan ilerlenemez.

---

## 0. Kalıcı uygulama kimlikleri — KARAR KAPISI

| Kimlik | Değer | Kaynak |
|---|---|---|
| Android `applicationId` | `com.kararveriyorum.karar_veriyorum` | `android/app/build.gradle.kts` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.kararveriyorum.kararVeriyorum` | `ios/Runner.xcodeproj/project.pbxproj` |
| Apple Team | `SXD4YLW556` | aynı dosya |

Bunlar **mevcut teknik kimliklerdir; değişiklik önerilmemiştir ve kalıcılık
onayı beklenmektedir.** Marka adı ("Karar Koçum") ile birebir aynı olmaları
**gerekmez**; bir uygulama kimliğinin görünen adla uyuşmaması normaldir ve
tek başına değiştirme gerekçesi değildir.

Ancak şunlar bu kimliklere **kalıcı olarak** bağlıdır: Firebase iOS/Android
app kayıtları, App Attest ve Play Integrity yapılandırması, Play App Signing,
App Store Connect kaydı. **İlk mağaza yüklemesinden sonra değiştirilemezler.**

> **[KARAR] Kapı 0.** İlk artifact mağazaya yüklenmeden önce bu kimlikler
> için açık insan onayı alınmalıdır. Onay yoksa §11'e geçilmez.

---

## 1. Version ve build number stratejisi

### 1.1 Kavramlar

| Kavram | Anlamı | Nereden gelir |
|---|---|---|
| **Marketing version** | Kullanıcının gördüğü sürüm (`1.0.0`) | `pubspec.yaml` → `version:` öncesi |
| **Build number** | Aynı marketing version'ın kaçıncı derlemesi (`+1`) | `pubspec.yaml` → `version:` sonrası |
| Android `versionName` | Marketing version karşılığı | `flutter.versionName` |
| Android `versionCode` | Build number karşılığı — **tamsayı, monoton artan** | `flutter.versionCode` |
| iOS `CFBundleShortVersionString` | Marketing version karşılığı | `MARKETING_VERSION` |
| iOS `CFBundleVersion` | Build number karşılığı | `$(FLUTTER_BUILD_NUMBER)` |

Tek kaynak `pubspec.yaml`'daki `version: <marketing>+<build>` alanıdır; her
iki platform da bundan türer. Biçim `test/release/toolchain_pin_test.dart`
ile doğrulanır.

### 1.2 Kurallar

1. **Her mağaza yüklemesinde build number ARTAR.** Aynı build number ile
   ikinci bir yükleme her iki mağazada da reddedilir.
2. **Başarısız bir yükleme build number'ı tüketmiş olabilir.** İşlenmiş ama
   reddedilmiş bir yüklemeden sonra aynı numarayı tekrar kullanmayı denemek
   yerine numarayı artırın.
3. **Aynı artifact'i yeniden üretmek ≠ yeni bir yükleme.** Aynı commit'ten
   yeniden derleme sürüm artırmaz; yalnız mağazaya **yeni** bir şey
   yüklemek artırır.
4. Marketing version yalnız kullanıcıya anlatılacak bir değişiklik varsa
   artar; build number **her** yüklemede artar.
5. Sürüm artırma kararı **§3 kapılarından sonra, §11'den önce** verilir.
   Kapılar kırmızıyken sürüm artırılmaz.

### 1.3 Terimler

| Terim | Anlamı |
|---|---|
| **RC (release candidate)** | Tüm kapıları geçmiş, mağazaya aday commit. Tag: `v<marketing>+<build>-rc<N>`. |
| **Internal testing** | Play'in iç test kanalı. Gerçek imzalı AAB, sınırlı test kullanıcısı. |
| **TestFlight** | Apple'ın karşılığı. Internal test için App Store review gerekmez. |
| **Production** | Genel yayın kanalı. |

Release branch yaklaşımı: `main`'den `release/v<marketing>` dallanır;
yalnız hotfix cherry-pick'i alır; yayın sonrası tag'lenir ve `main`'e geri
birleştirilir.

> **[REPO] Bu dilimde `version: 1.0.0+1` DEĞİŞTİRİLMEDİ.** Yalnız strateji
> yazıldı ve biçim testle kilitlendi.

---

## 2. Preflight

1. `git fetch --prune`; çalışma ağacı temiz mi?
2. `origin/main` CI'ı yeşil mi?
3. Hedef commit belirlendi mi? (RC bu commit'tir.)
4. **[KARAR] Kapı 0** (§0) onaylandı mı?
5. Açık Dependabot PR'ları gözden geçirildi mi? (Birleştirme zorunlu değil;
   bilinçli karar olmalı.)

## 3. Test ve güvenlik kapıları — [REPO]

Hepsi yeşil olmadan ilerlenmez:

```
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
bash scripts/check_layers.sh
flutter test --coverage && bash scripts/check_coverage.sh 80
python3 scripts/check_publication.py && python3 scripts/test_publication_guard.py
bash scripts/check_secrets.sh          # geçmiş
bash scripts/check_secrets.sh staged   # staged
npm --prefix functions run lint && npm --prefix functions run build
npm --prefix functions run typecheck && npm --prefix functions test
npm --prefix functions run test:rules
npm --prefix functions run test:privacy
npm --prefix functions run test:emulator
npm --prefix functions audit --audit-level=moderate
npm --prefix scripts/smoke test
git diff --check
```

## 4. Backup / RPO / RTO — [KARAR] + [CANLI] + ÜCRET

**Durum: canlıda yapılandırıldı ve doğrulandı (İş Paketi 6B1, 2026-09-14).**
Aşağıdaki değerler production `(default)` veritabanında **gözlemlenmiştir**;
ürün garantisi, taahhüt veya SLA **değildir**.

| Ayar | Değer | Durum |
|---|---|---|
| PITR | **Açık** — 7 gün pencere | [CANLI] ✅ |
| Delete protection | **Açık** | [CANLI] ✅ |
| Günlük yedek programı | retention **7 gün** | [CANLI] ✅ |
| Haftalık yedek programı | **Pazar (UTC)** — retention **28 gün** | [CANLI] ✅ |
| Konum | `eur3` (veritabanıyla aynı bölge) | [CANLI] ✅ |

### 4.1 RPO / RTO hedefleri — [KARAR] alındı

**Bunlar dahili çalışma hedefleridir. Kullanıcıya verilmiş bir garanti veya
SLA DEĞİLDİR ve mağaza/pazarlama metninde öyle sunulamaz.**

| Hedef | Değer | Dürüst sınır |
|---|---|---|
| **RTO** | **≤ 4 saat** | İlk tatbikatta *platform* restore süresi **16 dakika 56 saniye** ölçüldü. Bu **tek bir gözlemdir**; **insan karar, onay ve doğrulama süresi hariçtir** ve gelecekteki süreler için taahhüt değildir. Süre veri hacmiyle büyür. |
| **RPO — PITR yolu** | 7 günlük pencere içinde **dakika hassasiyeti** | Yalnız pencere **içinde** geçerlidir. Pencere dışına düşen bir olayda tek yol yedeklerdir. |
| **RPO — yedek yolu** | Son **başarılı** snapshot anı | Belirleyici olan programın varlığı değil, **snapshot'ın başarısıdır**. Başarısız bir programlı yedek RPO'yu **sessizce** büyütür — bu yüzden backup freshness checker (6C4) açık bir eksiktir. |

### 4.2 Tatbikat sıklığı

Restore tatbikatı **6 haftada bir** tekrarlanır (§5).

- Son tatbikat: **2026-09-14** — sonuç **PASS**.
- Sıradaki tatbikat için **takvim önerisi: 2026-10-26**.

Bu bir **öneridir**. Hatırlatma, zamanlanmış görev veya otomasyon
**kurulmamıştır**; takip insan sorumluluğundadır.

### 4.3 Yetki sınırı

Backup/restore yetkisi **yalnız operatör kimliğine** verilir ve
**Functions runtime servis hesabına verilmez** — uygulama çalışma zamanının
yedek silme veya restore başlatma yeteneği olmamalıdır.

Ayrı bir yol olan export/import için bucket, Firestore ile **aynı bölgede**
(`eur3`) olmalıdır.

## 5. Restore tatbikatı — [CANLI] + ÜCRET

**Durum: ilk tatbikat 2026-09-14'te yapıldı ve PASS aldı.** Sanitize kanıt:
[`operations/RESTORE-DRILL-2026-09-14.md`](operations/RESTORE-DRILL-2026-09-14.md).

Restore **üretime prova edilemez**. İki ayrı yol vardır ve karıştırılmaz:

- `gcloud firestore import` — **mevcut koleksiyonların üzerine yazar.**
  Tatbikatta kullanılmaz.
- **Managed backup restore** — **yeni bir hedef veritabanı oluşturur.**
  Tatbikatta kullanılan yol budur.

### 5.1 Hedef veritabanı ÖNCEDEN OLUŞTURULMAZ

**Restore hedefi elle oluşturulmaz.** Restore operation'ının kendisi yeni
veritabanını oluşturur. Hedefi önceden oluşturmak restore'u başarısız kılar.

> **KRİTİK KESKİN KENAR.** `--destination-database` parametresi `(default)`
> değerini **sözdizimsel olarak kabul eder**; CLI bunu bir yazım hatası
> olarak **reddetmez**. Yanlış yazılmış tek bir destination **production
> veritabanını hedefler.**
>
> Bu yüzden destination her çalıştırmada **iki kez** doğrulanır:
> **(a)** komut çalıştırılmadan önce **gözle**, **(b)** ayrıca
> **programatik olarak** — destination `(default)` ise komut çalıştırılmaz.

Hedef ad deseni: `restore-drill-YYYYMMDD`.

### 5.2 Başarı otoritesi

| Kaynak | Otorite |
|---|---|
| Long-running operation: `done=true` **ve** hatasız **ve** `SUCCESSFUL` | **Tek başarı otoritesi budur.** |
| `databases describe` → `sourceInfo.progress=COMPLETED` | **Tek başına yeterli DEĞİLDİR.** |

**Gözlenen davranış:** veritabanı kaynağı `COMPLETED` gösterirken
long-running operation birkaç dakika daha `PROCESSING` kalabilir. İki API
yüzeyinin kısa süre ayrışması **normaldir**; karar **operation'a** göre verilir.

### 5.3 Polling ve süre

- Polling **foreground**, kontrollü ve **sınırlı (bounded)** aralıklarla
  yapılır. Arka plan görevi bırakılmaz.
- **Sabit bir 15 dakika sınırında operasyon başarısız SAYILMAZ.** İlk
  tatbikatta operation 15. dakikada hâlâ `30/100` idi ve **16 dakika
  56 saniyede** başarıyla tamamlandı.
- Operation uzarsa: **iptal etme, ikinci restore başlatma, veritabanını
  silme.** Operation kimliği kaydedilir ve izleme sonraki turda sürdürülür.
- **Aynı destination için ikinci bir restore başlatılmaz.**

### 5.4 Backup kapsamı — ne gelir, ne gelmez

| Öğe | Backup ile gelir mi? | İlk tatbikatta gözlem |
|---|---|---|
| Composite index configuration | **Evet** | Kaynak 3 ↔ hedef 3; normalize edilmiş tanımlar aynı |
| Security Rules | **Hayır** | Hedef veritabanı için rules release'i yok |
| TTL policies | **Hayır** | Kaynak 0 ↔ hedef 0 aktif politika |

> **Zayıf kanıt uyarısı.** Kaynakta **aktif TTL politikası yoksa**, hedefte
> de TTL bulunmaması zaten beklenen sonuçtur ve **tek başına güçlü bir
> restore kanıtı değildir.** TTL'in kapsam dışı olduğu, ancak kaynakta aktif
> bir politika varken anlamlı biçimde gözlemlenebilir.

Rules taşınmadığı için restore edilen veritabanı **kendi başına servis
edilebilir durumda değildir**; rules ayrıca deploy edilmelidir.

### 5.5 Temizleme — koşullu ve dar kapsamlı

Temizleme **yalnız tüm zorunlu kontroller PASS ise** yapılır. Herhangi bir
kontrol **FAIL, belirsiz veya doğrulanamaz** ise veritabanı **korunur** ve
silme yapılmaz.

**Gözlenen davranış:** restore edilen veritabanı **delete protection AÇIK**
olarak oluşur; silinmeden önce kapatılması gerekir.

1. Delete protection **yalnız drill veritabanı için** kapatılır; komuttaki
   `--database` değerinin drill kimliği olduğu önce doğrulanır.
2. **Kaynak `(default)` veritabanının delete protection'ına DOKUNULMAZ** ve
   kapatma sonrası hâlâ **açık** olduğu ayrıca doğrulanır.
3. Drill veritabanı silinir.

### 5.6 Doğrulama yöntemi — neyin kanıt sayıldığı

- **Production izolasyonu write-count metriğiyle kanıtlanmaz**; canlı trafik
  bu metriği zaten değiştirir. Kanıt **operation metadata** ve **audit
  log**'tur; audit kaydında **tam hedef kimliği** kontrol edilir.
- **Monitoring storage metriğinde görünmemek restore başarısızlığı değildir**
  (yanlış negatif olabilir) ve zorunlu kapı sayılmaz. Descriptor örnekleme
  periyodu 60 saniyedir, ancak gerçek seri **aralıklı** yayınlanır ve saatlerce
  boşluk olabilir; yedek boyutu adımları snapshot'tan 11–13 saat sonra
  görünebilir. Kısa ömürlü bir drill veritabanı bu boşluğa denk gelebilir.
- **HTTP 403 veya hata yanıtı boş liste sayılmaz.** Her API çağrısında HTTP
  durum kodu ve yapılandırılmış hata gövdesi **ayrıştırılır**. "Sonuç yok"
  ile "erişemedim" **farklı** sonuçlardır; bu ayrım yapılmazsa eksik bir
  kayıt yanlışlıkla "temiz" diye raporlanır.
- Kota projesi atfı hatalıysa **global CLI yapılandırması değiştirilmez**;
  istek başına kota atfı (`x-goog-user-project`) kullanılır.

### 5.7 Kanıt saklama ve veri minimizasyonu

Geçici veritabanı silinse bile **tatbikat kanıtı korunur**: operation sonucu,
PASS/FAIL matrisi ve audit referansı `docs/operations/` altında **sanitize**
biçimde saklanır.

Bu repo **public** kabul edilir. Kanıt belgelerine **UID, tam backup/operation
kimlikleri, quota project numarası, e-posta, ham audit log veya yerel dosya
yolu yazılmaz**; bu değerler repo dışında tutulur.

> **Kapsam dışı — 6C4.** Notification channel ve temel alarmlar kuruldu
> (6C2/6C3; bkz. §6), ancak **backup freshness checker hâlâ yoktur.** Şu anda
> başarısız bir programlı yedek **sessizce** kaybolabilir. Bu iş **6C4
> kapsamındadır** ve bu tatbikatla kapanmamıştır.

## 6. Monitoring hazırlığı — [CANLI]

**Durum: kısmen canlıda (6C2/6C3).** Ayrıntı ve filtre sözleşmesi:
`docs/MONITORING-PANOSU.md` §2–§4.

| Bileşen | Durum | Tür |
|---|---|---|
| E-posta notification channel | Kuruldu; teslimat gerçek bir test alarmıyla doğrulandı | [CANLI] ✅ |
| Log-based metric'ler | 9 adet, label'sız sayaç | [CANLI] ✅ |
| Alert policy'ler | 9 adet: 8'i e-posta kanalına bağlı; App Check gözlem alarmı (AL-09) bildirimsiz | [CANLI] ✅ |
| Projeye özel budget bildirimi | Kuruldu; harcamayı durdurmaz, OpenAI maliyetini kapsamaz | [CANLI] ✅ |
| Backup freshness checker (AL-10 / AL-11) | **Yok** | [CANLI] — 6C4 |
| App Check alarmının bildirime bağlanması | **Yok** | [CANLI] — 6E |
| Eşik ayarı | **Yok** — gerçek trafik baseline'ı gerekir | [KARAR] |

> **Release riski:** backup freshness checker kurulana kadar başarısız bir
> zamanlanmış yedek bildirim üretmez.

Canlı örneği olmayan olayların (CODE-CONTRACT-ONLY) alarmları güncel backend
deploy'undan önce pasif olarak kuruldu; ilk gerçek olayda veya kontrollü bir
doğrulamada VERIFIED seviyesine taşınmalıdır.

---

## 7. App Check — durum ve bağımlılıklar

| Aşama | Durum | Tür |
|---|---|---|
| SDK entegrasyonu (Flutter) | **Yapıldı** — `firebase_app_check`, Play Integrity / App Attest+DeviceCheck | [REPO] |
| Callable'larda `enforceAppCheck: true` | **Kodda mevcut** — `analyzeDecision`, `deleteAccount`, `createRewardTicket` | [REPO] |
| Production callable enforcement | **AKTİF** — `analyzeDecision` ve `deleteAccount` App Check'i zaten enforce ediyor; MISSING/INVALID token'lar HTTP 401 alıyor (6C1 canlı doğrulama) | [CANLI] ✅ |
| Provider kaydı (App Attest / Play Integrity) | **Yapılmadı / doğrulanmadı** | [CANLI] |
| Gerçek cihazda geçerli token kanıtı | **Yok** | [CANLI] |
| Firebase servis enforcement (Firestore vb.) | **Kapalı** (0 enforcement kaydı) | [CANLI] |

**İki farklı kontrol karıştırılmamalıdır:**

- Callable'daki `enforceAppCheck: true` **kodun bir parçasıdır** ve o kod
  deploy edildiği anda etkilidir. Firebase Console'daki enforcement
  ayarından **bağımsızdır**.
- Console'daki enforcement, Firestore gibi **diğer** servisleri kapsar.
- Console'daki servis enforcement kaydının **0 olması, callable kod
  seviyesindeki enforcement'ın kapalı olduğu anlamına gelmez**: production
  callable'ları bugün App Check'i zaten enforce ediyor.

### 7.1 Gerçek durum ve kalan release kapısı

> **Düzeltme (6C1 kanıtı).** Bu bölümün önceki sürümü, güncel Functions
> deploy'unun App Check enforcement'ını ilk kez açacağını ima ediyordu. Bu
> yanlıştır: production'daki `analyzeDecision` ve `deleteAccount` callable'ları
> **hâlihazırda** `enforceAppCheck: true` ile çalışıyor ve MISSING/INVALID
> token'lı istekleri HTTP 401 ile reddediyor.

Güncel backend deploy'u bu yüzden **enforcement'ı ilk kez açmaz**. Deploy yine
de kontrollü yapılır, çünkü:

- production'da olmayan callable'lar (ör. `createRewardTicket`) ilk kez ve
  enforcement ile yayına girer;
- AI izin kapısı sunucuda zorunlu hâle gelir; izin akışı olmayan istemci
  sürümlerinin analiz istekleri reddedilir;
- production'daki backend davranışı repodaki son sürüme geçer.

**Kalan release kapısı (6E):**

1. Provider kayıtlarının (App Attest / Play Integrity) doğrulanması.
2. İmzalı build ile **gerçek cihazdan** geçerli token alınması.
3. Play Integrity ve App Attest davranışının cihaz üzerinde gözlenmesi.
4. Yeni sürüm sonrası App Check **reddetme oranının** izlenmesi
   (`docs/MONITORING-PANOSU.md` §3.4, AL-09).

Bu kapılar kapanmadan gerçek kullanıcılara açılan bir istemci sürümünün
callable çağrıları enforcement nedeniyle reddedilebilir.

### 7.2 Karar ağacı

```
Provider kayıtları (App Attest + Play Integrity) tamam mı?
├── HAYIR ─► Play Integrity için imza parmak izi gerekiyor mu?
│            ├── EVET ─► Önce §11–§12: imzalı AAB'yi internal testing'e
│            │           yükle, Play App Signing parmak izini al,
│            │           Play Integrity'yi kaydet. Sonra buraya dön.
│            └── HAYIR ─► Provider'ları kaydet, buraya dön.
│
└── EVET ──► Gerçek cihazda "verified request" gözlemlendi mi?
             ├── HAYIR ─► §13 cihaz turunu ESKİ backend ile yap;
             │            App Check metriklerini gözle. Sonra buraya dön.
             │
             └── EVET ──► Güncel Functions deploy'u GÜVENLİ (§10).
                          Deploy sonrası Firestore enforcement AYRI bir
                          adımdır ve ayrıca gözlem ister.
```

**Bağımlılıklar:**
- App Attest → bundle ID + Team ID + **gerçek iPhone** (simulator token üretmez).
- Play Integrity → package name + **release imza parmak izi** (Play App
  Signing kullanılıyorsa parmak izi ancak ilk AAB yüklendikten sonra bilinir).

### 7.3 Deploy öncesi iki seçenek — bu dilimde SEÇİLMEDİ

- **A.** Provider kayıtları ve fiziksel cihaz token doğrulaması
  tamamlandıktan **sonra** güncel Functions deploy'u.
- **B.** Kontrollü bir geçiş sürümü tasarlamak.

> **B seçeneği, production'da zaten aktif olan App Check enforcement'ını
> geçici olarak gevşetmek anlamına gelir.** Açık kullanıcı kararı, ayrı kod
> incelemesi ve **ayrı bir PR** olmadan uygulanamaz.

---

## 8. Gerçek cihazda verified-token kanıtı — [CANLI]

App Attest ve Play Integrity **simulator/emulator'de çalışmaz**. Bu adım
fiziksel cihaz olmadan tamamlanamaz ve "başarılı" sayılamaz.

## 9. (yer tutucu — 6E kapsamı) Firestore enforcement

Functions deploy'undan **ayrı** bir adımdır; ayrı gözlem ve ayrı geri dönüş
yolu vardır (Console'dan kapatılır).

## 10. Backend / rules / indexes deploy — [CANLI]

**Ön koşul:** §7.2 karar ağacı "GÜVENLİ" dalına ulaşmış olmalı.

Sıra:
1. `firestore:indexes` — index oluşturma **zaman alır** ve anında geri
   alınamaz; önce gider.
2. `firestore:rules` — hızlı ve geri alınabilir.
3. `functions` — yalnız canlıda karşılığı olan fonksiyonlar.

Her komutta **hedef proje açıkça belirtilir** (`--project`), varsayılan
projeye güvenilmez.

## 11. İmzalı artifact — [CANLI]

- Android: `android/key.properties` gerekir; yoksa build **fail-closed**
  durur. Play App Signing varsayımı **[KARAR]** gerektirir.
- iOS: archive + export; provisioning profile gerekir.
- **Doğrulama:** AAB'nin birleştirilmiş manifestinde reklam izinlerinin
  bulunmadığı ve `PrivacyInfo.xcprivacy`'nin **imzalı Release** paketinde yer
  aldığı bu aşamada doğrulanır. (6A yalnız `--no-codesign` derlemesinde
  doğruladı; imzalı archive kanıtı **6F'ye açıktır**.)

## 12. Internal testing / TestFlight — [CANLI]

## 13. Fiziksel cihaz smoke matrisi — [CANLI]

Temiz kurulum · yükseltme · AI izni ver/reddet/geri al/eski sürüm ·
analiz üretimi · bağlantı kaybı → timeout → retry · aynı requestId ile
replay (kredi **bir kez**) · uygulamayı öldür → state restore · geri
navigasyonda flush · hesap+veri silme · bildirim izni ve 7 gün hatırlatması ·
App Check geçerli/geçersiz · gizlilik metni ↔ mağaza beyanı tutarlılığı.

## 14. Mağaza beyanları — [CANLI] + [KARAR]

`docs/store/APP-STORE-PRIVACY.md` ve
`docs/store/GOOGLE-PLAY-DATA-SAFETY.md` kaynak kanıttır; konsol formları
bunlardan doldurulur. Content rating / age rating / review notes
**[KARAR]** gerektirir.

## 15. Aşamalı yayın — [CANLI]

## 16. Post-release gözlem

En az bir tam gün: `docs/MONITORING-PANOSU.md` §2 alarmları, App Check
reddetme oranı (AL-09), Crashlytics crash-free oranı ve OpenAI maliyet
sayaçları (OpenAI maliyeti GCP budget'ına dahil değildir).

---

## 17. Rollback ve roll-forward

**Her katmanın geri dönüşü farklıdır. "Önceki revision'a dön" tek başına
yeterli bir talimat DEĞİLDİR.**

| Katman | Geri dönüş | Sınır |
|---|---|---|
| **Functions** | **Bilinen iyi Git commit'inden yeniden deploy.** Revizyon trafiğini geri almak Gen2'de mümkün olsa da tek doğru kaynak repodur. | Hedef proje ve bilinen iyi commit **doğrulanmadan** çalıştırılmaz. |
| **Firestore rules** | Bilinen iyi `firestore.rules` dosyasını yeniden deploy. | Hızlıdır; en güvenilir geri dönüş. |
| **Firestore indexes** | **Her zaman anında geri alınamaz.** Index oluşturma/silme asenkrondur. | İleri uyumlu index'leri önce ekleyin. |
| **App Check enforcement** | Console'dan kapatılır; etkisi hızlıdır. | Kod içi `enforceAppCheck` **bununla kapanmaz** — o bir deploy konusudur. |
| **Veri şeması / yazılmış veri** | **Kod rollback'i yetmez.** Yanlış yazılmış veri kodla geri gelmez. | Migrasyon/onarım işi gerekir. |
| **Mobil binary** | **Mağazalarda anlık DEĞİLDİR.** Play'de yayını durdurup önceki sürümü yeniden yayınlamak, App Store'da yeni bir sürüm göndermek gerekir; kullanıcıların güncellemesi zaman alır. | Bu yüzden istemci sözleşmesini kıran değişiklikler **önce** sunucuda geriye uyumlu hâle getirilir. |
| **Backup'tan restore** | **Uygulama rollback'i DEĞİLDİR.** Veriyi bir ana döndürür; o andan sonraki tüm kullanıcı yazımlarını kaybettirir. | Yalnız veri kaybı/bozulması senaryosunda. Restore **yeni bir veritabanı** oluşturur ve **rules taşımaz** (§5.4); trafiğin yeni veritabanına alınması ayrı bir iştir. |

### 17.1 Canlı komut kullanımı

Bu belgeye kopyala-yapıştır üretim komutu **yalnız** şu kapılarla konur:

1. Hedef proje **açık placeholder** ile yazılır (`--project <PROJE_ID>`);
   varsayılan projeye asla güvenilmez.
2. Bilinen iyi commit/artifact **önce doğrulanır** (`git log`, CI yeşili).
3. Komut çalıştırılmadan önce hangi kaynağı değiştirdiği yazılır.

## 18. Incident ownership — [KARAR]

Bildirim hedefi belirlendi: alarmlar proje sahibinin doğrulanmış e-posta
kanalına gider (6C2; adres bu belgede yayınlanmaz). **Tek sorumlu ve tek
kanal** vardır; ikinci kanal ve yedek sorumlu **public yayın öncesi** yeniden
değerlendirilecektir.

## 19. Release kapanışı ve kanıt arşivi

RC tag'i, CI koşu bağlantısı, imzalı artifact özetleri, cihaz matrisi
sonuçları, mağaza beyan ekran görüntüleri ve alarm durumu tek bir yerde
arşivlenir.

---

## 20. Bilinen sınırlar (dürüst kayıt)

- **Flutter SDK pini `.flutter-version` + git tag ile yapılır. Bir etiket
  yeniden işaretlenebilir; bu, tam commit değişmezliği DEĞİLDİR.** SDK
  checksum doğrulaması / iç mirror ayrı bir tedarik zinciri işidir ve
  6A kapsamında yapılmamıştır.
- `PrivacyInfo.xcprivacy`'nin **imzalı Release archive** içinde paketlendiği
  henüz doğrulanmadı (6A yalnız `--no-codesign` derlemesinde doğruladı).
- Fiziksel cihaz testi yapılmadı; App Attest/Play Integrity davranışı
  doğrulanmadı.
- Production backend güncel değildir.
- **Restore tatbikatı yalnız bir kez ve küçük veri hacminde yapıldı.**
  Ölçülen 16 dakika 56 saniye tek bir gözlemdir; süre veri hacmiyle büyür ve
  gelecekteki restore'lar için bir taahhüt değildir.
- **Yedeklerin gerçekten okunabilir uygulama verisi taşıdığı belge düzeyinde
  doğrulanmadı.** Tatbikat, veri minimizasyonu gereği **yapısal** düzeyde
  (operation durumu, metadata, index/TTL/rules kapsamı, izolasyon)
  doğrulanmıştır; kullanıcı belgesi **okunmamıştır**.
- **Backup freshness checker yoktur** (6C4). Notification channel ve temel
  alarmlar kuruldu (6C2/6C3), ancak başarısız bir programlı yedek şu anda
  sessizce kaybolabilir.
- **CODE-CONTRACT-ONLY alarmlar** henüz canlı bir olayla doğrulanmadı; ilk
  gerçek olayda veya kontrollü bir doğrulamada teyit edilmelidir.
- Production callable'ları App Check'i zaten enforce ediyor; provider ve
  gerçek cihaz doğrulaması (6E) tamamlanmadığı için gerçek cihaz istemcileri
  reddedilebilir.
- **Auth kullanıcı verisi ve imzalama materyali (signing key, provisioning
  profile) bu yedekleme kapsamında DEĞİLDİR.** Firestore restore'u bu iki
  kaybı telafi etmez; ayrı bir felaket kurtarma işidir.
