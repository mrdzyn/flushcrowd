# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

**Last updated:** 2026-10-04  
**Project:** LooRadar — global community-powered restroom finder  
**Repository:** `mrdzyn/looradar`  
**Overall stage:** Application Implementation  
**Current phase:** Phase 1 — Map Discovery  
**Current milestone:** P1.3 — Restroom preview, nearby list, and local filters implementation complete; independent audit pending  
**Current branch:** `phase-1/map-discovery`  
**Current PR:** [#3](https://github.com/mrdzyn/looradar/pull/3) — `feat: implement LooRadar Phase 1 map discovery` (draft)  
**Phase 1 base:** `main` at `307baff1145287218a1056cee72295ec93de1624`  
**Implementation status:** P1.1 audited (0 findings); P1.2 audited (0 findings); P1.3 preview, nearby list, and local filters completed (140/140 tests green); P1.4 hardening/QA is BLOCKED pending final independent P1.3 exact-head audit approval

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

### P1.2 — Query orchestration + markers/clustering (FINAL REMEDIATION COMPLETED, RE-AUDIT PENDING)

Implemented, remediated, and verified:

- **Location Permission Grant Flow Single-Path Convergence:** In `MapDiscoveryScreen`, `PermissionBanner.onRequestPermission` now animates the camera to the newly granted user location (`_mapController.animateCamera`) instead of invoking `loadNearbyRestrooms()`. Discovery converges purely through the canonical camera idle → debounce → viewport query flow with 0 nearby repository reads. If permission is denied or dismissed, manual map exploration continues uninterrupted with 0 nearby reads.
- **MAJOR-1 Remediated (Single Startup Discovery Path):** Removed automatic startup `loadNearbyRestrooms()` bootstrap from `MapDiscoveryScreen`. The map now has a single authoritative discovery path: map creation → camera settles → `onCameraIdle` → debounced viewport discovery. Verified normal map startup issues 1 viewport discovery call and 0 nearby discovery calls.
- **MAJOR-2 Remediated (Last Committed Viewport State Restoration):** Introduced ephemeral runtime snapshot `_LastCommittedViewportState` storing the descriptor, items, status (`loadedComplete`, `loadedDegraded`, `empty`), and completeness metadata of the last committed viewport query. When returning to an equivalent viewport, notifier restores the committed snapshot rather than staying stuck in `loading` or `suppressed`. Explicit refresh bypasses reuse and queries again. Materially different descriptors and uncommitted/error states never trigger restoration.
- **MAJOR-3 Remediated (Sticky User-Selection History):** Introduced `SelectionOrigin` enum (`none`, `automatic`, `user`, `clearedAfterUserSelection`). Once a user explicitly taps/selects a facility, their selection history is preserved. If that chosen facility disappears from the visible area, selection clears to `null` and transitions to `clearedAfterUserSelection`. Future query results remain intentionally unselected until the user explicitly selects another facility; automatic fallback selection never resumes after user interaction.
- **BLOCKER-1 Remediated:** In-flight request invalidation implemented via `_invalidateActiveRequest()`. Any in-flight asynchronous query generation is invalidated on `onCameraMoveStarted()` and on intentional suppression (`zoom < minViewportZoom` and `ViewportTooLargeException`). Stale responses and stale errors from prior camera positions cannot commit or overwrite map state.
- **Recenter Duplicate Read Elimination:** Programmatic camera animation in `_recenterOnUser()` relies exclusively on `onCameraIdle` to trigger debounced discovery, eliminating duplicate nearby reads.
- **Antimeridian-aware Viewport Equivalence:** Circular angular distance `min(|lngA - lngB|, 360 - |lngA - lngB|) <= coordinateToleranceDegrees` correctly detects equivalent viewports spanning ±180°.
- **Camera lifecycle debounce:** central `AppConstants.cameraIdleDebounceDuration = 400ms`; zero repository queries during camera pan/zoom movement (`onCameraMove`).
- **Zoom & oversized viewport suppression:** queries suppressed when zoom < `AppConstants.minViewportZoom` (12.0) or on `ViewportTooLargeException`; UI displays non-blocking "Zoom in to see restrooms" pill.
- **DiscoveryResult completeness propagation:** `MapDiscoveryNotifier` exposes `isComplete`, `completenessReason`, `rangeCount`, and `candidateCount`; partial results render with `loadedDegraded` status.
- **Center/local prefix prioritization:** candidate geohash prefixes in nearby and viewport queries are prioritized nearest to center coordinates.
- **Restroom marker model & adapter:** presentation model `RestroomMarkerItem` and `MapMarkerAdapter` providing stable identity by restroom ID, visual selection distinction (`hueAzure` vs `hueBlue`), and strict 1:1 deduplication.
- **Marker clustering:** integrated Google Maps native clustering (`ClusterManager`), cluster tap zooms into cluster region without arbitrarily selecting an individual restroom.
- **Foreground location separation:** user position remains platform-controlled (`myLocationEnabled`) and visually separate from restroom markers without historical tracking.
- **Comprehensive test suites:** 116 unit/widget tests green across query orchestration, debounce, query equivalence, concurrency/stale-token protection, suppression, marker adaptation, clustering, request invalidation, committed-state restoration, startup single-path, selection lifecycle, and permission-grant viewport convergence. Audited and approved at `b88d42d62d2688850d07eee8fffc7da480918e09` with 0 findings.

### P1.3 — Restroom preview, nearby list & local filters (IMPLEMENTATION COMPLETE, AUDIT PENDING)

Implemented, verified, and strictly isolated to zero additional Firestore reads:

- **Zero-read local execution invariant:** Restroom preview, nearby list, local search, and filter matching operate 100% in-memory against `_discoveredRestrooms` already retrieved by the P1.1/P1.2 viewport discovery pipeline. Zero additional Firestore or repository queries are issued when opening preview, scrolling list, typing query text, applying filters, or resetting filters.
- **Restroom Preview Bottom Sheet (`RestroomPreviewSheet`):**
  - Displays facility title, rating badge, review count, access type pill, status badge, indoor navigation hierarchy (`buildingName · buildingSection · floor · unitOrArea`), landmark callout, directions note, and verification freshness badge.
  - Safe Haversine distance display when foreground location is available; cleanly omitted with zero distance assumptions when location is unavailable.
  - Amenity chip row for verified features (wheelchair accessibility, baby changing, bidet, free/paid, etc.).
  - Primary "Get Directions" action (designed for external navigation handoff) and secondary Share/Dismiss actions.
  - Gracefully omits empty or absent optional fields without layout glitches or placeholder clutter.
- **Nearby Restrooms List Sheet (`NearbyRestroomsSheet`):**
  - Draggable, scrollable modal bottom sheet listing visible/filtered facilities using compact `RestroomSummaryCard`.
  - Deterministic sorting: sorts by computed Haversine distance when user location is known; sorts alphabetically by name and ID when user location is absent.
  - Fully synchronized with map markers: tapping a list item selects the facility, updates preview, and triggers camera centering.
  - Explicit distinction between geographic emptiness ("No restrooms found in this area") and filter-driven emptiness ("No restrooms match the selected filters" with an inline "Reset Filters" action).
- **Domain Filter Model & Matching Semantics (`DiscoveryFilters`):**
  - Pure domain value object in `lib/domain/models/discovery_filters.dart`.
  - Filter categories: access types (`free`, `paid`, `customer_only`, `key_required`), gender designations (`female`, `male`, `all_gender`), amenities (`isAccessible`, `hasBabyChanging`, `hasBidet`, `hasToiletPaper`, `hasSoap`, `hasHandDryer`), quality & freshness (`minRating`, `recentlyVerifiedOnly` within 90 days).
  - Strict matching semantics: within-category **OR** (e.g. matching any selected access type or gender), across-category **AND** (all active amenity, rating, verification, and category criteria must be met).
  - Helper properties: `isActive`, `activeFilterCount`.
- **Search & Filter Modal (`FilterBottomSheet` & `MapSearchBar`):**
  - Filter modal with staged local state: users can stage changes and tap "Apply Filters" or "Reset All".
  - Search bar displays active filter count badge indicator when filters are active.
  - In-memory case-insensitive search matching name, building name, landmark, and directions note.
- **Selection Lifecycle Synchronization:**
  - When active filters hide the currently selected restroom, `_selectedRestroom` is safely cleared to `null` and `_selectionOrigin` becomes `SelectionOrigin.clearedAfterUserSelection`. The app never jumps to an arbitrary alternative facility.
  - When filters or search are reset and the previously selected restroom reappears, it is cleanly restored without disrupting user focus.
- **Degraded Status Preservation:**
  - Underlying discovery status (`loadedComplete`, `loadedDegraded`, `suppressed`, `error`) is preserved intact when filters or search are applied. Filter emptiness triggers `isFilteredEmpty` without corrupting underlying query state.
- **Comprehensive test suites:** 140/140 unit and widget tests green, including 24 dedicated P1.3 tests verifying all preview fields, distance handling, sorting, selection synchronization, within-group OR and across-group AND filter semantics, search matching, filter reset, and filter bottom sheet interactions.

### P1.4 — Hardening and human QA (BLOCKED)

Planned final Phase 1 milestone (strictly blocked pending independent P1.3 exact-head audit):

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
- `flutter test` — PASS (140/140 passed)
- Firestore Security Rules emulator tests — PASS (20/20 passed)
- Firebase live discovery — NOT RUN; live device/owner config pending
- Google Maps live discovery — NOT RUN; live device/owner config pending

## Next recommended action

Perform independent exact-head audit of **P1.3 — Restroom Preview, Nearby List & Local Filters** on `phase-1/map-discovery`. Do NOT begin P1.4 until audit passes.

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