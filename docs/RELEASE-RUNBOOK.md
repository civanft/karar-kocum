# Release Runbook

| | |
|---|---|
| **Sürüm** | v1.0 — 9 Eylül 2026 (İş Paketi 6A) |
| **Kapsam** | Yayın adayı üretimi, canlı işlemlerin güvenli sırası, rollback sınırları |
| **Durum** | Bu belge bir **plandır**. Aşağıdaki hiçbir canlı adım henüz uygulanmadı. |

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

**Mevcut durum (2026-09-09 itibarıyla, salt okunur doğrulandı):**
production Firestore'da **PITR kapalı**, **yedekleme programı yok**,
**hiç yedek yok**. Delete protection açık.

Yayın öncesi karar verilmesi gerekenler:

- **RPO** (kabul edilebilir veri kaybı penceresi) — değer **belirlenmedi**.
- **RTO** (kabul edilebilir geri dönüş süresi) — değer **belirlenmedi**.
- PITR açılacak mı? (ek depolama ücreti)
- Managed backup programı ve retention? (ücret)

Kaynaklar (yalnız ad; bu dilimde yetki verilmedi):
`roles/datastore.importExportAdmin`, `roles/storage.admin`,
`roles/firebase.admin`. Export bucket'ı Firestore ile **aynı bölgede**
(`eur3`) olmalıdır.

## 5. Restore tatbikatı — [CANLI] + ÜCRET

Restore **üretime prova edilemez**: `import` mevcut koleksiyonların üzerine
yazar. Tatbikat **ayrı bir hedef veritabanında veya ayrı bir projede**
yapılır. Tatbikat tamamlanmadan §4'teki RPO/RTO değerleri "doğrulanmış"
sayılmaz.

## 6. Monitoring hazırlığı — [CANLI]

`docs/MONITORING-PANOSU.md` §3'teki A1–A9. **Sıralama uyarısı:** filtreler
canlı bir log satırıyla doğrulanmalıdır ve bu, güncel backend deploy
edildikten **sonra** mümkündür (§10). Notification channel ve incident owner
**[KARAR]** gerektirir.

---

## 7. App Check — durum ve bağımlılıklar

| Aşama | Durum | Tür |
|---|---|---|
| SDK entegrasyonu (Flutter) | **Yapıldı** — `firebase_app_check`, Play Integrity / App Attest+DeviceCheck | [REPO] |
| Callable'larda `enforceAppCheck: true` | **Kodda mevcut** — `analyzeDecision`, `deleteAccount`, `createRewardTicket` | [REPO] |
| Provider kaydı (App Attest / Play Integrity) | **Yapılmadı / doğrulanmadı** | [CANLI] |
| Gerçek cihazda geçerli token kanıtı | **Yok** | [CANLI] |
| Firebase servis enforcement (Firestore vb.) | **Kapalı** (0 enforcement kaydı) | [CANLI] |

**İki farklı kontrol karıştırılmamalıdır:**

- Callable'daki `enforceAppCheck: true` **kodun bir parçasıdır** ve o kod
  deploy edildiği anda etkilidir. Firebase Console'daki enforcement
  ayarından **bağımsızdır**.
- Console'daki enforcement, Firestore gibi **diğer** servisleri kapsar.

### 7.1 KRİTİK SIRALAMA

> **"Önce güncel Functions'ı deploy et, sonra App Check'i devreye al"
> sırası GÜVENLİ DEĞİLDİR.**
>
> Güncel callable tanımları `enforceAppCheck: true` içerir.
> Bu kod production'a gittiği anda Functions seviyesindeki zorlama
> **deploy anında aktif olur** — Console'daki enforcement anahtarına
> bakılmaksızın. Provider kaydı yapılmamış veya gerçek cihazdan geçerli
> token alındığı doğrulanmamışsa, deploy **tüm istemci çağrılarını
> kesebilir**.

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

> **B seçeneği güvenlik sözleşmesini geçici olarak gevşetebilir.** Açık
> kullanıcı kararı, ayrı kod incelemesi ve **ayrı bir PR** olmadan
> uygulanamaz.

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

En az bir tam gün: §3 alarmları, Crashlytics crash-free oranı, OpenAI
maliyet sayaçları.

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
| **Backup'tan restore** | **Uygulama rollback'i DEĞİLDİR.** Veriyi bir ana döndürür; o andan sonraki tüm kullanıcı yazımlarını kaybettirir. | Yalnız veri kaybı/bozulması senaryosunda, §4–§5 kararları alınmışsa. |

### 17.1 Canlı komut kullanımı

Bu belgeye kopyala-yapıştır üretim komutu **yalnız** şu kapılarla konur:

1. Hedef proje **açık placeholder** ile yazılır (`--project <PROJE_ID>`);
   varsayılan projeye asla güvenilmez.
2. Bilinen iyi commit/artifact **önce doğrulanır** (`git log`, CI yeşili).
3. Komut çalıştırılmadan önce hangi kaynağı değiştirdiği yazılır.

## 18. Incident ownership — [KARAR]

Incident owner **belirlenmedi**. Belirlenene kadar §6'daki notification
channel kurulamaz ve alarmların gideceği bir yer yoktur.

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
