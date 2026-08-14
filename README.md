# Karar Veriyorum

> AI destekli karar asistanı — önemli kararlarını dakikalar içinde yapılandır, puanla, tarafsız analiz al.

Flutter (iOS + Android) · Clean Architecture · Riverpod · Firebase

## Ne yapar?

Kullanıcı bir karar konusu oluşturur ("iPhone mu Samsung mu?", "Almanya mı Kanada mı?"), seçeneklerini ve artı/eksilerini girer, kendi önem ağırlıklarıyla kriterler belirler; uygulama ağırlıklı skor hesaplar ve (Sprint 3+) yapay zekâ tarafsız analiz, risk ve gözden kaçan kriter önerisi sunar.

## Dokümanlar

| Doküman | İçerik |
|---|---|
| [PRD](docs/PRD.md) | Ürün gereksinimleri, personalar, user story'ler, metrikler |
| [Teknik Mimari](docs/TEKNIK-MIMARI.md) | Katmanlar, veri modeli, güvenlik, ADR'ler |
| [Sprint Planı](docs/SPRINT-PLAN.md) | 7 sprintlik yol haritası ve DoD tanımları |
| [Proje Yapısı](docs/PROJE-YAPISI.md) | Klasör yapısı ve katman kuralları |
| [Katkı Rehberi](CONTRIBUTING.md) | Dal stratejisi, commit kuralları, PR kontrol listesi |

## Hızlı başlangıç

Önkoşullar: Flutter SDK ≥ 3.44 (`brew install --cask flutter`), iOS için Xcode, Android için Android Studio.

```sh
git clone <repo-url> && cd karar-veriyorum
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Freezed/JSON codegen
flutter test                                               # 24 test, tamamı geçmeli
flutter run                                                # bağlı cihaz/simülatör gerekir
```

Cihazsız hızlı önizleme (web):

```sh
flutter build web && cd build/web && python3 -m http.server 8788
# http://localhost:8788
```

## Kalite kapıları

Her PR şunlardan geçmek zorunda (CI: `.github/workflows/ci.yaml`):

```sh
dart format --output=none --set-exit-if-changed lib test   # format
flutter analyze --fatal-infos                              # sıfır bulgu
bash scripts/check_layers.sh                               # katman kuralları
flutter test --coverage                                    # tüm testler yeşil
bash scripts/check_coverage.sh 80                          # kapsam ≥ %80
```

Functions tarafı (Node 20; emulator gerektirenler için Java 21):

```sh
npm --prefix functions run lint
npm --prefix functions run build
npm --prefix functions test              # birim testler
npm --prefix functions run test:rules    # Firestore Rules (emulator)
npm --prefix functions run test:privacy  # hesap silme kaskadı (Firestore+Auth emulator)
```

Emulator testleri yalnız `demo-karar` projesine bağlanır; emulator host
değişkenleri yoksa fail-fast eder (canlı projeye asla dokunmaz).

Katman kuralı: `presentation → domain ← data`; domain saf Dart (flutter import edemez); `core/`, `features/`'ı import edemez.

## Hesap ve veri silme (mağaza zorunluluğu)

Ayarlar → **Hesap ve Veriler** → "Hesabımı ve Verilerimi Sil" akışı, `deleteAccount`
callable'ını çağırır: `users/{uid}` ağacı recursive, `rateLimits/{uid}` ve
`rateLimits/{uid}:reward` ayrıca silinir, en son Auth hesabı silinir. `ops/*`
global sayaçları korunur. Cihazdaki takip tercihleri ve planlı bildirimler
temizlenir, ardından yeni ve boş bir misafir oturumu açılır.

Deploy sırası ZORUNLU: önce `firebase deploy --only functions:deleteAccount`,
sonra istemci sürümü. Ayrıntı: [docs/FIRESTORE-VERI-MODELI.md](docs/FIRESTORE-VERI-MODELI.md) §8.

## Sprint durumu

- [x] Sprint 0 — PRD, mimari, iskelet, skor motoru (testli)
- [x] Sprint 1 — çekirdek karar akışı (yerel): karar → seçenek → kriter → puan → sonuç ✅ 24/24 test
- [ ] Sprint 2 — Firebase temeli + AI proxy
- [ ] Sprint 3 — AI analiz deneyimi
- [ ] Sprint 4 — hesap & senkron
- [ ] Sprint 5 — abonelik & kota
- [ ] Sprint 6 — PDF, paylaşım, KVKK
- [ ] Sprint 7 — sertleştirme & mağaza lansmanı

## Bilinen kısıtlar (Sprint 1)

- Veriler bellek içi tutulur — uygulama kapanınca kaybolur (Firestore Sprint 2'de).
- AI analizi henüz bağlı değil (Sprint 2-3).
- `riverpod_lint`/`custom_lint` geçici olarak devre dışı (analyzer 7.6 uyumsuzluğu); katman denetimini `scripts/check_layers.sh` yapıyor.
