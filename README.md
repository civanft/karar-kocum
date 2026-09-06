# Karar Veriyorum

> AI-assisted decision helper — structure your important decisions in minutes, score them, and get an impartial analysis.

Flutter (iOS + Android) · Clean Architecture · Riverpod · Firebase

## What does it do?

The user creates a decision topic ("iPhone or Samsung?", "Germany or Canada?"), enters the options along with their pros and cons, and defines criteria with their own importance weights; the app calculates a weighted score and (Sprint 3+) provides an impartial AI analysis, risk assessment, and suggestions for criteria that may have been overlooked.

## Documentation

| Document | Contents |
|---|---|
| [PRD](docs/PRD.md) | Product requirements, personas, user stories, metrics |
| [Technical Architecture](docs/TEKNIK-MIMARI.md) | Layers, data model, security, ADRs |
| [Sprint Plan](docs/SPRINT-PLAN.md) | 7-sprint roadmap and DoD definitions |
| [Project Structure](docs/PROJE-YAPISI.md) | Folder structure and layer rules |
| [Contributing Guide](CONTRIBUTING.md) | Branching strategy, commit conventions, PR checklist |

## Quick start

Prerequisites: Flutter SDK ≥ 3.44 (`brew install --cask flutter`), Xcode for iOS, Android Studio for Android.

```sh
git clone <repo-url> && cd karar-veriyorum
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Freezed/JSON codegen
flutter test                                               # 24 tests, all must pass
flutter run                                                # requires a connected device/simulator
```

Quick preview without a device (web):

```sh
flutter build web && cd build/web && python3 -m http.server 8788
# http://localhost:8788
```

## Quality gates

Every PR must pass the following (CI: `.github/workflows/ci.yaml`):

```sh
dart format --output=none --set-exit-if-changed lib test   # formatting
flutter analyze --fatal-infos                              # zero findings
bash scripts/check_layers.sh                               # layer rules
flutter test --coverage                                    # all tests green
bash scripts/check_coverage.sh 80                          # coverage ≥ 80%
```

Functions side (Node 22; Java 21 for the ones that require the emulator):

```sh
npm --prefix functions run lint
npm --prefix functions run build
npm --prefix functions test              # unit tests
npm --prefix functions run test:rules    # Firestore Rules (emulator)
npm --prefix functions run test:privacy  # account deletion cascade (Firestore+Auth emulator)
```

Emulator tests connect only to the `demo-karar` project; if the emulator host
variables are not set, they fail fast (they never touch the live project).

### Live smoke test

Runs against the live Firebase project; the API key is read **from the environment only**,
there is no default value in the repository. If the variable is not set, it stops without
making any network request.

```sh
FIREBASE_WEB_API_KEY=<your-client-key> node scripts/smoke/live_smoke_test.mjs
```

Layer rule: `presentation → domain ← data`; domain is pure Dart (it cannot import flutter); `core/` cannot import `features/`.

## Account and data deletion (app store requirement)

Settings → **Account and Data** → the "Delete My Account and My Data" flow calls the
`deleteAccount` callable: the `users/{uid}` tree is deleted recursively, `rateLimits/{uid}`
and `rateLimits/{uid}:reward` are deleted separately, and the Auth account is deleted last.
Global `ops/*` counters are preserved. Tracking preferences stored on the device and any
scheduled notifications are cleared, after which a new, empty guest session is started.

Deployment order is MANDATORY: first `firebase deploy --only functions:deleteAccount`,
then the client release. Details: [docs/FIRESTORE-VERI-MODELI.md](docs/FIRESTORE-VERI-MODELI.md) §8.

## Sprint status

- [x] Sprint 0 — PRD, architecture, skeleton, scoring engine (tested)
- [x] Sprint 1 — core decision flow (local): decision → option → criterion → score → result ✅ 24/24 tests
- [ ] Sprint 2 — Firebase foundation + AI proxy
- [ ] Sprint 3 — AI analysis experience
- [ ] Sprint 4 — account & sync
- [ ] Sprint 5 — subscription & quota
- [ ] Sprint 6 — PDF, sharing, KVKK (Turkish data protection law)
- [ ] Sprint 7 — hardening & store launch

## Known limitations (Sprint 1)

- Data is kept in memory — it is lost when the app is closed (Firestore comes in Sprint 2).
- AI analysis is not connected yet (Sprints 2-3).
- `riverpod_lint`/`custom_lint` are temporarily disabled (analyzer 7.6 incompatibility); layer checks are handled by `scripts/check_layers.sh`.
