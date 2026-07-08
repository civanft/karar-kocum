# Proje Yapısı

Feature-first Clean Architecture (gerekçe: [TEKNIK-MIMARI.md](TEKNIK-MIMARI.md) AD-8).

```
karar-veriyorum/
├── docs/                    # PRD, mimari, sprint planı, bu doküman
├── lib/
│   ├── main.dart            # bootstrap: (Sprint 2+) Firebase init, ProviderScope
│   ├── app.dart             # MaterialApp.router, tema bağlama
│   │
│   ├── core/                # ÖZELLİKLERDEN BAĞIMSIZ altyapı — features/ import EDEMEZ
│   │   ├── config/          #   ortam/flavor tanımları (Sprint 2)
│   │   ├── constants/       #   limits.dart — ürün limitleri (tek doğruluk kaynağı)
│   │   ├── error/           #   Failure hiyerarşisi + Result<T>
│   │   ├── extensions/      #   Dart/Flutter extension'ları
│   │   ├── l10n/            #   arb dosyaları (Sprint 6'da doldurulur)
│   │   ├── network/         #   Dio kurulumu (Sprint 2)
│   │   ├── router/          #   GoRouter haritası + guard'lar
│   │   ├── services/        #   id_generator, analytics sarmalayıcıları
│   │   ├── theme/           #   Material 3 tema + tasarım token'ları
│   │   └── widgets/         #   paylaşılan görsel bileşenler
│   │
│   └── features/            # her özellik kendi içinde üç katman taşır:
│       │                    #   domain/   → entity, validator, repo arayüzü, use case (SAF DART)
│       │                    #   data/     → repo implementasyonu, datasource, dto
│       │                    #   presentation/ → screen, widget, provider
│       ├── auth/            # giriş, anonim oturum (Sprint 2/4)
│       ├── decision/        # karar CRUD, seçenek, artı/eksi, kriter — çekirdek modül
│       ├── scoring/         # ağırlıklı skor motoru — %100 test, flutter import YASAK
│       ├── ai_analysis/     # AI proxy istemcisi, streaming (Sprint 2-3)
│       ├── results/         # sonuç ekranı, what-if simülatörü
│       ├── history/         # geçmiş: arama, filtre, favori (Sprint 4)
│       ├── paywall/         # abonelik, kota, RevenueCat (Sprint 5)
│       ├── report/          # PDF, paylaşım kartı (Sprint 6)
│       ├── onboarding/      # ilk açılış akışı (Sprint 6)
│       └── settings/        # profil, tema, KVKK akışları (Sprint 6)
│
├── functions/               # Cloud Functions (TypeScript) — AI proxy, billing, KVKK
│   └── src/{ai,billing,privacy,quota,moderation}/
├── test/                    # lib/ yapısını aynalar (unit + widget)
├── integration_test/        # E2E altın yollar (Sprint 4+)
├── scripts/                 # check_layers.sh — katman kuralı denetimi (CI'da zorunlu)
├── android/ ios/ web/       # platform iskeleti (flutter create üretimi)
│                            #   web yalnız geliştirme önizlemesi içindir, mağaza hedefi değildir
├── firestore.rules          # güvenlik kuralları (plan/quota istemciye kapalı)
├── firestore.indexes.json
├── analysis_options.yaml    # lint + strict mode
└── .github/workflows/ci.yaml
```

## Katman bağımlılık kuralları

```
presentation ──► domain ◄── data          core ──► (hiçbir feature'a değil)
```

1. `domain/` **saf Dart** — `package:flutter` import edemez.
2. `domain/`, `data/` veya `presentation/` import edemez.
3. `core/`, `features/` import edemez.

Denetim: `bash scripts/check_layers.sh` — CI'da her PR'da koşar.

## Yeni özellik eklerken

1. `lib/features/<ad>/{domain,data,presentation}` iskeletini kur.
2. Önce domain: entity → validator → repo arayüzü → use case (testleriyle).
3. Sonra data: repo implementasyonu (in-memory/fake ile başla, testte yaşamaya devam eder).
4. En son presentation: provider → screen; iş mantığı widget'a sızmasın.
5. Rota `core/router/app_router.dart`'a eklenir; ürün limiti gerekiyorsa `core/constants/limits.dart`'a.
