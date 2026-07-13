# Sprint A — Teknik Tasarım: Aktivasyon UX Paketi

> Rol: Senior Product Designer + Flutter Architect
> Durum: Tasarım (kod yok)
> İlgili dokümanlar: PRD.md §6.1, TEKNIK-MIMARI.md §6, SPRINT-PLAN.md

## 0. Kapsam ve Kısıtlar

Davranışsal UX denetiminin bulduğu üç kritik problem ve Sprint A yanıtları:

| # | Problem | Özellik | Aktivasyon hunisindeki hedef |
|---|---------|---------|------------------------------|
| P1 | İlk açılışta değer gösterilmiyor | **A1 — Hazır Şablon Kararlar** | `decision_created` oranını artır |
| P2 | Kriter üretmek zor | **A2 — Kriter Öneri Sistemi** | `criteria_completed` oranını artır |
| P3 | Puan matrisi çok yorucu | **A3 — Puanlama İlerleme Göstergesi** | `scoring_completed` oranını artır |

**Değişmezler (tasarımın uyduğu kurallar):**

1. **Firestore şeması değişmez.** Üç özellik de mevcut `Decision` belgesinin
   alanlarıyla çalışır: şablonlar `templateId` (zaten var) + normal
   `criteria`/`options` yazımı; öneriler `CriterionSource.aiSuggested`
   (zaten var); ilerleme tamamen türetilmiş durumdur, hiçbir şey persist edilmez.
2. **Domain katmanı korunur.** Yeni iş kuralları saf Dart olarak domain'e girer
   (öneri motoru, ilerleme getter'ları); Flutter/Firebase importu yok.
3. **Riverpod yapısı korunur.** Mevcut stil sürdürülür: codegen'siz
   `Provider` / `StateProvider` / `AsyncNotifierProvider.autoDispose.family`;
   tüm mutasyonlar `DecisionEditor` üzerinden akar.
4. **Mevcut mimari bozulmaz.** Feature-first klasörleme
   (`features/<x>/domain|data|presentation`), arayüz → implementasyon bağlama
   `*_providers.dart` içinde, iyimser mutasyon + `DecisionPatch` yolu aynen kalır.

**Sprint A'ya girmeyenler (bilinçli):** AI destekli kriter önerisi (callable
maliyeti; A2'nin arayüzü buna hazır bırakılır), şablonların Firestore'dan
uzaktan yönetimi (Remote Config/koleksiyon — Sprint B+ adayı), puan matrisinin
kart-kart "wizard" moduna dönüştürülmesi (A3 ölçümü sonrası değerlendirilecek).

---

## 1. UX Akışları

### 1.1 A1 — Hazır Şablon Kararlar

**Bugünkü durum:** `HomeScreen._EmptyState` yalnız başlık önerisi taşıyan 4
buton gösterir; tıklayınca `NewDecisionScreen`'e sadece `title` gider. Kullanıcı
boş bir editöre düşer → P1.

**Hedef durum:** Şablon = başlık kalıbı + hazır kriter seti (ağırlıklarıyla)
+ isteğe bağlı örnek seçenekler. Tek dokunuşla "yarı dolu" bir karar açılır;
kullanıcı ilk 10 saniyede ürünün ne yaptığını dolu ekranda görür.

**Akış A1-a: İlk açılış (boş liste)**

```
Home (boş durum)
 │  4 şablon kartı (emoji + başlık + "5 hazır kriter" rozeti) + "Tüm şablonlar →"
 ├─ şablon kartına dokun
 │   └─ Şablon Önizleme (modal bottom sheet)
 │       • başlık, açıklama
 │       • kriter listesi: ad + önem (salt okunur)
 │       • varsa örnek seçenekler
 │       • [Bu şablonla başla]  [Boş başla]
 │           ├─ "Bu şablonla başla" → karar OLUŞTURULUR (başlık düzenlenebilir
 │           │    olarak sheet üstünde sorulur, şablon başlığı ön dolu)
 │           │    → /decision/:id/edit  (Seçenekler sekmesi açık,
 │           │       Kriterler sekmesi zaten dolu)
 │           └─ "Boş başla" → /decision/new?title=<şablon başlığı> (mevcut akış)
 └─ "Tüm şablonlar" → /templates (galeri: kategori başlıklı liste)
```

**Akış A1-b: Dönen kullanıcı (liste dolu)**

```
Home (dolu) ── FAB "Yeni Karar" → /decision/new
NewDecisionScreen
 • başlık alanı (mevcut)
 • YENİ: alanın altında yatay şablon şeridi ("Ya da bir şablonla başla")
 • şerit kartına dokun → aynı Şablon Önizleme sheet'i
```

**Kritik UX kararları:**

- Önizleme sheet'i **taahhütten önce içerik gösterir** — kullanıcı ne
  alacağını görmeden karar yaratılmaz (yanlışlıkla çöp taslak üretimini ve
  `maxDecisionsPerUser=50` kotasının israfını önler).
- Şablonla oluşturulan karar editörde **Seçenekler** sekmesiyle açılır:
  kriterler hazır olduğundan kullanıcının tek işi seçenek girmek; "sonraki
  boş iş" ilkesi.
- Şablon uygulandıktan sonra kriterler normal kriterdir: silinebilir,
  ağırlığı değiştirilebilir. Şablona geri bağ yok (yalnız `templateId` izi).
- Katalog **uygulama içi sabittir** (Dart const). Gerekçe: Firestore şeması
  değişmeyecek, çevrimdışı ilk açılışta da (in-memory repo modunda) çalışmalı,
  içerik sürümü uygulama sürümüyle taşınır. v1 katalog: 6 şablon —
  Telefon Alımı 📱, İş Teklifi 💼, Bölüm/Okul Seçimi 🎓, Şehir/Taşınma 🏙️,
  Araba Alımı 🚗, Tatil Planı ✈️. Her biri 4–6 kriter, ağırlıklar 1-10.

**Analytics:** mevcut `logDecisionCreated(source:)` `blank|template` ayrımını
zaten yapıyor. Yeni olay: `template_selected {template_id}` (önizleme
sheet'inde CTA anı). `template_id` katalog enum kimliğidir, içerik/PII değildir
— TEKNIK-MIMARI.md §9.1 şema dokümanına eklenmeden kodlanmaz (mevcut kural).

### 1.2 A2 — Kriter Öneri Sistemi

**Bugünkü durum:** `CriteriaTab` boş liste + "İlk kriteri ekle" düğmesi;
kullanıcı sıfırdan kriter adı icat etmek zorunda → P2.

**Hedef durum:** Editör, karar bağlamından türetilmiş **öneri chip'leri**
gösterir; tek dokunuş kriteri varsayılan ağırlıkla ekler.

**Öneri kaynağı (yerel, deterministik, sıralı):**

1. `decision.templateId` doluysa → o şablonun henüz eklenmemiş kriterleri
   (şablonla başlayıp kriter silen / boş başlayıp sonra gelenler için).
2. Başlık **anahtar kelime eşleşmesi** → yerel Türkçe sözlük
   (ör. "telefon|iphone|samsung" → Fiyat, Kamera, Batarya, Ekosistem;
   "iş|teklif|maaş" → Maaş, Kariyer Gelişimi, İş-Yaşam Dengesi, Uzaktan Çalışma…).
3. Genel dolgu seti: Maliyet, Kalite, Risk, Zaman, Mutluluk.

Kurallar: mevcut kriterlerle **ad bazlı, harf-duyarsız (tr locale)** çakışanlar
elenir; en fazla **6 chip**; kaynak sırası korunur (şablon > başlık > genel).
AI çağrısı yok — motor saf fonksiyondur; gelecekte AI destekli öneri aynı
arayüzün ikinci implementasyonu olarak takılır (bkz. §3, `CriterionSuggester`).

**Akış:**

```
CriteriaTab
 ┌────────────────────────────────────────────┐
 │ Önerilen kriterler                    (kapat ✕) │
 │ [+ Fiyat] [+ Kamera] [+ Batarya] [+ Ekosistem]  │
 └────────────────────────────────────────────┘
 │
 ├─ chip'e dokun
 │   → addCriterion(ad, ağırlık=5, source: aiSuggested)
 │   → chip listeden düşer (artık "mevcut"), kart listesine kriter eklenir
 │   → kullanıcı ağırlığı mevcut slider'la ayarlar
 ├─ ✕ → şerit bu ekran ömrü boyunca gizlenir (persist edilmez; ephemeral
 │       StateProvider — dogmatik kalıcılık yerine ucuz geri dönüş)
 └─ "Kriter ekle" (mevcut dialog) aynen kalır — öneriler onu İKAME ETMEZ
```

**Kritik UX kararları:**

- Chip'le eklenen kriter `CriterionSource.aiSuggested` etiketlenir → mevcut
  `logCriteriaCompleted(aiSuggestedCount:)` hunisi hiç değişmeden A2'nin
  etkisini ölçer. (Enum adı "ai" dese de anlamı "sistem önerdi"dir; şema
  değişmediği için yeniden adlandırılmaz, doküman notu düşülür.)
- Öneri şeridi kriter listesi **boşken en görünür** (birincil eylem gibi),
  kriter varken listenin üstünde kompakt kalır; 6+ kriterde tamamen gizlenir
  (öneri değeri düşer, gürültü olur).
- Varsayılan ağırlık 5: kullanıcıya "önce ekle, sonra ayarla" akışı;
  dialog akışındaki ağırlık seçme sürtünmesi chip yolunda sıfırlanır.

**Analytics (yeni):** `criterion_suggestion_accepted {origin: template|keyword|generic}` —
yalnız enum, içerik yok.

### 1.3 A3 — Puanlama İlerleme Göstergesi

**Bugünkü durum:** `ScoresTab` tüm seçenek×kriter slider'larını tek listede
döker; kaç hücre kaldığı görünmez, "Sonucu Gör" düğmesinin neden pasif olduğu
belirsiz ("—" işaretlerini saymak gerekir) → P3.

**Hedef durum:** İlerlemeyi üç seviyede görünür kıl; sıradaki işi işaret et.
Hiçbir veri persist edilmez — hepsi `decision.scores`'tan türetilir.

```
ScoresTab
 ┌──────────────────────────────────────────────┐
 │ Puanlama: 12/20        ▓▓▓▓▓▓▓░░░░░  (sticky) │  ← genel ilerleme başlığı
 └──────────────────────────────────────────────┘
 │
 ├─ Seçenek kartı başlığı: "iPhone 15   [3/5 ✓✓✓○○]" ← seçenek bazlı sayaç
 │    · tamamlanan kart başlığında ✓ dolu renk (primary)
 ├─ boş hücre satırı: değer sütununda "—" (mevcut) + slider track soluk
 └─ hepsi dolunca başlık "Puanlama tamam 🎉 20/20" + progress bar dolu

DecisionEditScreen (alt bar)
 ├─ engel varsa (mevcut blockers metni) → puanlama engeli için metin
 │    "Puanlama: 12/20 — 8 hücre kaldı" biçimine zenginleşir
 └─ "Puanlar" sekme etiketi: "Puanlar" yanında küçük kalan-sayısı rozeti (8)
```

**Kritik UX kararları:**

- İlerleme başlığı **sticky**: uzun listede scroll ederken hedef hep görünür
  (Zeigarnik etkisi — tamamlanmamış işin görünürlüğü tamamlama motivasyonudur).
- Seçenek bazlı sayaç, kullanıcıya doğal "chunk"lama verir: matris 20 hücre
  değil "4 seçenek × 5'lik küçük işler" olarak algılanır — P3'ün asıl yorucu
  algısına saldıran budur.
- "Sonucu Gör" pasifken alt bar artık **niceliksel** sebep söyler; kullanıcı
  bitişin ne kadar yakın olduğunu bilir.
- İlk dokunuşta 5'ten başlama davranışı (mevcut) korunur; hücre "dolu"
  sayılmak için dokunuş şartı aynen sürer (`scores[o][c] == null` tanımı).

**Analytics:** yeni olay yok — `scoring_completed` zaten eşik geçişinde
atılıyor; A3'ün etkisi bu oranın hareketinden okunur.

---

## 2. Widget Ağaçları

### 2.1 A1 — Şablonlar

```
HomeScreen (mevcut)
└─ _EmptyState                                    [DEĞİŞİR]
   ├─ başlık + alt metin (mevcut)
   ├─ TemplateCardStrip (dikey, ilk 4 şablon)     [YENİ, ortak widget]
   │  └─ TemplateCard × 4
   │     ├─ Text(emoji)  Text(template.title)
   │     └─ Text('${criteria.length} hazır kriter') — rozet
   └─ TextButton('Tüm şablonlar') → context.push('/templates')

TemplateGalleryScreen  (/templates)               [YENİ]
└─ Scaffold
   ├─ AppBar('Şablonlar')
   └─ ListView (kategori grupları)
      └─ TemplateCard (aynı ortak widget) → onTap: showTemplatePreviewSheet

TemplatePreviewSheet (showModalBottomSheet)       [YENİ]
└─ DraggableScrollableSheet
   ├─ Text(template.title, headlineSmall) + Text(template.description)
   ├─ TextField(başlık, ön-dolu template.title)   ← oluşturulacak kararın adı
   ├─ 'Hazır kriterler' bölümü
   │  └─ ListTile × N: Text(name)  trailing: Text('Önem ${weight}/10')
   ├─ (varsa) 'Örnek seçenekler' Chip'leri
   └─ Row
      ├─ OutlinedButton('Boş başla')
      └─ FilledButton('Bu şablonla başla')        ← tek async CTA, spinner'lı

NewDecisionScreen (mevcut)                        [DEĞİŞİR]
└─ Column
   ├─ başlık TextField + 'Devam Et' (mevcut, aynen)
   ├─ Divider + Text('Ya da bir şablonla başla', labelMedium)
   └─ SizedBox(height: ~120)
      └─ ListView(horizontal)
         └─ TemplateCard(compact: true) × 6 → onTap: showTemplatePreviewSheet
```

### 2.2 A2 — Kriter Önerileri

```
CriteriaTab (mevcut)                              [DEĞİŞİR]
└─ ListView
   ├─ açıklama metni (mevcut)
   ├─ CriterionSuggestionStrip(decisionId)        [YENİ]
   │  └─ (öneri boşsa / kullanıcı kapattıysa / kriter ≥ 6 ise → SizedBox.shrink)
   │     Card(tonal)
   │     ├─ Row: Icon(auto_awesome) Text('Önerilen kriterler')
   │     │       Spacer  IconButton(✕, 'Önerileri gizle')
   │     └─ Wrap(spacing: s2)
   │        └─ ActionChip('+ ${s.name}') × ≤6
   │           onPressed → notifier.addCriterion(s.name, 5,
   │                         source: CriterionSource.aiSuggested)
   ├─ kriter Card'ları (mevcut, aynen)
   └─ 'Kriter ekle' OutlinedButton (mevcut, aynen)
```

### 2.3 A3 — Puanlama İlerlemesi

```
ScoresTab (mevcut)                                [DEĞİŞİR]
└─ Column                                         ← ListView'in üstüne sarmalayıcı
   ├─ ScoringProgressHeader(decisionId)           [YENİ, sticky]
   │  └─ Padding > Column
   │     ├─ Row: Text('Puanlama: ${filled}/${total}')
   │     │       Spacer  (tamamsa Icon(check_circle, primary))
   │     └─ LinearProgressIndicator(value: filled/total)  — animasyonlu
   └─ Expanded > ListView (mevcut gövde)
      └─ seçenek Card'ı (mevcut)
         └─ başlık Row                            [DEĞİŞİR]
            ├─ Expanded(Text(option.title))
            └─ OptionScoreBadge('${optFilled}/${criteria.length}')  [YENİ]
               — tamamsa primary container, değilse surfaceVariant

DecisionEditScreen (mevcut)                       [DEĞİŞİR — iki küçük nokta]
├─ TabBar → Tab('Puanlar') yanına kalan-hücre rozeti
│   Tab(child: Row[Text('Puanlar'), if(remaining>0) _CountBadge(remaining)])
└─ alt bar blocker metni: puanlama engeliyse
    resultReadinessProvider mesajı yerine 'Puanlama: X/Y — Z hücre kaldı'
```

---

## 3. Dosya Bazlı İmplementasyon Planı

Sıralama bağımlılık sırasıdır; her PR bağımsız merge edilebilir.

### PR A1 — Hazır Şablon Kararlar

**Yeni: `lib/features/templates/domain/entities/decision_template.dart`**
- Saf Dart sınıfları (freezed GEREKMEZ — serileşmez, const katalog verisi):
  - `DecisionTemplate { String id; String emoji; String title; String description; TemplateCategory category; List<TemplateCriterion> criteria; List<String> sampleOptions; }`
  - `TemplateCriterion { String name; int weight; }` — `Criterion`'dan ayrı,
    çünkü `id`/`source` üretimi uygulama anına aittir (id çakışması imkânsız olur).
  - `enum TemplateCategory { shopping, career, education, lifestyle }`

**Yeni: `lib/features/templates/domain/repositories/template_catalog.dart`**
- `abstract interface class TemplateCatalog { List<DecisionTemplate> all(); DecisionTemplate? byId(String id); }`
- Domain arayüzü — mevcut `decision_repository.dart` kalıbının aynısı.

**Yeni: `lib/features/templates/data/static_template_catalog.dart`**
- `class StaticTemplateCatalog implements TemplateCatalog` — 6 şablonluk
  `const` liste. İçerik Türkçe; kriter ağırlıkları 1-10, `Limits` ile uyumlu
  (kriter sayısı ≤ 6, `sampleOptions` ≤ 3 — `maxOptions=10` sınırının altında).

**Yeni: `lib/features/templates/presentation/providers/template_providers.dart`**
- `final templateCatalogProvider = Provider<TemplateCatalog>((_) => const StaticTemplateCatalog());`
- `final templateByIdProvider = Provider.family<DecisionTemplate?, String>(...)`

**Değişir: `lib/features/decision/domain/usecases/create_decision.dart`**
- `call()` imzasına opsiyonel `List<TemplateCriterion> initialCriteria`,
  `List<String> initialOptions` eklenir (varsayılan boş — geriye uyumlu).
- Gövde: her `TemplateCriterion`/başlık için `_idGenerator()` ile `Criterion(source: CriterionSource.user)` / `Option` üretir, `Decision`'a koyar,
  tek `upsert` (ek Firestore yazımı yok — mevcut tek-belge modeli).
  Not: şablon kriterleri `user` kaynaklıdır; `aiSuggested` A2'ye ayrılmıştır
  ki `ai_suggested_count` metriği iki özelliği karıştırmasın.
- Import yönü: templates → decision değil; `TemplateCriterion` yerine
  imza `List<({String name, int weight})>` (record) alınarak decision
  domain'inin templates'e bağımlılığı SIFIR tutulur. **Tercih edilen budur.**

**Yeni: `lib/features/templates/presentation/widgets/template_card.dart`**
- `TemplateCard { DecisionTemplate template; bool compact; VoidCallback onTap; }`

**Yeni: `lib/features/templates/presentation/widgets/template_preview_sheet.dart`**
- `Future<void> showTemplatePreviewSheet(BuildContext, WidgetRef, DecisionTemplate)`
- CTA: `createDecisionProvider` çağrısı (ownerUid: `currentUidProvider`,
  templateId, initialCriteria, initialOptions) → başarıda
  `context.pushReplacement('/decision/${id}/edit')`,
  `logDecisionCreated(source: 'template')` + `template_selected` olayı.
  Hata → sheet içi inline hata metni (`NewDecisionScreen` kalıbı).

**Yeni: `lib/features/templates/presentation/screens/template_gallery_screen.dart`**

**Değişir: `lib/app_router.dart`**
- `GoRoute(path: '/templates', builder: ... TemplateGalleryScreen())`

**Değişir: `lib/features/decision/presentation/screens/home_screen.dart`**
- `_EmptyState`: `_suggestions` sabiti kalkar → `templateCatalogProvider`'dan
  ilk 4 şablon + "Tüm şablonlar" bağı. (`ConsumerWidget`'a döner.)

**Değişir: `lib/features/decision/presentation/screens/new_decision_screen.dart`**
- Alt bölüme yatay `TemplateCard(compact)` şeridi.

**Değişir: `lib/core/services/analytics/analytics_service.dart`** (+ şema dokümanı)
- `logTemplateSelected({required String templateId})` — önce
  TEKNIK-MIMARI.md §9.1'e satır eklenir (mevcut kural).

### PR A2 — Kriter Öneri Sistemi

**Yeni: `lib/features/decision/domain/usecases/suggest_criteria.dart`**
- Saf sınıf `CriterionSuggester`:
  - `List<CriterionSuggestion> suggest({required Decision decision, List<({String name, int weight})> templateCriteria = const []})`
  - `CriterionSuggestion { String name; SuggestionOrigin origin; }`,
    `enum SuggestionOrigin { template, keyword, generic }`
  - İç sözlük: `Map<RegExp, List<String>>` Türkçe anahtar kelime kümeleri +
    genel dolgu listesi. Eleme: `toLowerCase('tr')` ad eşleşmesi; üst sınır 6.
  - Flutter/Riverpod importu YOK — birim testte doğrudan çağrılır.
  - Gelecek AI implementasyonu için not: arayüz senkron ve yereldir; AI
    varyantı ayrı bir `Future` tabanlı sağlayıcı olarak eklenecek, bu sınıf
    onun çevrimdışı/anında fallback'i olarak kalacaktır.

**Değişir: `lib/features/decision/presentation/providers/decision_editor.dart`**
- `addCriterion(String name, int weight, {CriterionSource source = CriterionSource.user})`
  — tek satırlık imza genişletmesi; mevcut çağrılar etkilenmez.

**Yeni: `lib/features/decision/presentation/providers/criterion_suggestions.dart`**
- `final criterionSuggesterProvider = Provider<CriterionSuggester>(...)`
- `final criterionSuggestionsProvider = Provider.autoDispose.family<List<CriterionSuggestion>, String>` —
  `decisionEditorProvider(id)` + `templateCatalogProvider`'ı (templateId
  doluysa) izler; kriter listesi her değiştiğinde otomatik yeniden hesaplar.
- `final suggestionsDismissedProvider = StateProvider.autoDispose.family<bool, String>((_, __) => false)`
  — ✕ davranışı, ekran ömrüyle sınırlı (autoDispose bilinçli).

**Yeni: `lib/features/decision/presentation/widgets/criterion_suggestion_strip.dart`**
- §2.2'deki widget. Chip onPressed → `addCriterion(..., source: aiSuggested)` +
  `logCriterionSuggestionAccepted(origin:)`; dönen `Failure` → SnackBar
  (`criteria_tab` dialog kalıbı).

**Değişir: `lib/features/decision/presentation/widgets/criteria_tab.dart`**
- Açıklama metninin altına `CriterionSuggestionStrip(decisionId)` eklenir.

**Değişir: `lib/core/services/analytics/analytics_service.dart`** (+ şema dokümanı)
- `logCriterionSuggestionAccepted({required String origin})`

### PR A3 — Puanlama İlerleme Göstergesi

**Değişir: `lib/features/decision/domain/entities/decision.dart`**
- `isScoreMatrixComplete`'in yanına türetilmiş getter'lar (JSON'a girmez,
  şema etkisi sıfır; `const Decision._()` zaten mevcut):
  - `int get totalScoreCells` — `options.length * criteria.length`
  - `int get filledScoreCells` — null olmayan hücre sayısı
  - `int filledScoreCellsFor(String optionId)`
- `build_runner` yeniden çalıştırılır (freezed part dosyaları), şema/JSON çıktısı değişmez.

**Yeni: `lib/features/decision/presentation/providers/scoring_progress.dart`**
- `typedef ScoringProgress = ({int filled, int total});`
- `final scoringProgressProvider = Provider.autoDispose.family<ScoringProgress, String>` —
  `decisionEditorProvider(id).select(...)` ile yalnız sayı değişince rebuild
  (slider sürüklemede her tick state ürettiğinden `select` burada performansın
  kendisidir).

**Yeni: `lib/features/decision/presentation/widgets/scoring_progress_header.dart`**
- §2.3 başlığı. `LinearProgressIndicator` + `AnimatedSwitcher`'lı tamam durumu.

**Değişir: `lib/features/decision/presentation/widgets/scores_tab.dart`**
- Gövde `Column[ScoringProgressHeader, Expanded(ListView)]` olur; seçenek kartı
  başlığına `_OptionScoreBadge` (dosya içi private widget yeter).

**Değişir: `lib/features/decision/presentation/screens/decision_edit_screen.dart`**
- `Tab('Puanlar')` rozeti + alt bar blocker metninin puanlama dalında
  `scoringProgressProvider` ile niceliksel mesaj.

**Not — validator:** `resultReadinessProvider` / `DecisionValidator.readyForResult`
sözleşmesi DEĞİŞMEZ; A3 yalnız sunum katmanında mesajı zenginleştirir.

---

## 4. Test Planı

Mevcut düzen korunur: `test/features/<feature>/...` ayna yolları,
`FakeFirebaseFirestore` ile repo override, `autosaveDebounceProvider` kısa
süre override'ı (decision_editor testlerindeki mevcut kalıp).

### 4.1 Birim testleri (domain — saf Dart)

**`test/features/templates/domain/static_template_catalog_test.dart`**
- Katalog değişmezleri (içerik değişse de kırılmayan sözleşme testleri):
  her şablonun `id`'si benzersiz; kriter sayısı 1–6; her ağırlık
  `Limits.criterionWeightMin..Max` içinde; başlık uzunluğu
  `Limits.titleMinLength..Max` içinde; `sampleOptions.length <= Limits.maxOptions`;
  `byId` bilinmeyen id'de null döner.

**`test/features/decision/domain/create_decision_test.dart`** (mevcutsa genişler)
- `initialCriteria` verildiğinde: karar o kriterlerle upsert edilir, her
  kriterin `id`'si benzersiz ve `source == user`, `templateId` yazılır.
- `initialCriteria` boş → mevcut davranış birebir (regresyon).
- Geçersiz başlık → `Err`, repo'ya yazım YOK (şablon yolunda da).

**`test/features/decision/domain/suggest_criteria_test.dart`**
- Şablon kriterleri önce gelir; eklenmiş olanlar (harf-duyarsız, 'İ/i'
  Türkçe locale vakası dahil: "FİYAT" varken "Fiyat" önerilmez) elenir.
- Başlık "iPhone mu Samsung mu?" → telefon kümesi döner (`origin: keyword`).
- Eşleşme yoksa genel set (`origin: generic`); toplam ≤ 6; determinizm
  (aynı girdi → aynı sıra).

**`test/features/decision/domain/decision_test.dart`** (mevcutsa genişler)
- `totalScoreCells` / `filledScoreCells` / `filledScoreCellsFor`:
  boş matris, kısmi, tam; seçenek/kriter silindikten sonra tutarlılık
  (removeOption/removeCriterion'ın score temizliğiyle uyum);
  `filled == total && total > 0 ⟺ isScoreMatrixComplete` özelliği
  (options ≥ 2 kısıtı dahil kenar durumlar).

### 4.2 Provider / notifier testleri (ProviderContainer)

**`test/features/decision/presentation/decision_editor_test.dart`** (genişler)
- `addCriterion(source: aiSuggested)` → kriter kaynağı doğru persist edilir
  ve `logCriteriaCompleted.aiSuggestedCount` doğru sayar (fake analytics).

**`test/features/decision/presentation/criterion_suggestions_test.dart`** (yeni)
- Kriter eklenince öneri listesi reaktif küçülür; dismiss → boş liste;
  kriter ≥ 6 → boş liste; templateId'li kararda şablon kriterleri önde.

**`test/features/decision/presentation/scoring_progress_test.dart`** (yeni)
- `setScore` sonrası `filled` artar; aynı hücreye ikinci yazım artırmaz;
  `removeCriterion` → `total` ve `filled` birlikte düşer.

### 4.3 Widget testleri

**`test/features/templates/presentation/template_preview_sheet_test.dart`**
- Sheet şablonun tüm kriterlerini ve ağırlıklarını gösterir; "Bu şablonla
  başla" → repo'da kriterleri dolu karar oluşur, editöre yönlenir (mevcut
  go_router test kalıbı); repo hatasında sheet kapanmaz + hata görünür;
  çift dokunuş tek karar üretir (CTA disable).

**`test/features/decision/presentation/home_screen_test.dart`** (genişler)
- Boş durumda 4 `TemplateCard` + "Tüm şablonlar" görünür; eski `_suggestions`
  butonlarının regresyonu (title query akışı şablonsuz yolda hâlâ çalışır).

**`test/features/decision/presentation/criteria_tab_test.dart`** (genişler)
- Chip dokunuşu kriter kartı oluşturur ve chip kaybolur; ✕ şeridi gizler;
  6 kriterli kararda şerit render edilmez.

**`test/features/decision/presentation/scores_tab_test.dart`** (genişler)
- Başlık "0/N" ile başlar; bir slider dokunuşu sonrası "1/N";
  seçenek rozetinin metni doğru; matris tamamlanınca tamam durumu görünür
  ve `DecisionEditScreen` alt barındaki "Sonucu Gör" aktifleşir (uçtan uca
  P3 senaryosu tek widget testinde).

### 4.4 Entegrasyon (integration_test/ — mevcut altyapı)

- **Altın yol A1→A3:** boş home → şablon kartı → önizleme → "Bu şablonla
  başla" → Seçenekler'e 2 seçenek → Kriterler zaten dolu → Puanlar'da
  ilerleme 0/N'den N/N'e → "Sonucu Gör" aktif → sonuç ekranı.
  (Aktivasyon hunisinin dört olayı fake analytics'te sırayla doğrulanır:
  `decision_created{template}` → `options_completed` → `criteria_completed` →
  `scoring_completed`.)
- **Firestore emülatör dumanı:** şablonla oluşturulan belgenin mevcut
  `firestore.rules`'tan geçtiği (kriter dizisi + templateId alanıyla yazım) —
  şema değişmediğinin kanıtı.

### 4.5 Çıkış kriterleri (Definition of Done)

- `flutter analyze` temiz; tüm mevcut testler yeşil (özellikle
  decision_editor debounce/patch testleri — `addCriterion` imza değişikliği).
- Yeni domain kodu %100 birim test kapsamında (saf fonksiyonlar için ucuz).
- Üç özellik de in-memory repo modunda (çevrimdışı ilk açılış) çalışır.
- Analytics şema dokümanı yeni iki olayla güncellenmiş.

---

## 5. Riskler ve Açık Sorular

| Risk | Etki | Önlem |
|------|------|-------|
| `addCriterion` imza değişikliği çağrı yerlerini kırar | Düşük — tek çağrı yeri (dialog) | Opsiyonel parametre; derleyici yakalar |
| Şablon içeriği ürün kararı gerektirir (metinler) | Orta | Katalog tek dosyada; copy incelemesi PR A1'de ayrı commit |
| Sticky header + ListView performansı düşük cihazda | Düşük | `select` ile sayısal rebuild; progress header sabit yükseklik |
| `aiSuggested` adının anlam genişlemesi kafa karıştırır | Düşük | decision.dart'a doküman yorumu: "sistem önerdi (şu an yerel motor)" |

**Açık soru (Sprint B'ye):** A3 ölçümü sonrası `scoring_completed` hâlâ
düşükse bir sonraki adım matrisin seçenek-bazlı sayfalara bölünmesidir
(wizard); bu tasarım header/rozet bileşenlerini o düzende aynen yeniden kullanır.
