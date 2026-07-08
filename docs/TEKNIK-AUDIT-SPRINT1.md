# Teknik Audit Raporu — Sprint 1 Kod Tabanı

| | |
|---|---|
| **Denetim tarihi** | 8 Temmuz 2026 |
| **Denetlenen sürüm** | `ca247d7` (main) |
| **Kapsam** | lib/, test/, functions/, firestore.rules, CI |
| **Genel değerlendirme** | 🟢 Temel sağlam — 2 kritik, 5 yüksek, 6 orta, 4 düşük bulgu |
| **Güncelleme (2026-07-08)** | ✅ K-1 kapatıldı (`270c720`) · ✅ K-2 istemci ayağı kapatıldı + O-3 birlikte çözüldü; K-2'nin sunucu ayağı (alan bazlı yazım + serverTimestamp) Firestore repo PR'ının ön koşulu olarak açık |

Risk ölçeği: **KRİTİK** = ilk push/Sprint 2'de kesin sorun · **YÜKSEK** = üretimde veri kaybı/maliyet riski · **ORTA** = büyüyen teknik borç · **DÜŞÜK** = iyileştirme fırsatı

---

## KRİTİK

### K-1 · CI'ın functions ayağı ilk push'ta kırılacak
**Kategori:** CI/CD · **Dosya:** `.github/workflows/ci.yaml`, `functions/`

`functions/src/index.ts` var olmayan modülleri import ediyor (`./ai/analyze.js` vb. — klasörler boş), `package-lock.json` yok (`npm ci` lockfile'sız çalışmaz), eslint config yok (`npm run lint` patlar), test dosyası yok (`vitest run` sıfır test ile hata döner).

- **Etki:** GitHub'a push edilen ilk PR'da pipeline kırmızı; ekip "CI zaten bozuk" alışkanlığı edinir — kalite kapılarının otoritesi ilk günden ölür.
- **Çözüm:** (a) Kısa vade: functions job'ına `if: false` veya path filtresi (`paths: ['functions/**']`) koy + index.ts'teki ölü importları yorumla. (b) Sprint 2 başında: `npm install` ile lockfile üret, eslint flat config ekle, her modül için en az derlenen stub + 1 test yaz. Önerim (a)'yı hemen yapmak.

### K-2 · Editor "read-modify-write" deseni Firestore'da veri kaybettirir
**Kategori:** State management / Firestore hazırlığı · **Dosya:** `decision_editor.dart`

`_mutate` tüm `Decision`'ı okuyup değiştirip **belgenin tamamını** yazıyor ve `build()` repo'dan **tek seferlik** okuma yapıyor (`getById`), akış izlemiyor. İki cihaz (veya Sprint 3'te AI'ın `aiAnalysis` yazan Functions'ı) aynı kararı değiştirdiğinde: cihaz A eski kopyasının üstüne tüm belgeyi yazar → B'nin (veya sunucunun) değişikliği **sessizce silinir**.

- **Etki:** Sprint 4 senkronunda kesin veri kaybı; Sprint 3'te AI analizinin istemci autosave'i tarafından ezilmesi. Kullanıcı "kararım kayboldu" der — ürünün güven vaadi için ölümcül.
- **Çözüm:** Sprint 2'de Firestore repo'ya geçerken birlikte yapılmalı: (1) `DecisionRepository`'ye `watchById(id)` ekle, editor `build()` içinde stream'i `ref.watch`/`listen` ile izlesin; (2) yazımları alan bazlı yap (`update({'options': ...})`) veya en azından `aiAnalysis`/`result` alanlarını istemci yazımından ayır; (3) `updatedAt` karşılaştırmalı iyimser kilit değerlendir. Bu, Sprint 2 tanımına açık madde olarak eklenmeli.

---

## YÜKSEK

### Y-1 · `_mutate` hata yutuyor: state ile depo sessizce ayrışabilir
**Dosya:** `decision_editor.dart`

`state = AsyncData(updated)` önce set ediliyor, sonra `await repo.upsert(...)` — upsert fırlatırsa (Firestore: izin/kota/offline sınırı) hata yakalanmıyor: UI güncel görünür, kalıcı katman eski kalır; kullanıcı veri kaybını ancak app restart'ta fark eder.

- **Etki:** Sessiz veri kaybı; hata ayıklanması çok zor "arada kayboldu" şikâyetleri.
- **Çözüm:** `_mutate`'e try/catch: başarısızlıkta önceki state'e geri al + `Failure`'ı UI'a taşı (snackbar "kaydedilemedi — tekrar dene"). Testi: fake repo'ya fırlatan `upsert` enjekte et.

### Y-2 · Slider `onChanged` → mutasyon başına tam belge yazımı
**Dosya:** `scores_tab.dart`, `criteria_tab.dart`

Her slider pikselinde `setScore`/`setCriterionWeight` → `_mutate` → `upsert`. In-memory'de bedava; Firestore'da tek sürüklemede 30-60 belge yazımı.

- **Etki:** Firestore maliyeti (yazım başına ücret) + gecikme + K-2 ile birleşince çakışma penceresini büyütür. 1K aktif kullanıcıda anlamlı fatura.
- **Çözüm:** İki katman: (1) UI'da `onChangeEnd` ile yalnız bırakınca yaz (görsel güncelleme `onChanged`'da yerel kalsın); (2) repo önünde 800 ms debounce (mimaride zaten kararlaştırıldı — Sprint 2 DoD'sine ölçülebilir madde olarak girsin: "tek slider sürüklemesi ≤ 1 yazım").

### Y-3 · Seçenek adı, açıklama ve kriter adında uzunluk sınırı yok
**Dosya:** `decision_validator.dart`, `firestore.rules`

`optionTitle` yalnız boşluk kontrolü yapıyor; `description` ve kriter adı hiç doğrulanmıyor. Artı/eksi madde **sayısı** da sınırsız (madde başı 140 karakter var ama 10.000 madde eklenebilir).

- **Etki:** Tek kayıtla 1 MB Firestore belge limitine dayanma → yazım hatası; kötü niyetli kullanım için ucuz vektör; AI prompt'una girecek metnin token maliyeti kontrolsüz.
- **Çözüm:** `Limits`'e ekle: `optionTitleMax=60`, `descriptionMax=280`, `criterionNameMax=40`, `maxProsConsPerOption=20`; validator + UI `maxLength` + Firestore rules üç katmanda zorla (CONTRIBUTING'deki "limit üç katmanda senkron" kuralı zaten bunu emrediyor).

### Y-4 · `DateTime` serileştirmesi ve istemci saati Firestore ile uyumsuz
**Dosya:** `decision.dart`, `decision_editor.dart`, `create_decision.dart`

`createdAt/updatedAt` json_serializable ile ISO-8601 string'e gidiyor ve değerler `DateTime.now()` ile istemci saatinden üretiliyor.

- **Etki:** (1) Firestore'da string tarih = `Timestamp` sorgu/indeks avantajı yok; (2) saati bozuk cihazda liste sıralaması ve "en yeni üstte" garantisi çöker; (3) K-2'deki iyimser kilit fikri istemci saatine güvenemez.
- **Çözüm:** Sprint 2'de `TimestampConverter` (JsonConverter) ekle; Firestore yazımlarında `updatedAt` için `FieldValue.serverTimestamp()`. Ayrıca `Clock` soyutlaması enjekte et (T-1 ile birleşir).

### Y-5 · Rules: `ownerUid` alanı doğrulanmıyor
**Dosya:** `firestore.rules`

Belge yolu (`users/{uid}/decisions`) sahipliği garanti ediyor ama belge **içindeki** `ownerUid` alanının `uid` ile eşleştiği kontrol edilmiyor. İstemci `ownerUid: 'baskasi'` yazabilir.

- **Etki:** Bugün zararsız (yol otoriter) ama Sprint 4'te `mergeAccounts` / collectionGroup sorguları `ownerUid` alanına güvenirse sessiz yetki karmaşası doğar — bu tür alan/yol tutarsızlıkları klasik güvenlik regresyon kaynağıdır.
- **Çözüm:** Rules'a tek satır: `&& request.resource.data.ownerUid == uid`. Rules birim testine negatif senaryo ekle (Sprint 2'de rules testleri zaten planlı).

---

## ORTA

### O-1 · Domain invariant'ları presentation katmanında yaşıyor
**Dosya:** `decision_editor.dart`

Kaskad silme (seçenek silinince puanları düşür), 10 seçenek sınırı, puan aralığı gibi iş kuralları Notifier metodlarında. AI otomatik puanlama (Sprint 3) veya import/şablon akışı (Sprint 2) karara **başka yoldan** yazdığında bu kurallar uygulanmaz.

- **Etki:** Çok girişli mutasyonda tutarsız veri; kuralların iki yerde kopyalanması.
- **Çözüm:** Mutasyonları `Decision` üzerinde saf domain fonksiyonlarına çıkar (`decision.addOption(...)` → `Result<Decision>` döner, entity dosyasında ya da `decision_mutations.dart`); Notifier yalnız çağırıp kaydetsin. Test yükü domain'e iner (daha hızlı, widget'sız). Sprint 2'de Firestore geçişiyle birlikte yapmak en ucuz an.

### O-2 · Validator kullanıcı metni döndürüyor — l10n domain'e sızmış
**Dosya:** `decision_validator.dart`, `failure.dart`

`ValidationFailure.message` Türkçe cümle taşıyor ve doğrudan UI'da gösteriliyor. Sprint 6'da EN eklenince domain katmanı locale bilmek zorunda kalacak.

- **Etki:** l10n geçişinde domain+test toplu değişikliği; domain'in "saf" iddiası zayıflar.
- **Çözüm:** `ValidationFailure`'a `code` alanı (enum: `titleTooShort`, `tooManyOptions`…); mesaj eşlemesi presentation'da tek harita. Şimdi ucuz, Sprint 6'da pahalı.

### O-3 · `watchAll()` ilk emisyonunda yarış penceresi
**Dosya:** `in_memory_decision_repository.dart`

`async*` gövdesi önce `yield _snapshot` yapıp sonra broadcast stream'e abone oluyor; bu iki adım arasındaki mikro-görevde gerçekleşen mutasyon **kaybolur** — dinleyici bir sonraki değişikliğe kadar bayat liste görür.

- **Etki:** Bugün: "karar oluşturdum, listede yok" tarzı nadir, üretilemeyen UI tutarsızlığı. Firestore repo'da SDK bunu çözer ama bu sınıf **testlerde fake olarak yaşayacak** — testlerde flakiness kaynağı olur.
- **Çözüm:** Abonelik-önce deseni: `StreamController.onListen` içinde snapshot emit et ya da son değeri tutan basit bir BehaviorSubject eşleniği yaz.

### O-4 · İki ayrı hata sözleşmesi: `Result<T>` vs `ValidationFailure?`
**Dosya:** `create_decision.dart` vs `decision_editor.dart`

Use case `Result<Decision>` dönerken editor mutasyonları `Future<ValidationFailure?>` dönüyor; ayrıca `Failure.when` benzeri tüketim yalnız Result'ta var.

- **Etki:** Her yeni özellikte "hangi deseni kullanayım?" kararsızlığı; hata işleme kodu iki stilde çoğalır.
- **Çözüm:** Tek sözleşme seç (önerim: hepsi `Result<T>`); O-1'deki domain fonksiyonu çıkarma işiyle aynı PR'da hizala.

### O-5 · `ResultScreen` başka feature'ın presentation'ına bağımlı
**Dosya:** `results/presentation/screens/result_screen.dart`

`decision/presentation/providers` import ediliyor — feature'lar arası bağımlılık en oynak katman (presentation) üzerinden kurulmuş. `check_layers.sh` bunu yakalamıyor (yalnız katman yönünü denetliyor, feature-arası presentation bağımlılığını değil).

- **Etki:** decision provider'larında her refactor results'ı kırar; feature'ların bağımsız test edilebilirliği azalır.
- **Çözüm:** Kuralı netleştir: feature-arası erişim yalnız **domain** üzerinden (results, `DecisionRepository`+`ComputeResult` ile kendi provider'ını kurar) — ve `check_layers.sh`'e "başka feature'ın /presentation/ yolundan import yasak" deseni ekle.

### O-6 · Editor `build()` hatası ham `StateError` olarak UI'a sızıyor
**Dosya:** `decision_editor.dart`, `decision_edit_screen.dart`, `result_screen.dart`

Bulunamayan karar `StateError('Karar bulunamadı: d1')` fırlatıyor; ekranlar `Text('Yüklenemedi: $e')` ile ham hata basıyor; retry yok.

- **Etki:** Derin bağlantı/senkron gecikmesi durumlarında kullanıcıya İngilizce-teknik metin; Crashlytics'te sınıflandırılamayan hatalar.
- **Çözüm:** `Failure.notFound` türü ekle; ekranlarda `AsyncValueWidget` sarmalayıcısı (mimaride zaten planlı) ile standart hata+retry UI.

---

## DÜŞÜK

### D-1 · `DateTime.now()` ve eşik sabitleri test edilebilirliği kısıtlıyor
`CreateDecision`/`_mutate` gerçek saat kullanıyor (testler `isAfter` ile gerçek zamana bağımlı — yavaş CI'da kırılganlık); `ScoringEngine._confidence` içindeki 15/5/3 eşikleri gömülü sabit (ürün ayarı gerektirecek). **Çözüm:** `Clock` enjeksiyonu; eşikleri `ScoringThresholds` sabitine çıkar.

### D-2 · Build içinde `ref.read` kullanımı
`ResultScreen` (`ref.read(computeResultProvider)(decision)`) ve sekmelerde (`ref.read(...notifier)`) build sırasında `read` var. Bugün zararsız (değerler sabit) ama Riverpod'un belgelenmiş anti-pattern'i; provider yeniden oluşursa bayat referans riski. **Çözüm:** Sonucu `Provider.family` türevine taşı; notifier'ları callback içinde `read` et.

### D-3 · `check_layers.sh` `dart:ui`/`dart:io` kaçağını yakalamıyor
Domain'e `package:flutter` importu yasak ama `dart:ui` grep deseninde yok. **Çözüm:** Desene `dart:ui|dart:io` ekle (5 dakikalık iş).

### D-4 · Puan slider'ının "5'te duran ama boş" durumu
Dokunulmamış hücre slider'ı 5'te gösteriyor; kullanıcı tam 5 vermek isterse slider'ı oynatıp geri getirmek zorunda — ayrıca "zaten 5'te duruyor" diye dokunmayan kullanıcı kapıda takılır ve nedenini anlamayabilir. **Çözüm:** Dokunulmamış hücreyi görsel olarak da farklılaştır (soluk track + "puanla" chip'i) veya "5 olarak onayla" dokunuşu ekle. Sprint 3 UX turuna not.

---

## Kategori bazında özet değerlendirme

| Denetim alanı | Durum | Not |
|---|---|---|
| Clean Architecture | 🟡 | Yön kuralları sağlam ve denetimli; invariant yerleşimi (O-1) ve feature-arası bağ (O-5) düzeltilmeli |
| Katman bağımlılıkları | 🟢 | domain saf Dart doğrulandı; script kör noktası D-3 |
| State management | 🟡 | Desen doğru (AsyncNotifier + tek yönlü akış); K-2 ve Y-1 Firestore öncesi şart |
| Riverpod kullanımı | 🟢 | Override edilebilir grafik, autoDispose disiplini iyi; D-2 kozmetik |
| Performans | 🟢 | Yerel hesap <1 ms, const disiplini var; Y-2 tek gerçek risk (maliyet) |
| Test edilebilirlik | 🟡 | 35 test, %81,9; widget testi yok, Clock yok (D-1), fake repo yarışı (O-3) |
| Güvenlik | 🟢 | İstemcide sır yok, rules mantığı doğru yönde; Y-5 + Y-3 kapatılmalı |
| Firestore hazırlığı | 🔴 | K-2 + Y-4 çözülmeden Firestore repo yazılMAmalı — geçiş planının ön koşulu |

## Önceliklendirilmiş aksiyon planı

**Push'tan önce (bugün, ~1 saat):** K-1 (functions job'ını kapat/filtrele) · D-3 (script deseni)
**Sprint 2'nin ilk PR'ları (Firestore repo'dan ÖNCE):** K-2 (watchById + alan bazlı yazım tasarımı) · Y-1 (mutasyon hata yolu) · Y-3 (limitler, üç katman) · Y-4 (Timestamp/Clock) · O-1+O-4 (domain mutasyonları, tek hata sözleşmesi — Firestore geçişiyle aynı refactor penceresi)
**Sprint 2 içinde:** Y-2 (debounce+onChangeEnd) · Y-5 (rules satırı+testi) · O-3 (fake repo düzeltmesi) · O-6 (AsyncValueWidget)
**Sprint 3+ / fırsat buldukça:** O-2, O-5, D-1, D-2, D-4
