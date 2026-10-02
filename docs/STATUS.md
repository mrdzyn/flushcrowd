# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

**Last updated:** 2026-10-02  
**Project:** LooRadar — global community-powered restroom finder  
**Repository:** `mrdzyn/looradar`  
**Overall stage:** Application Implementation  
**Current phase:** Phase 1 — Map Discovery  
**Current milestone:** P1.1 — GIS + Firestore discovery engine remediation completed (re-audit pending)  
**Current branch:** `phase-1/map-discovery`  
**Current PR:** [#3](https://github.com/mrdzyn/looradar/pull/3) — `feat: implement LooRadar Phase 1 map discovery` (draft)  
**Phase 1 base:** `main` at `307baff1145287218a1056cee72295ec93de1624`  
**Implementation status:** P1.1 audit findings (BLOCKER-1, BLOCKER-2, MAJOR-1, MAJOR-2, MINOR-1) remediated and verified; P1.2 query orchestration is BLOCKED pending exact-head re-audit approval

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

### P1.1 — GIS + Firestore discovery engine (REMEDIATION COMPLETED, RE-AUDIT PENDING)

Remediated and implemented:

- **Full geometric envelope and spherical-cap polar coverage:** spherical-cap delta longitude formulation with full-world `[-180, 180]` coverage for caps enclosing geographic poles; dynamic grid sampling across allowed radii (up to 10 km) and high latitudes ensuring 100% spatial coverage without fixed 3x3 assumptions or artificial longitude clamping;
- **Explicit completeness contract:** introduced domain `DiscoveryResult<T>` and `DiscoveryCompletenessReason` (`complete`, `rangeCapExceeded`, `perRangeLimitExceeded`, `candidateLimitExceeded`, `resultCapExceeded`) ensuring UI is never silently misled;
- **Antimeridian viewport correctness:** `GeoBoundingBox` antimeridian spanning and wraparound containment;
- **Domain layer purity:** `GeoBoundingBox` in `lib/domain/models/`, removing data-layer leakage into domain contracts;
- **Injectable Firestore range executor:** `FirestoreQueryExecutor` enables deterministic verification of production query loops, candidate deduplication, status filtering, caps, and error mapping;
- **Comprehensive test suites:** 76 unit/widget tests green, including dedicated polar facility coverage across meridians, non-immediate geohash cell facility discovery, isolated candidate/range caps, and 10 km outer boundary cases.

### P1.2 — Query orchestration + markers/clustering (BLOCKED)

BLOCKED pending exact-head re-audit of P1.1. Do NOT implement until P1.1 re-audit passes.

Planned:

- camera-idle debounce (300–500 ms);
- equivalent-query reuse;
- stale/superseded response protection;
- real markers and selected state;
- dense-marker clustering;
- zoom-too-low/query-suppressed behavior.

### P1.3 — Preview/list/filters

Planned after P1.2:

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
- `flutter test` — PASS (76/76 passed)
- Firestore Security Rules emulator tests — PASS (20/20 passed)
- Firebase live discovery — NOT RUN; live device/owner config pending
- Google Maps live discovery — NOT RUN; live device/owner config pending

## Next recommended action

Perform independent exact-head re-audit of **P1.1 — GIS + Firestore discovery engine remediation** on `phase-1/map-discovery`. Do NOT begin P1.2 until re-audit passes.

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