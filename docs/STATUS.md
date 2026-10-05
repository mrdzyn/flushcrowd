# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

**Last updated:** 2026-10-05  
**Project:** LooRadar — global community-powered restroom finder  
**Repository:** `mrdzyn/looradar`  
**Overall stage:** Application Implementation  
**Current phase:** Phase 1 — Map Discovery  
**Current milestone:** P1.4 — hardening complete; final Phase 1 independent audit pending  
**Current branch:** `phase-1/map-discovery`  
**Current PR:** [#3](https://github.com/mrdzyn/looradar/pull/3) — `feat: implement LooRadar Phase 1 map discovery` (draft)  
**Phase 1 base:** `main` at `307baff1145287218a1056cee72295ec93de1624`  
**Implementation status:** P1.1 audited (PASS); P1.2 audited (PASS); P1.3 audited (PASS); P1.4 hardening, platform builds, accessibility polish, CI modernization, bounds documentation, and failure resilience complete; ready for final independent Phase 1 / P1.4 exact-head audit.

## Current objective

Implement production-quality, bounded, cost-conscious map discovery on top of the merged Phase 0 foundation without weakening privacy/security or prematurely expanding into later product phases.

The active specification is:

- `docs/08-phase-1-map-discovery.md`

## Locked decisions

- Product name: **LooRadar**.
- Global-first, mobile-first, UI/UX-first product.
- Flutter for iOS and Android.
- Google Maps SDK for visualization.
- Firebase Anonymous Authentication; no mandatory traditional login in V1.
- Cloud Firestore + geohash candidate retrieval for MVP discovery.
- Exact Haversine filtering after geohash candidate retrieval.
- Foreground location only; no background location or persisted movement history.
- Discovery reads only sanitized public restroom data.
- External navigation handoff; no built-in routing.
- Avoid Places, Routes, Directions, Street View, and other unnecessary paid APIs.
- Low Firestore/Maps cost is an architectural constraint.
- Canonical UI reference remains `docs/assets/looradar-mobile-ux-reference.png`.

## Canonical references

Read before Phase 1 implementation:

1. `AGENTS.md`
2. `docs/STATUS.md`
3. `docs/08-phase-1-map-discovery.md`
4. `docs/06-ui-ux-reference.md`
5. `docs/01-architecture.md`
6. `docs/02-data-model.md`
7. `docs/03-privacy-security.md`
8. `docs/07-environment-setup.md`

## Phase 0 baseline — merged

PR #2 was squash-merged into `main` at:

`307baff1145287218a1056cee72295ec93de1624`

Baseline capabilities include:

- Flutter iOS/Android scaffold and layered architecture;
- design tokens and map-first UI shell;
- pure Dart domain models;
- Firestore Timestamp codec boundary;
- Firebase Anonymous Auth and App Check boundaries;
- restrictive Firestore rules plus emulator tests;
- foreground location handling;
- in-memory/demo repositories;
- GIS primitives and Haversine utilities;
- CI for formatting, analysis, Flutter tests, and Firestore Rules tests.

Last validated Phase 0 evidence before merge:

- `flutter analyze` — PASS
- `flutter test` — PASS (46/46)
- Firestore Rules emulator tests — PASS (20/20)
- Android debug build — PASS
- iOS config/no-codesign build — PASS

## Active Phase 1 scope

### P1.0 — Specification and task contract

- Production discovery behavior and limits documented in `docs/08-phase-1-map-discovery.md`.

### P1.1 — GIS + Firestore discovery engine (AUDITED & APPROVED)

Audited at `d6771fb12b84b53d49602d21c0218b9771035559` with 0 BLOCKER / 0 MAJOR / 0 MINOR findings.

Capabilities:
- Full geometric envelope and spherical-cap polar coverage without fixed 3x3 grid assumptions;
- Explicit completeness contract via `DiscoveryResult<T>` and `DiscoveryCompletenessReason`;
- Antimeridian viewport correctness via `GeoBoundingBox.contains` and wrapping;
- Domain layer purity with `GeoBoundingBox` in `lib/domain/models/`;
- Minimum safe query precision floor `AppConstants.minDiscoveryGeohashPrecision = 3` (~156 km floor);
- Deterministic 16-range query limit safety cap under real production constraints;
- Center-distance prioritization for candidate prefixes under range-cap degradation.

### P1.2 — Query orchestration + markers/clustering (AUDITED & APPROVED)

Audited at `b88d42d62d2688850d07eee8fffc7da480918e09` with 0 BLOCKER / 0 MAJOR / 0 MINOR findings.

Key capabilities:
- Single authoritative discovery flow: camera idle → debounce (400ms) → viewport query → render.
- Permission-grant camera animation converges strictly into the viewport idle pipeline with zero nearby reads.
- Ephemeral last-committed viewport state restoration on equivalent viewports.
- Selection lifecycle preserves explicit user selections and never auto-resumes once user interacts.
- In-flight request cancellation on camera move start and zoom suppression.
- Google Maps native clustering (`ClusterManager`), cluster tap zooms into region.
- 116/116 unit/widget tests passing.

### P1.3 — Restroom preview, nearby list & local filters (AUDITED & APPROVED)

Audited at `120c445437ad88ac8f1e0a8f6dcb49cb39c27c14` with 0 BLOCKER / 0 MAJOR / 0 MINOR findings.

Key capabilities:
- Zero-read local execution: preview, list, search, and filters operate 100% in-memory against already-discovered restrooms.
- Clear derived-empty and degraded status messages with targeted reset actions (`Clear search`, `Reset filters`, `Clear search & filters`).
- Nearby restrooms list accessible without active selection via bottom bar.
- Truthful status badges: no false "Open" claims; warning badge shown only when temporarily unavailable.
- Strict 90-day verification freshness check and truthful preview freshness labels.
- Deterministic 3-level sorting (distance, normalized name, restroom ID).

### P1.4 — Hardening and human QA (FINAL AUDIT REMEDIATION COMPLETE, RE-AUDIT PENDING)

Completed final Phase 1 hardening milestone:

- **P1.4A — Firestore Read/Cost Upper Bounds (Aligned with Code Truth):**
  - Viewport discovery bounded to zoom ≥ 12.0 (`AppConstants.minViewportZoom`), 400ms camera idle debounce (`AppConstants.cameraIdleDebounceDuration`).
  - Geohash query ranges capped at max 16 (`AppConstants.maxGeohashQueryRanges`) for both nearby (`take(16)`) and viewport queries.
  - Per-range Firestore document limit: 50 documents (`AppConstants.maxDocumentsPerRangeQuery`).
  - Theoretical max raw documents read: `16 × 50 = 800` documents for both nearby and viewport discovery.
  - Candidate document decoding safety ceiling: 200 candidates (`AppConstants.maxCandidateDocuments`) in local memory (clarified: local decoding ceiling, not billed Firestore reads).
  - Maximum returned results cap: 100 facilities (`AppConstants.maxDiscoveryResults`).
  - Zero rating/review fan-out reads (restroom aggregates used exclusively).
  - Zero search/filter Firestore network fan-out (100% client-side memory evaluation).
  - Full bounds documented in `docs/08-phase-1-map-discovery.md`.
- **P1.4B — Privacy & Security Verification:**
  - Zero background location permissions or service modes (`AndroidManifest.xml` and `Info.plist` clean).
  - Zero telemetry or precise location coordinates persisted.
  - 20/20 Firestore Security Rules emulator tests passing.
  - Zero secrets or private keys in git tree.
- **P1.4C — CI / Toolchain Hardening:**
  - Node.js upgraded to LTS 22 in `.github/workflows/ci.yml`, resolving engine deprecation warnings.
  - devDependencies npm audit classified (21 transitive dev-only dependencies in test runner; zero production impact).
- **P1.4D — Failure Resilience & Non-Blocking Refresh Error Display:**
  - Retained-results error handling: query failures retain previously discovered facilities and markers in memory rather than blanking the map.
  - Non-blocking error overlay in `MapStatusOverlay`: when refresh fails with existing results, displays `"Couldn't refresh this area — showing previous results"` with a `"Retry"` action; when an initial query fails with zero results, displays `"Couldn't find restrooms — check connection"` with `"Retry"`.
  - Notifier tracks `_lastAttemptedDescriptor` and provides `retryLastViewportQuery()`.
  - Verified by unit test #35 in `test/presentation/map_discovery_notifier_test.dart` and 2 dedicated widget tests in `test/presentation/p1_3_preview_list_filter_test.dart`.
- **P1.4E — Accessibility & Touch Target Polish:**
  - Close button touch targets across `RestroomPreviewSheet` and `NearbyRestroomsSheet` meet standard 48×48 minWidth/minHeight with semantic tooltips.
  - Broader dynamic type / contrast / screen reader audits marked as `NOT RUN / PLANNED` for dedicated manual QA pass.
- **P1.4F — Platform Compilation Validation:**
  - Android debug APK build verified: `flutter build apk --debug` PASS (exit code 0).
  - iOS debug Runner build verified: `flutter build ios --debug --no-codesign` PASS (exit code 0).
- **P1.4G — Live Device & Credential QA Protocol:**
  - Live Firebase and Google Maps services documented as `NOT RUN` pending human owner credential configuration

## Phase 1 intentionally excluded

Do not implement in this phase:

- add-restroom workflow;
- rating/review submission;
- verification/report submission;
- photos;
- built-in routing;
- Google Places search/autocomplete;
- Street View;
- background location;
- precise-location analytics;
- PostGIS migration;
- AI features;
- donations/monetization.

## Current owner actions / external dependencies

These are not required for emulator/unit implementation but are required for full live QA:

1. Create/reuse platform-restricted Google Maps Android and iOS keys.
2. Configure the Firebase project and enable Anonymous Authentication.
3. Place local `google-services.json` and `GoogleService-Info.plist` files outside version control.
4. Configure GCP budget alerts.
5. Production Android signing remains a later release-readiness action.

## Current validation status

- `dart format --output=none --set-exit-if-changed lib test` — PASS (clean, 71 files formatted)
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (168/168 passed)
- Firestore Security Rules emulator tests — PASS (20/20 passed)
- `flutter build apk --debug` — PASS (built `build/app/outputs/flutter-apk/app-debug.apk`)
- `flutter build ios --debug --no-codesign` — PASS (built `build/ios/iphoneos/Runner.app`)
- Firebase live discovery — NOT RUN; live device/owner config pending
- Google Maps live discovery — NOT RUN; live device/owner config pending

## Next recommended action

Perform final independent Phase 1 / P1.4 exact-head audit on `phase-1/map-discovery`. Upon passing audit, squash-merge PR #3 into `main` and proceed to Phase 2 — Add Restroom.

## Handoff template

Every implementation agent should leave:

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

Keep this file useful to the **next agent**, not as a chronological diary.