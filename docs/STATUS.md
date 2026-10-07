# LooRadar — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

- **Last updated:** 2026-10-07
- **Project:** LooRadar — global community-powered restroom finder
- **Repository:** `mrdzyn/looradar`
- **Overall stage:** Application Implementation
- **Current phase:** Phase 2 — Add Restroom
- **Current milestone:** P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX: implementation complete; independent exact-head audit pending
- **Current branch:** `phase-2/add-restroom`
- **Current PR:** [#4](https://github.com/mrdzyn/looradar/pull/4) — `feat: implement LooRadar Phase 2 add restroom` (draft)
- **Phase 2 base:** `main` at `11d3b6fcf8f22d3c2c6a91bcf8631198a6efa6a6`
- **Implementation status:** Phase 0 [MERGED]; Phase 1 [MERGED] (audit PASS 0/0/0, PR #3 squash-merged at `11d3b6fcf8f22d3c2c6a91bcf8631198a6efa6a6`); Phase 2 [ACTIVE]; P2.0 specification [APPROVED — PASS 0 BLOCKER / 0 MAJOR / 0 MINOR]; P2.1 [APPROVED — PASS 0 BLOCKER / 0 MAJOR / 0 MINOR]; P2.2 [IMPLEMENTED — independent exact-head audit pending]; P2.3 [BLOCKED pending P2.2 audit].

## Current objective

Independent exact-head audit of **Phase 2 Milestone P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX** (`docs/09-phase-2-add-restroom.md` §4.2):
- Implemented `AddRestroomLocationScreen` in `lib/presentation/screens/add_restroom_location_screen.dart` with interactive Google Map and fixed center target pin overlay (`_buildCenterTargetIndicator`).
- Selected facility coordinate represented strictly via canonical `Coordinates` value object (`lib/domain/models/coordinates.dart`).
- Enforced minimum zoom floor (`zoom >= 15.0`, `minConfirmationZoom`) with precision guidance hint: `"Zoom in to place the restroom more precisely."` shown whenever zoom is below 15.0; confirmation is disabled until zoom floor is met and camera is idle.
- Live coordinate readout formatted to exactly 5 decimal places (~1.1m precision): `${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}` (e.g. `14.58390, 121.06170`).
- Camera movement updates lightweight visual state (`_isCameraMoving`) and animates target pin without triggering persistence, domain updates, or database reads/writes; camera idle (`onCameraIdle`) commits selected coordinate from camera target.
- Initial location order: 1) explicit `initialCoordinates` if provided; 2) current foreground device location via `LocationRepository`/`LocationNotifier` if permission granted; 3) safe fallback (`AppConstants.defaultLatitude`, `AppConstants.defaultLongitude`).
- Added "Use my location" action (`MapRecenterButton`) to center map on current device location with non-blocking error feedback if permission denied or location disabled; manual map exploration remains fully functional without GPS.
- Clean navigation seam returning `Coordinates` via `onLocationConfirmed` callback and `Navigator.pop(selectedCoordinates)` via static `route()` factory; no premature P2.3 form created.
- Zero Firestore reads, zero Firestore writes, zero Places API, zero Geocoding API, zero Directions/Routes APIs, zero background location, zero movement history.
- Full accessibility: touch targets $\ge 48\times 48$, semantics on center target pin, coordinate readout, location button, and Continue button.
- Authored 16 focused unit & widget tests in `test/presentation/add_restroom_location_screen_test.dart` covering all 14 prompt criteria plus antimeridian normalization and route navigation.
- Validated full Flutter test suite (248 total Flutter tests, all PASS: 232 prior + 16 new P2.2 tests).
- Validated all 49 Firestore Security Rules tests under Firestore emulator.

The active specification is:

- `docs/09-phase-2-add-restroom.md`

## Locked decisions

- Product name: **LooRadar**.
- Global-first, mobile-first, UI/UX-first product.
- Flutter for iOS and Android.
- Google Maps SDK for visualization.
- Firebase Anonymous Authentication; no mandatory traditional login in V1.
- Public/private data boundary strictly enforced: public documents NEVER contain contributor UIDs.
- Public restroom facilities in Phase 2 are strictly CREATE-ONLY (`allow update, delete: if false;`).
- Public contribution-derived amenity and stall fields use nullable booleans (`bool?`), preserving data truth.
- Community-contributed facilities are strictly initialized as `status: 'unverified'` with zero initial aggregates.
- Cloud Firestore + geohash candidate retrieval for MVP discovery and duplicate detection.
- Exact Haversine filtering after geohash candidate retrieval.
- Foreground location only; no background location or persisted movement history.
- External navigation handoff; no built-in routing.
- Avoid Places, Routes, Directions, Street View, and other unnecessary paid APIs.
- Low Firestore/Maps cost is an architectural constraint.
- Discovery repository and viewport query pipeline remain the single authoritative source of truth for the map.
- Production community contribution writes require enforceable server-side rate limiting.
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

### P2.0 — Specification & Task Contract [APPROVED — PASS 0 BLOCKER / 0 MAJOR / 0 MINOR]
- Authored canonical implementation specification in `docs/09-phase-2-add-restroom.md`.
- Remediated all audit findings (MAJOR-1 through MAJOR-3, MINOR-1 through MINOR-3).
- Updated `docs/02-data-model.md` (nullable boolean schema and `accessInstructions`).
- Updated `docs/03-privacy-security.md` (create-only rule and production rate-limiting release gate).
- Updated project documentation index and tracking status.
- Independent specification audit passed: 0 BLOCKER / 0 MAJOR / 0 MINOR.

### P2.1 — Contribution Domain Model (`RestroomDraft`), Nullable Schema Migration, Repository Batch Write Contract, Firestore Rules & Emulator Tests [FINAL DOCUMENTATION CLOSURE COMPLETE — INDEPENDENT EXACT-HEAD AUDIT PENDING]
- Reconciled canonical specification in `docs/09-phase-2-add-restroom.md` §8.3 to reflect the approved hardened ambiguous reconciliation contract (direct write without pre-reads, public-only initial read on ambiguous failure, conditional private read, permission-denied mapping to invariant failure, independent public/private field validation, stable ID retry invariant without same-call auto-retry, and preserved timestamp provenance note).
- Implemented `RestroomDraft`, `TriStateAmenity`, normalization method (`draft.normalized()`), and domain validation.
- Implemented `CreateRestroomCommand` in `lib/domain/commands/create_restroom_command.dart`.
- Migrated `Restroom` public domain model to nullable booleans (`bool?` for amenities/stalls) and added `accessInstructions`.
- Updated `RestroomFirestoreCodec` for nullable booleans, `accessInstructions`, fee fields, and legacy missing field decoding to `null`.
- Updated `RestroomRepository` interface with `Future<Restroom> submitRestroom(CreateRestroomCommand command)`.
- Remediated BLOCKER-1: removed pre-submission reads on first-submit path; first action executes atomic `WriteBatch` (`restrooms/{id}` and `contributions/restroom_{id}`) directly.
- Remediated MAJOR-1: full ambiguous commit reconciliation on batch commit failure with full identity and field validation.
- Remediated MAJOR-1 (Reconciliation Hardening): introduced `FirestoreDocumentData` to return unmutated document maps from `ProductionFirestoreMutationAdapter`, validating both `documentId` and stored `data['id']` independently on public and private documents.
- Remediated MAJOR-1 (Parity): identical full-pair reconciliation validation in `InMemoryRestroomRepository`.
- Remediated MAJOR-2 (Permission-Denied Handling): caught Firebase `permission-denied` on private contribution reconciliation read and mapped to `SubmissionInvariantException` to align with live security rules when private documents are unreadable or unowned. Transient network errors rethrow as retryable `RepositoryException`.
- Remediated MAJOR-2 / 2B / 2C (Rules Hardening): updated `firestore.rules` with `isValidGenderConfiguration`, regex currency validation (`^[A-Z]{3}$`), and regex geohash validation (`^[0-9bcdefghjkmnpqrstuvwxyz]{4,12}$`).
- Remediated MAJOR-3: narrow `FirestoreMutationAdapter` (`ProductionFirestoreMutationAdapter`) with 34 targeted tests in `test/data/firestore_restroom_repository_test.dart` verifying all required production criteria, error mappings, and documentId invariants.
- Remediated MINOR-1: evaluated and documented timestamp provenance deferral to server boundary hardening.
- Remediated MINOR-2: rejected whitespace-containing stable `restroomId` in both repositories (`restroomId != restroomId.trim()`) throwing `RepositoryException` with code `invalid-restroom-id` without trimming.
- Remediated MINOR-3: first-submit returns `createdAt: null`, `updatedAt: null` without fabricating timestamps or running extra post-write reads.
- Authored Firestore Security Rules emulator tests in `rules_tests/test/p2_add_restroom_rules.test.js` (49 total rules tests, all PASS).
- Validated full Flutter test suite (232 total Flutter tests, all PASS).

### P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX [IMPLEMENTED — INDEPENDENT EXACT-HEAD AUDIT PENDING]
- Implemented `AddRestroomLocationScreen` with interactive Google Map and fixed center crosshair / target pin overlay (`_buildCenterTargetIndicator`).
- Selected facility coordinate represented strictly via canonical `Coordinates` domain model (`lib/domain/models/coordinates.dart`).
- Enforced zoom floor (`zoom >= 15.0`) with visual precision hint: `"Zoom in to place the restroom more precisely."` and disabled Continue action until zoom floor is met and camera is idle.
- Displayed live formatted coordinate readouts (5 decimal places, e.g. `14.58390, 121.06170`) via `Coordinates`.
- Camera movement updates lightweight visual state (`_isCameraMoving`) without triggering persistence or queries; camera idle commits target coordinates.
- "Use my location" button moves camera and updates selection if available; manual map selection remains fully functional when GPS is unavailable.
- Clean navigation seam returning `Coordinates` via callback and `Navigator.pop`.
- Authored 16 unit and widget tests in `test/presentation/add_restroom_location_screen_test.dart` covering all 14 prompt criteria plus antimeridian normalization and route navigation.

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management [BLOCKED pending P2.2 audit]
- Implement `AddRestroomFormScreen` with organized card sections (Basic Info, Indoor Directions, Accessibility, Amenities, Access Instructions & Fee).
- Implement tri-state amenity selector widgets.
- Implement `AddRestroomNotifier` form state management, normalization, validation, and ID allocation.
- Unit tests for form validation and widget tests for form rendering and error states.

### P2.4 — Bounded Duplicate Detection Engine & Advisory Warning UX (PLANNED)
- Implement `DuplicateDetectionService` reusing Phase 1 GIS primitives (`GeohashService.getCandidatePrefixes` with max 16 ranges, `.limit(20)`), Unicode-preserving normalization, and deterministic scoring model.
- Implement `DuplicateWarningSheet` advisory UI showing top 3 candidates.
- Unit tests for similarity heuristics and global script fixtures (`東京駅 トイレ`, `مطار دبي حمام`, etc.); widget tests for modal display and button actions.

### P2.5 — End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback (PLANNED)
- Connect anonymous authentication lifecycle.
- Wire submit action through repository batch write with `CreateRestroomCommand`, stable ID, and ambiguous commit reconciliation.
- Sync successful submissions with canonical viewport refresh and preview selection.
- End-to-end integration and widget tests.

### P2.6 — Hardening, Accessibility, Abuse Rate-Limiting Gate & Validation (PLANNED)
- Audit touch targets (>= 48×48), semantic labels, and contrast.
- Verify production abuse rate-limiting release gate.
- Run complete test suite (`flutter test`, Firestore emulator rules tests).
- Validate platform compilation (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`).
- Update `docs/STATUS.md` and prepare Phase 2 for audit.

---

## Phase 2 Intentionally Excluded

Do not implement in this phase:

- photo uploads (Phase 5);
- ratings and reviews submission (Phase 3);
- verification and report submission (Phase 3);
- public restroom editing / updates (deferred to dedicated workflow);
- operating hours (deferred to dedicated availability feature);
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

- `dart format --output=none --set-exit-if-changed lib test` — PASS (clean, 78 files formatted)
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (248/248 passed: 232 prior regressions + 16 new P2.2 unit/widget tests)
- Firestore Security Rules emulator tests — PASS (49/49 passed: 29 Phase 2 tests + 20 Phase 0 legacy tests)
- `git diff --check` — PASS (clean, no trailing whitespace or formatting defects)
- Secrets scan — PASS (0 secrets or private keys in git tree)
- Firebase live discovery — NOT RUN; live device/owner config pending
- Google Maps live discovery — NOT RUN; live device/owner config pending

## Next recommended action

Perform independent exact-head audit of Milestone P2.2 on `phase-2/add-restroom`. P2.3 remains BLOCKED pending P2.2 audit.

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