# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

- **Last updated:** 2026-10-06
- **Project:** LooRadar — global community-powered restroom finder
- **Repository:** `mrdzyn/looradar`
- **Overall stage:** Application Implementation
- **Current phase:** Phase 2 — Add Restroom
- **Current milestone:** P2.0 — Phase 2 specification authoring and setup complete; independent exact-head specification audit pending
- **Current branch:** `phase-2/add-restroom`
- **Current PR:** Draft PR to be opened (`feat: implement LooRadar Phase 2 add restroom`)
- **Phase 2 base:** `main` at `11d3b6fcf8f22d3c2c6a91bcf8631198a6efa6a6`
- **Implementation status:** Phase 0 [MERGED]; Phase 1 [MERGED] (audit PASS 0/0/0, PR #3 squash-merged at `11d3b6fcf8f22d3c2c6a91bcf8631198a6efa6a6`); Phase 2 [ACTIVE]; P2.0 specification authored (`docs/09-phase-2-add-restroom.md`); P2.1 implementation BLOCKED pending independent P2.0 specification exact-head audit.

## Current objective

Establish the canonical technical contract and implementation specification for **Phase 2 — Add Restroom** (`docs/09-phase-2-add-restroom.md`).

Address all architectural findings before coding begins:
- Data-truth preservation via dedicated `RestroomDraft` domain model (never defaulting unconfirmed amenities to positive claims);
- Atomic public/private batch write contract (`restrooms/{id}` and `contributions/restroom_{id}`);
- Firestore Security Rules cross-validation (strict `unverified` status, zero aggregates, atomic contribution pairing);
- Canonical document ID generation and resolution of repository debt;
- Bounded, zero-paid-API duplicate detection heuristic engine and advisory UX;
- Comprehensive unit, emulator rules, widget, and integration test requirements.

The active specification is:

- `docs/09-phase-2-add-restroom.md`

## Locked decisions

- Product name: **LooRadar**.
- Global-first, mobile-first, UI/UX-first product.
- Flutter for iOS and Android.
- Google Maps SDK for visualization.
- Firebase Anonymous Authentication; no mandatory traditional login in V1.
- Public/private data boundary strictly enforced: public documents NEVER contain contributor UIDs.
- Community-contributed facilities are strictly initialized as `status: 'unverified'` with zero initial aggregates.
- Cloud Firestore + geohash candidate retrieval for MVP discovery and duplicate detection.
- Exact Haversine filtering after geohash candidate retrieval.
- Foreground location only; no background location or persisted movement history.
- External navigation handoff; no built-in routing.
- Avoid Places, Routes, Directions, Street View, and other unnecessary paid APIs.
- Low Firestore/Maps cost is an architectural constraint.
- Canonical UI reference remains `docs/assets/looradar-mobile-ux-reference.png`.

## Canonical references

Read before Phase 2 implementation:

1. `AGENTS.md`
2. `docs/STATUS.md`
3. `docs/09-phase-2-add-restroom.md`
4. `docs/08-phase-1-map-discovery.md`
5. `docs/06-ui-ux-reference.md`
6. `docs/01-architecture.md`
7. `docs/02-data-model.md`
8. `docs/03-privacy-security.md`
9. `docs/07-environment-setup.md`

## Merged baselines

### Phase 0 — Foundation & Design System [MERGED]
Squash-merged into `main` at `307baff1145287218a1056cee72295ec93de1624` (PR #2).
- Flutter scaffold, layered architecture, design tokens, map shell;
- Domain models, Firestore codecs, Firebase Anonymous Auth & App Check boundaries;
- Initial Firestore rules and emulator test harness.

### Phase 1 — Map Discovery [MERGED]
Squash-merged into `main` at `11d3b6fcf8f22d3c2c6a91bcf8631198a6efa6a6` (PR #3).
- **P1.1 GIS & Spatial Engine:** Complete polar coverage, spherical envelope expansion, candidate geohash ranges, exact Haversine/bounding box filtering, deterministic 16-range query limit.
- **P1.2 Query Orchestration & Clustering:** Idle-triggered camera debounce (400ms), single discovery pipeline, permission convergence without extra reads, Google Maps native clustering (`ClusterManager`), zoom suppression (< 12.0).
- **P1.3 Preview, List & Local Filters:** 100% in-memory preview card, nearby list, search, and local filters; derived-empty and degraded status messaging; 90-day verification freshness check.
- **P1.4 Hardening & Cost Bounds:** Bounded read limits (theoretical max 800 reads, 200 decoded candidates), non-blocking refresh error retention and retry, 48×48 touch targets, CI Node.js 22 upgrade, verified Android and iOS builds.
- Independent audit passed: 0 BLOCKER / 0 MAJOR / 0 MINOR.

---

## Active Phase 2 Scope — Add Restroom

### P2.0 — Specification & Task Contract (ACTIVE / COMPLETE)
- Authored canonical implementation specification in `docs/09-phase-2-add-restroom.md`.
- Documented data-truth model, atomic public/private write architecture, Firestore security rules invariants, canonical document ID generation, bounded duplicate detection heuristics, and phased test plan.
- Updated project documentation index and tracking status.
- Opened draft PR `Phase 2 — Add Restroom` on `phase-2/add-restroom`.
- Independent exact-head specification audit pending.

### P2.1 — Contribution Domain Model (`RestroomDraft`), Repository Batch Write Contract, Firestore Rules & Emulator Tests (BLOCKED)
- *Blocked pending P2.0 specification audit approval.*
- Implement `RestroomDraft` and `TriStateAmenity` in `lib/domain/models/restroom_draft.dart`.
- Update `RestroomRepository` interface with `Future<Restroom> submitRestroom(RestroomDraft draft)`.
- Implement atomic batch write in `FirestoreRestroomRepository` writing `/restrooms/{id}` and `/contributions/restroom_{id}`.
- Update `InMemoryRestroomRepository` with mock batch support.
- Update `firestore.rules` to enforce `status: 'unverified'`, `id == restroomId`, zero aggregates, and atomic `/contributions/restroom_{id}` pairing via `getAfter()`.
- Author comprehensive security rules tests in `rules_tests/p2_add_restroom_rules_test.js`.

### P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX (PLANNED)
- Implement `AddRestroomLocationScreen` with interactive center crosshair / draggable pin on Google Maps.
- Enforce zoom floor (`zoom >= 15.0`) with visual hint.
- Display live formatted coordinate readouts (5 decimal places).
- Unit and widget tests for location selection interactions.

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management (PLANNED)
- Implement `AddRestroomFormScreen` with organized card sections (Basic Info, Indoor Directions, Accessibility, Amenities, Fee/Key notes).
- Implement tri-state amenity selector widgets.
- Implement `AddRestroomNotifier` form state management and input validation.
- Unit tests for form validation and widget tests for form rendering and error states.

### P2.4 — Bounded Duplicate Detection Engine & Advisory Warning UX (PLANNED)
- Implement `DuplicateDetectionService` with 500m geohash candidate retrieval and heuristic scoring.
- Implement `DuplicateWarningSheet` advisory UI.
- Unit tests for similarity heuristics and edge cases; widget tests for modal display and button actions.

### P2.5 — End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback (PLANNED)
- Connect anonymous authentication lifecycle.
- Wire submit action through repository batch write.
- Sync successful submissions with `MapDiscoveryNotifier` (camera move, optimistic cache injection, preview selection).
- End-to-end integration and widget tests.

### P2.6 — Hardening, Accessibility, Regression Suite & Validation (PLANNED)
- Audit touch targets (>= 48×48), semantic labels, and contrast.
- Run complete test suite (`flutter test`, Firestore emulator rules tests).
- Validate platform compilation (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`).
- Update `docs/STATUS.md` and prepare Phase 2 for audit.

---

## Phase 2 Intentionally Excluded

Do not implement in this phase:

- photo uploads (Phase 5);
- ratings and reviews submission (Phase 3);
- verification and report submission (Phase 3);
- Google Places autocomplete or Geocoding APIs;
- turn-by-turn routing (external handoff only);
- social logins or traditional user accounts;
- web/admin moderation dashboards (Phase 4).

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
- `flutter test` — PASS (171/171 passed)
- Firestore Security Rules emulator tests — PASS (20/20 passed)
- `git diff --check` — PASS (clean, no trailing whitespace or formatting defects)
- Secrets scan — PASS (0 secrets or private keys in git tree)
- Firebase live discovery — NOT RUN; live device/owner config pending
- Google Maps live discovery — NOT RUN; live device/owner config pending

## Next recommended action

Perform independent exact-head audit on P2.0 specification (`docs/09-phase-2-add-restroom.md`) on `phase-2/add-restroom`. Upon passing audit, proceed to P2.1 implementation.

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