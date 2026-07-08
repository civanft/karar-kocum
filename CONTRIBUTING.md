# Katkı Rehberi

## Dal (branch) stratejisi

- `main` — her zaman yeşil (CI geçer, testler tam). Doğrudan push yok; yalnız PR ile.
- `feature/<sprint>-<kısa-ad>` — örn. `feature/s2-firestore-repo`
- `fix/<kısa-ad>` — hata düzeltmeleri
- Sürümler `release/x.y` etiketiyle mağazaya gider (bkz. CI bölümü).

## Commit mesajı kuralı — Conventional Commits

```
<tip>(<kapsam>): <özet — emir kipi, küçük harf, nokta yok>

<gövde: neden ve ne — isteğe bağlı ama teşvik edilir>
```

**Tipler:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`, `perf`

**Kapsamlar:** özellik modülü adları (`decision`, `scoring`, `auth`, `paywall`, `report`, …) veya `core`, `functions`, `infra`

Örnekler:

```
feat(decision): seçenek başına artı/eksi listeleri ekle
fix(scoring): tek kriterde ağırlık normalizasyon hatasını düzelt
test(editor): kaskad silme senaryolarını kapsa
docs(architecture): AD-9 offline strateji kararını ekle
```

## PR kontrol listesi

- [ ] `dart format` temiz, `flutter analyze --fatal-infos` sıfır bulgu
- [ ] `bash scripts/check_layers.sh` yeşil
- [ ] Yeni/değişen davranış için test var; tüm testler geçiyor
- [ ] Domain katmanına flutter import'u eklenmedi
- [ ] Kullanıcıya görünen metinler Türkçe (l10n arb'a taşıma Sprint 6'da)
- [ ] Gizli anahtar/serbest API key yok (`.env`, `key.properties` vb. gitignore'da)
- [ ] PR açıklaması: ne değişti + neden + nasıl test edildi

## Mimari kurallar (özet — ayrıntı: docs/TEKNIK-MIMARI.md)

1. **Katman yönü:** `presentation → domain ← data`. Domain saf Dart'tır; hiçbir şeye bağımlı değildir.
2. **`core/` asla `features/` import etmez.** Paylaşılan UI/altyapı core'a, iş mantığı ilgili feature'a.
3. **İş mantığı widget'lara yazılmaz** — Notifier/UseCase'e gider; widget yalnız provider okur.
4. **LLM çağrıları yalnız Cloud Functions üzerinden** — istemcide API anahtarı bulunduran PR reddedilir.
5. **`plan`, `quota`, `aiAnalysis` alanlarını yalnız Functions yazar** — rules'a bu kuralı gevşeten değişiklik güvenlik incelemesi ister.
6. **Ürün limitleri tek yerde:** `core/constants/limits.dart` — rules ve Functions ile senkron tutulur; limit değiştiren PR üç katmanı da güncellemeli.

## Test beklentileri

| Katman | Minimum |
|---|---|
| `scoring/` | %100 — her davranış değişikliği testle gelir |
| domain use case & validator | ≥ %90 |
| genel | ≥ %80 (CI kapısı — etkinleştirilecek) |

Test adlandırması: davranış cümlesi, Türkçe ("`seçenek silinince puanları da silinir`").

## Geliştirme akışı

```sh
flutter pub get
dart run build_runner watch --delete-conflicting-outputs   # codegen izleme
flutter test                                               # her push öncesi
```

Üretilen dosyalar (`*.g.dart`, `*.freezed.dart`) commit edilmez; CI kendisi üretir.
