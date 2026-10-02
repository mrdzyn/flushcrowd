# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

**Last updated:** 2026-10-02  
**Project:** LooRadar — global community-powered restroom finder  
**Repository:** `mrdzyn/looradar`  
**Overall stage:** Application Implementation  
**Current phase:** Phase 1 — Map Discovery  
**Current milestone:** P1.2 — audit remediation completed; re-audit pending  
**Current branch:** `phase-1/map-discovery`  
**Current PR:** [#3](https://github.com/mrdzyn/looradar/pull/3) — `feat: implement LooRadar Phase 1 map discovery` (draft)  
**Phase 1 base:** `main` at `307baff1145287218a1056cee72295ec93de1624`  
**Implementation status:** P1.1 audited (0 findings); P1.2 query orchestration, markers, clustering, and audit remediation completed (107/107 tests green); P1.3 preview/list/filters is next pending P1.2 re-audit approval

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

### P1.2 — Query orchestration + markers/clustering (AUDIT REMEDIATED, RE-AUDIT PENDING)

Implemented, remediated, and verified:

- **BLOCKER-1 Remediated:** In-flight request invalidation implemented via `_invalidateActiveRequest()`. Any in-flight asynchronous query generation is invalidated on `onCameraMoveStarted()` and on intentional suppression (`zoom < minViewportZoom` and `ViewportTooLargeException`). Stale responses and stale errors from prior camera positions cannot commit or overwrite map state;
- **MAJOR-1 Remediated:** Duplicate read elimination on recenter. Removed redundant `loadNearbyRestrooms` call in `_recenterOnUser()`; camera animation to user coordinates triggers `onCameraIdle`, which alone performs the debounced, quantized query;
- **MAJOR-2 Remediated:** Selected restroom lifecycle hardened. User-selected restrooms are tracked with `_selectionIsUserInitiated`; surviving selected restrooms are preserved across queries; disappearing restrooms are cleared to `null` without silently jumping to the first result; auto-selection of first result only applies when `_selectedRestroom == null` and `!_selectionIsUserInitiated`;
- **MINOR-1 Remediated:** Antimeridian-aware viewport query descriptor equivalence. Circular angular distance `min(|lngA - lngB|, 360 - |lngA - lngB|) <= coordinateToleranceDegrees` correctly detects equivalent viewports spanning ±180°;
- **Camera lifecycle debounce:** central `AppConstants.cameraIdleDebounceDuration = 400ms`; no repository queries during camera pan/zoom movement (`onCameraMove`);
- **Query equivalence & quantization:** `ViewportQueryDescriptor` value object with coordinate tolerance (0.0001° ~ 11m) and zoom quantization (0.1) suppresses redundant Firestore reads on programmatic recentering or duplicate idle events;
- **Zoom & oversized viewport suppression:** queries suppressed when zoom < `AppConstants.minViewportZoom` (12.0) or on `ViewportTooLargeException`; UI displays non-blocking "Zoom in to see restrooms" pill;
- **DiscoveryResult completeness propagation:** `MapDiscoveryNotifier` exposes `isComplete`, `completenessReason`, `rangeCount`, and `candidateCount`; partial results render with `loadedDegraded` status;
- **Center/local prefix prioritization:** candidate geohash prefixes in nearby and viewport queries are prioritized nearest to center coordinates so that any range-cap degradation covers the visible user area;
- **Restroom marker model & adapter:** presentation model `RestroomMarkerItem` and `MapMarkerAdapter` providing stable identity by restroom ID, visual selection distinction (`hueAzure` vs `hueBlue`), and strict 1:1 deduplication;
- **Marker clustering:** integrated Google Maps native clustering (`ClusterManager`), cluster tap zooms into cluster region without arbitrarily selecting an individual restroom;
- **Foreground location separation:** user position remains platform-controlled (`myLocationEnabled`) and visually separate from restroom markers without historical tracking;
- **Comprehensive test suites:** 107 unit/widget tests green across query orchestration, debounce, query equivalence, concurrency/stale-token protection, suppression, marker adaptation, clustering, request invalidation, and selection lifecycle.

### P1.3 — Preview/list/filters (NEXT)

Planned after P1.2 audit:

- restroom preview/bottom sheet;
- nearby list;
- Phase 1 filters;
- loading/empty/error/offline/degraded states;
- accessibility refinements.

### P1.4 — Hardening and human QA

Planned final Phase 1 milestone:

- Firestore read/cost review;
- Android/iOS live QA where credentials are available;
- privacy/security regression;
- final documentation/status handoff;
- independent exact-head audit before merge.

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

- `dart format --output=none --set-exit-if-changed lib test` — PASS (clean)
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (107/107 passed)
- Firestore Security Rules emulator tests — PASS (20/20 passed)
- Firebase live discovery — NOT RUN; live device/owner config pending
- Google Maps live discovery — NOT RUN; live device/owner config pending

## Next recommended action

Perform independent exact-head re-audit of **P1.2 — Map query orchestration + markers/clustering** on `phase-1/map-discovery`. Do NOT begin P1.3 until audit passes.

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