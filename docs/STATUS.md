# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

**Last updated:** 2026-09-30  
**Project:** LooRadar — global community-powered restroom finder  
**Repository:** `mrdzyn/looradar`  
**Overall stage:** Application Implementation  
**Current phase:** Phase 0 — Foundation + UI shell/design system  
**Current branch:** `phase-0/foundation`  
**Current PR:** [#2](https://github.com/mrdzyn/looradar/pull/2) — `feat: establish LooRadar Phase 0 application foundation`  
**Audited implementation head:** `cbdbae417505c3ffd8dece347f37975b67dc3b45`  
**Implementation status:** Passed Exact-Head Re-Audit (0 BLOCKER / 0 MAJOR findings; ready for merge decision)

## Current objective

Establish the production-oriented Flutter foundation, architecture boundaries, design system tokens, UI shell, GIS utilities, Firebase/Maps boundaries, and CI baseline ready for Phase 1 Map Discovery.

## Locked decisions

- Product name: **LooRadar**.
- Global-first, mobile-first product.
- UI/UX-first delivery approach.
- Flutter for iOS and Android.
- Google Maps SDK for map visualization.
- Firebase Anonymous Authentication; no mandatory traditional login in V1.
- Cloud Firestore + geohashes for MVP GIS/nearby queries.
- Firebase App Check and restrictive Firestore rules are part of the security baseline.
- Foreground location only in V1.
- No persisted user movement/location history.
- External navigation handoff instead of building routing.
- Indoor location metadata (building/floor/wing/landmark/directions) is first-class.
- Photos deferred until after the core MVP workflow is proven.
- Optional donation/support model; no intrusive advertising planned for initial release.
- Low infrastructure cost and privacy-by-default are architectural constraints.

## Canonical references

Read these before implementation:

- `AGENTS.md` — multi-agent operating contract.
- `docs/README.md` — documentation index and current decisions.
- `docs/00-product-vision.md` — vision and product principles.
- `docs/01-architecture.md` — technical/GIS architecture and cost controls.
- `docs/02-data-model.md` — initial Firestore/domain model.
- `docs/03-privacy-security.md` — privacy and security baseline.
- `docs/04-mvp-scope.md` — MVP boundaries and acceptance criteria.
- `docs/05-phase-0-plan.md` — Phase 0 implementation plan and definition of done.
- `docs/06-ui-ux-reference.md` — UX rules and validation gates.
- `docs/07-environment-setup.md` — secrets, platform keys, App Check, and budget setup.
- `docs/assets/looradar-mobile-ux-reference.png` — **canonical visual reference** for user-facing implementation.

## Completed

- Scaffolded Flutter iOS and Android application with package identifier `com.looradar.looradar`.
- Designed clean layered architecture: Presentation -> State -> Domain -> Data Repositories -> Firebase/GIS Adapters.
- Established design tokens (`AppColors`, `AppTypography`, `AppSpacing`, `AppRadii`, `AppTheme`) matching canonical visual reference.
- Built reusable UI components: `LooPrimaryButton`, `LooSecondaryButton`, `AmenityChip`, `StatusChip`, `RestroomSummaryCard`, `MapSearchBar`, `MapRecenterButton`, `PermissionBanner`, `LooBottomNavBar`, `LooLoadingIndicator`, `EmptyStateView`, `ErrorStateView`.
- Implemented UI Shell: `SplashScreen` (Mockup 1), `MainShellScreen` (5-tab shell), `MapDiscoveryScreen` (Mockup 2).
- Built typed domain models: `Restroom`, `Rating`, `Verification`, `RestroomReport`, `Coordinates`, enums with full indoor metadata and zero contributor UIDs in public domain models.
- Implemented clean Firestore serialization boundary with native `Timestamp` adapters (`FirestoreCodec`, `RestroomFirestoreCodec`, `RatingFirestoreCodec`, `RestroomReportFirestoreCodec`, `VerificationFirestoreCodec`) preserving domain layer independence from Firebase.
- Implemented automated Firestore Security Rules test harness with 20 emulator tests (`rules_tests/test/firestore_rules.test.js`) testing public reads, private data protection, contribution auth, UID exclusion, aggregate protection, coordinate validation, and deterministic rating ownership.
- Removed premature production Firestore spatial querying; explicitly deferred spatial methods (`getNearbyRestrooms`, `getViewportRestrooms`) in `FirestoreRestroomRepository` via `UnsupportedError` to prevent partial or un-debounced spatial reads before Phase 1.
- Documented single-cell prefix calculation in `GeohashService.getCandidatePrefixes` and deferred full 9-neighbor multi-cell candidate expansion to Phase 1.
- Built Firebase Anonymous Authentication boundary (`AuthRepository`, `FirebaseAuthRepositoryImpl`, `InMemoryAuthRepository`).
- Configured Cloud Firestore repository boundary (`FirestoreRestroomRepository`, `InMemoryRestroomRepository`).
- Created Cloud Firestore Security Rules (`firestore.rules`) and indexes (`firestore.indexes.json`) enforcing public/private separation, deterministic `ratingOwnership/{restroomId}_{auth.uid}`, aggregate protections, and coordinate validations.
- Implemented Firebase App Check boundary (`FirebaseAppCheckService`) with debug provider in development and Play Integrity / App Attest in production.
- Configured foreground location permissions (`LocationRepositoryImpl`, `LocationNotifier`, `PermissionBanner`) with graceful manual exploration fallback.
- Added GitHub Actions CI (`.github/workflows/ci.yml`) for formatting, analysis, Flutter tests, and automated Firestore Security Rules emulator tests.
- Documented environment, secrets, budget alerts, cost controls, and Android production signing safeguards in `docs/07-environment-setup.md`.
- Expanded test suite: 46 Flutter tests passing and 20 Firestore rules tests passing.

## Active work

PR #2 substantive exact-head re-audit passed at implementation head `cbdbae417505c3ffd8dece347f37975b67dc3b45` with 0 BLOCKER and 0 MAJOR findings. Final bookkeeping cleanup applied. Ready for merge decision.

## Not started / later phases (Phase 1 Scope Intentionally Deferred)

**Phase 1 — Map Discovery:**
- Production geohash multi-cell candidate expansion (9-cell neighbor algorithm)
- Production Firestore spatial queries (`getNearbyRestrooms`, `getViewportRestrooms`)
- Viewport query debounce (300-500ms idle window)
- Live restroom map markers & marker clustering
- Preview card carousel / bottom sheet expansion
- Filter bottom sheet & query filters

**Phase 2 — Add Restroom:** adjustable map pin, location/building/floor/landmark metadata, amenities/access fields, duplicate warning, anonymous submission.

**Phase 3 — Ratings + Verification + Reporting:** community quality signals and freshness workflows.

**Phase 4 — Moderation / Trust / Production Hardening:** abuse controls, stronger aggregation/moderation workflows, production readiness.

**Phase 5 — Growth features:** photos, broader/open-data integrations, and other validated enhancements.

## Current blockers / human actions

1. **Google Maps Platform API Keys:** Create platform-restricted keys for Android (`com.looradar.looradar` + SHA-1) and iOS (`com.looradar.looradar`) as documented in `docs/07-environment-setup.md`.
2. **Firebase Project Configuration:** Enable Anonymous Authentication in Firebase Console; download `google-services.json` and `GoogleService-Info.plist` into local developer workspaces.
3. **Google Cloud Billing:** Configure budget alerts in GCP Console (\$25/mo threshold alerts).
4. **Android Production Signing:** Generate production keystore and configure `android/key.properties` prior to release readiness.

## Validation status

- `dart format --output=none --set-exit-if-changed lib test` — PASS (53 files checked, formatted)
- `flutter analyze` — PASS (0 issues found, strict mode enabled)
- `flutter test` — PASS (46/46 unit & widget tests passing)
- `npm --prefix rules_tests run test:emulators` — PASS (20/20 Firestore security rules tests passing in Firestore Emulator)
- Android debug build (`flutter build apk --debug`) — PASS (APK assembled successfully)
- iOS build configuration (`flutter build ios --config-only --no-codesign`) — PASS (Xcode project and CocoaPods configured successfully)
- Firebase live deployment / runtime — NOT RUN (Requires owner Firebase project credentials)
- Google Maps live SDK rendering — NOT RUN (Requires owner platform-restricted API key)

## Next recommended action

Review final bookkeeping delta on PR #2 and execute merge decision. Once merged into `main`, proceed to **Phase 1 — Map Discovery**.

## Handoff template

Every implementation agent should update the current sections above and leave a compact handoff in this format:

```text
Task:
Branch:
Commit:
PR:

Implemented:
- ...

Validation:
- ... — PASS | FAIL | NOT RUN

Docs updated:
- ...

Blockers / risks:
- ...

Next recommended action:
- ...
```

Do not preserve stale completed-task detail here merely for history. Keep this file useful to the **next agent**.