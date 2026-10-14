# FlushCrowd — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

- **Last updated:** 2026-10-14
- **Project:** FlushCrowd — global community-powered restroom finder
- **Repository:** `mrdzyn/flushcrowd`
- **Overall stage:** Phase 2 Add Restroom
- **Current phase:** Phase 2 Add Restroom
- **Current milestone:** Milestone P2.5 End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback — AWAITING PR #12 MERGE
- **Current branch:** `phase-2/p2.5-submission`
- **Current PR:** #12 — P2.5 submission & discovery sync implementation (https://github.com/mrdzyn/flushcrowd/pull/12)
- **Base:** `main` at `91ee2612ac5c855da0719a346dc6d16ea7e4d6ee` (PR #10 P2.4 squash merge)
- **Implementation status:** Phase 0 [MERGED]; Phase 1 [MERGED; Explore Tab Hotfix MERGED — PR #9]; Phase 2 [ACTIVE]; P2.0 [APPROVED — PASS 0/0/0]; P2.1 [APPROVED — PASS 0/0/0]; P2.2 [APPROVED — PASS 0/0/0, merged into main]; Product Rename [MERGED — PASS 0/0/0]; Staging Readiness [MERGED — PR #6]; P2.2 Navigation Hotfix [MERGED — PR #7]; P2.3 [APPROVED & MERGED into main at `9cc4b9b779d510de7b73561804443cc21f6454f9`]; P2.4 [MERGED — PR #10 at `91ee2612ac5c855da0719a346dc6d16ea7e4d6ee`]; P2.5 [QA PASS — AWAITING OWNER MERGE]; P2.6 [READY TO START].

## Current objective

Implement and validate **P2.5** on branch `phase-2/p2.5-submission`, following `docs/tasks/P2.5-submission-map-sync.md` and canonical `docs/09-phase-2-add-restroom.md`.

- Wire existing P2.4 validated `CreateRestroomCommand` + advisory duplicate flow to the P2.1 `FirestoreRestroomRepository.submitRestroom()` atomic public/private batch.
- Authenticate anonymously before submitting; prevent false successful saves when staging Firebase fails initialization (`firebase-init-failed` exception in offline in-memory fallback).
- Enforce production contribution write block until P2.6 enforceable per-UID rate limiting.
- Keep one exact command/restroom ID through recoverable failures, retries, and reconciliation; provide clear disabled/loading/success/error feedback.
- On remote success, clear draft, show success message with advisory scan note, navigate to map at zoom 16.5, force canonical viewport refresh, select by authoritative discovered `restroomId`, show one `Unverified` preview; strictly zero optimistic or synthetic insertion.
- Surface recovery action (`Refresh`) if authoritative query omits newly created facility.
- 37 automated regression tests in `test/presentation/p2_5_submission_map_sync_test.dart` (plus 6 unit tests in `test/presentation/auth_notifier_test.dart`) covering safety gates, single-flight submission, live anonymous session restoration, recoverable retries, and authoritative map synchronization.

The active specification is:

- `docs/09-phase-2-add-restroom.md` (active Phase 2 specification)

## Locked decisions

- Product name: **FlushCrowd**.
- Canonical brand marks: `docs/assets/brand/flushcrowd-icon.png` (icon) and `docs/assets/brand/flushcrowd-horizontal.png` (horizontal lockup).
- Canonical UI reference: `docs/assets/flushcrowd-mobile-ux-reference.png`.
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

### Product & Repository Rename [MERGED]
Squash-merged into `main` at `60ed8096ee1bc132c4a6144943a735e164ca86f0` (PR #5).
- Controlled rename from LooRadar / looradar to FlushCrowd / flushcrowd.
- Android package / namespace: `com.flushcrowd.flushcrowd`.
- iOS bundle identifier: `com.flushcrowd.flushcrowd`.
- Canonical brand marks: `docs/assets/brand/flushcrowd-icon.png` and `docs/assets/brand/flushcrowd-horizontal.png`.
- Native launcher assets generated for Android (mipmap-*) and iOS (AppIcon.appiconset).
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

### P2.1 — Contribution Domain Model (`RestroomDraft`), Nullable Schema Migration, Repository Batch Write Contract, Firestore Rules & Emulator Tests [APPROVED — PASS 0 BLOCKER / 0 MAJOR / 0 MINOR]
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

### P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX [APPROVED — PASS 0 BLOCKER / 0 MAJOR / 0 MINOR]
- Implemented `AddRestroomLocationScreen` with interactive Google Map and fixed center crosshair / target pin overlay (`_buildCenterTargetIndicator`).
- Selected facility coordinate represented strictly via canonical `Coordinates` domain model (`lib/domain/models/coordinates.dart`).
- Enforced zoom floor (`zoom >= 15.0`) with visual precision hint: `"Zoom in to place the restroom more precisely."` and disabled Continue action until zoom floor is met, camera is idle, and no programmatic move is pending.
- Displayed live formatted coordinate readouts (5 decimal places, e.g. `14.58390, 121.06170`) via `Coordinates`.
- Camera movement updates lightweight visual state (`_isCameraMoving`) without triggering persistence or queries; camera idle commits target coordinates.
- "Use my location" button moves camera and updates selection if available; manual map selection remains fully functional when GPS is unavailable.
- Remediated MAJOR-1: Fresh foreground-location attempt directly queries `LocationRepository.getCurrentLocation()`, explicitly distinguishing location service disabled, permission denied/permanently denied, and retrieval failure/timeout without consuming stale cached coordinates from `LocationNotifier`. Manual map placement remains fully functional.
- Remediated MAJOR-2 (Initial & Residual): Introduced `MapCameraController` interface (`animateCamera`, `moveCamera`) and `GoogleMapCameraController` adapter. Completely decoupled actual camera state (`_actualCameraTarget`, `_actualCameraZoom`) from programmatic desired destinations via `_ProgrammaticCameraIntent`. Initialized `_initialCameraPosition` once in `initState` so widget rebuilds do not pass pending coordinates to the native map constructor. Enforced that premature `onCameraIdle` events (before real movement frames) do not clear pending intents or falsely commit unreached coordinates. Handled identical-destination edge cases and camera command failures with non-blocking user notices and manual panning recovery. `_canConfirm` disables Continue while any programmatic move is pending.
- Remediated MINOR-1: Fixed test 13 safe-area assertion to derive boundary from `screenSize.height - viewPadding.bottom` rather than a magic number.
- Remediated MINOR-2: Injected `CountingRestroomRepository` into Provider tree via `createTestWidget` so that accidental Firestore queries/submissions are observable by tests.
- Remediated MINOR-3: Synchronized `docs/STATUS.md` line 100 P2.1 heading to `[APPROVED — PASS 0 BLOCKER / 0 MAJOR / 0 MINOR]`.
- Clean navigation seam returning `Coordinates` via callback and `Navigator.pop`.
- Authored 25 unit and widget tests in `test/presentation/add_restroom_location_screen_test.dart` covering all prompt criteria, edge cases, and remediation assertions.
- Validated full Flutter test suite (257 total Flutter tests, all PASS).
- Validated all 49 Firestore Security Rules tests under Firestore emulator.
- Merged into `main` at `2b58a79c22182d8213b0c625b0de69b1daf623c5`.

### Staging Environment Readiness [MERGED — PR #6]
- Squash-merged into `main` at `76e8669c1646667c7a1e6484d643b9d949a8846d` (PR #6).
- Defined canonical staging resource contract in `docs/07-environment-setup.md` (`flushcrowd-staging`, `com.flushcrowd.flushcrowd`).
- Wired executable Android Firebase integration: declared `com.google.gms.google-services` (4.4.2) in `settings.gradle.kts` and conditionally applied in `build.gradle.kts` when `google-services.json` is present; credential-free builds succeed when absent.
- Wired executable iOS Firebase integration: added `Copy GoogleService-Info.plist` build phase in `project.pbxproj` copying into the application bundle when present; credential-free builds succeed when absent.
- Wired executable Android Maps integration: `android/local.properties` (`MAPS_API_KEY`) via Gradle manifest placeholder with `DEFAULT_MAPS_API_KEY` fallback.
- Wired executable iOS Maps integration: `ios/Flutter/Secrets.xcconfig` (`GOOGLE_MAPS_API_KEY`) via `Debug.xcconfig` / `Release.xcconfig` to `Info.plist` (`GoogleMapsApiKey`) and `AppDelegate.swift`.
- Cleaned up dead configuration: converted `.env.example` to truthful configuration matrix reference; removed unused maps key and debug token fields from `AppConfig`.
- Aligned App Check providers: development & staging use Debug providers, production uses Play Integrity / App Attest.
- Hardened `.gitignore` to protect sensitive local credentials and secrets.
- Documented explicit-scoped staging deployment command (`firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes`) and corrected 20-step human activation sequence.
- Independent PR #6 exact-head audit passed: 0 BLOCKER / 0 MAJOR / 0 MINOR.

### P2.2 — Add Restroom Navigation Entry Hotfix [MERGED — PR #7]
- Squash-merged into `main` at `ebb9c746e65cc9902a49cfaf96f9bc3e4ffcaf86` (PR #7).
- Discovered during Android live staging QA: tapping bottom-navigation **Add** tab (index 2) mounted `_PhasePlaceholderScreen` instead of opening the implemented P2.2 `AddRestroomLocationScreen`.
- Preserved `MainShellScreen` architecture while treating Add as an action entry point pushing `AddRestroomLocationScreen.route()`.
- Replaced `IndexedStack` placeholder at index 2 with non-placeholder `SizedBox.shrink()`.
- Protected against rapid duplicate taps stacking routes (`_isOpeningAddLocation`).
- Remediated MAJOR-1: Preserved discovery map camera target by capturing continuous camera movement in `MapDiscoveryScreen` without triggering rebuilds, and passing it as `initialCoordinates` to `AddRestroomLocationScreen.route()`. Preserved device GPS / default fallback when no discovery target has been captured.
- Handled coordinate confirmation by returning `Coordinates` and navigating to the contribution form.
- Cancel/back pops route and returns cleanly to prior shell tab preserving state.
- Authored 10 focused widget tests in `test/presentation/main_shell_navigation_test.dart` verifying all behaviors, camera target preservation, fallback intactness, and zero Firestore operations on entry/exit.
- Manual human QA: PASS on Android, PASS on iOS.

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management [MERGED — PR #8]
- Squash-merged into `main` at `9cc4b9b779d510de7b73561804443cc21f6454f9` (PR #8).
- Implemented `AddRestroomFormScreen` (`lib/presentation/screens/add_restroom_form_screen.dart`) with organized card sections (Facility Identification with compact read-only coordinate display, Indoor Directions & Context, Accessibility & Stalls, Hygiene & Amenities, Access Instructions & Pricing).
- Implemented accessible, reusable `TriStateAmenitySelector` (`lib/presentation/components/inputs/tri_state_amenity_selector.dart`) with min 48×48 touch targets, semantic labels, text scaling, checkmark visual indicators beyond color, and nullable boolean adapter.
- Implemented `AddRestroomNotifier` (`lib/presentation/state/add_restroom_notifier.dart`) managing raw editable state, constructing `RestroomDraft`, validating via `draft.normalized().validate()`, and allocating stable restroom ID only upon valid preparation.
- Implemented `RestroomIdGenerator` and `DefaultRestroomIdGenerator` (`lib/presentation/state/restroom_id_generator.dart`) producing 20-character alphanumeric IDs without network reads.
- Remediated MAJOR-1: Synchronized fee controllers and notifier state across access type transitions (`Paid` → non-paid → `Paid`), ensuring controllers are cleared when hidden and genuinely empty when reappearing, with domain normalization clearing fee data for non-paid commands.
- Remediated MAJOR-2: Preserved nullable data truth during command normalization: missing/unknown amenities normalize to null rather than being coerced to false.
- Wired P2.2 → P2.3 navigation in `MainShellScreen`: location confirmation opens `AddRestroomFormScreen`, valid continue prepares `CreateRestroomCommand` in memory and displays honest temporary validation notice without claiming submission, and cancel/back pops cleanly with zero writes.
- Zero-persistence milestone: 0 Firestore writes, 0 Firestore reads, 0 Places/Geocoding calls, no personal data or contributor UID collected.
- Independent audit passed: 0 BLOCKER / 0 MAJOR / 0 MINOR.

### Phase 1 — Explore Restrooms Experience Restoration [MERGED — PR #9]
- Resolved Phase 1 unfinished navigation seam: bottom-navigation **Explore** tab (index 1) previously mounted a placeholder claiming Phase 1 was unbuilt.
- Implemented `ExploreRestroomsScreen` (`lib/presentation/screens/explore_restrooms_screen.dart`) providing rich list discovery, searching, and filtering on top of Phase 1 discovery state.
- Zero new network queries: consumes `MapDiscoveryNotifier` and `LocationNotifier` with 0 Firestore reads triggered by tab navigation, searching, or filtering.
- Extended `RestroomSummaryCard` with optional contextual parameters (`showFullContext`, `showAccessType`, `showAmenities`, `showVerification`, `onInfoTap`, `now`) while defaulting all to false/null for 100% backward compatibility.
- Comprehensive lifecycle handling:
  - Loading: Centered `LooLoadingIndicator` when results are empty during query.
  - Degraded results: Non-blocking warning banner when safety caps are reached (`isDegraded`).
  - Error with retained prior results: Non-blocking error banner with retry action (`retryLastViewportQuery()`).
  - Error without prior results: Centered `ErrorStateView` with retry action.
  - Zoom-in suppressed: `EmptyStateView` prompting zoom-in with "View Map" CTA (`onSwitchToMap`).
  - Filter/search empty: `EmptyStateView` distinguishing search-only, filter-only, and search+filters with dedicated reset actions.
  - Geographic empty: `EmptyStateView` when 0 facilities exist in area with "Explore on Map" CTA.
  - Loaded results: Scrollable list sorted deterministically via `RestroomSorting.sort`, displaying full context (building name, floor, landmark, status chip, access type chip, amenity icons, verified badge).
- Tap selection synchronization: Tapping a restroom card selects the facility in `MapDiscoveryNotifier`, switches active tab to Map (`_currentTabIndex = 0`), and displays the preview card on the map.
- Remediated MAJOR-1: Replaced unconditional `Verified` badge in `RestroomSummaryCard` with truthful verification freshness semantics reusing canonical `DiscoveryFilters.recentVerificationThreshold` (90 days). Fresh verifications (`lastVerifiedAt` within 90 days, non-future) display green `Recently verified`. Older verifications (> 90 days) or count-only verifications (`verificationCount > 0` with null timestamp) display neutral `Previously verified`. Unverified facilities render no verification badge. Future timestamps are not treated as recent.
- Remediated MINOR-1: Updated `RestroomSummaryCard` `onInfoTap` `IconButton` constraints from `minWidth: 40, minHeight: 40` to `minWidth: 48, minHeight: 48` satisfying the repository minimum interactive touch target accessibility rule.
- Authored 18 unit and widget tests in `test/presentation/explore_restrooms_screen_test.dart` and 1 additional navigation/tab-switch test in `test/presentation/main_shell_navigation_test.dart` (317 total Flutter tests, all PASS).

### P2.4 — Bounded Duplicate Detection Engine & Advisory Warning UX [MERGED — PR #10]
- Squash-merged into `main` at `91ee2612ac5c855da0719a346dc6d16ea7e4d6ee` (PR #10).
- Implemented `DuplicateDetectionService` reusing Phase 1 GIS primitives (`GeohashService.getCandidatePrefixes` with max 16 ranges, `.limit(20)`), Unicode-preserving normalization, and deterministic scoring model.
- Implemented `DuplicateWarningSheet` advisory UI showing top 3 candidates with distance and similarity chips.
- Non-blocking advisory warning with continue, view existing, and cancel actions; safe draft preservation across flows.

### P2.5 — End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback [ACTIVE]
- **Active Audited Candidate:** PR #12 (`phase-2/p2.5-submission`).
- **Overlapping Older Candidate:** PR #11 (`phase-2/p2.5-submission-map-sync`) remains open awaiting human owner disposition (do not merge, close, or audit without owner approval).
- **PR #12 Audit Remediation:**
  - **MAJOR-1 — Restore anonymous session on every submission attempt:**
    - In `MainShellScreen._submitRestroom`, eliminated sole reliance on cached `AuthNotifier.isAuthenticated`.
    - Unconditionally verifies and ensures live anonymous session via `authNotifier.ensureAnonymousSession()` before every attempted write (including retries).
    - Fails closed if the required authentication provider is unavailable (`authNotifier == null`), preserving draft command/coordinates and displaying truthful retry feedback.
    - Preserves synchronous `_isSubmitting = true` single-flight lock before any asynchronous authentication operation (preserving Test B.4).
    - On auth failure: does not submit, preserves identical command and restroom ID, shows truthful recovery SnackBar with `Retry`, and never allocates a new restroom ID.
    - Updated `AuthNotifier` to listen to live `authStateChanges`, clear `_userId` on errors, and unconditionally invoke `_authRepository.ensureAnonymousSession()`.
    - Automated tests: Tests A.9, A.10, A.11 in `p2_5_submission_map_sync_test.dart` and 6 unit tests in `auth_notifier_test.dart`.
  - **MAJOR-2 — Reconcile canonical status across competing PR candidates:**
    - Documented PR #12 on branch `phase-2/p2.5-submission` as the active audited candidate.
    - Documented PR #11 as an overlapping older candidate awaiting owner disposition; removed stale instructions directing next agent to audit or merge PR #11.
  - **MINOR-1 — Preserve advisory scan note on retry:**
    - Forwarded `advisoryScanNote` through recoverable error and retry paths in `MainShellScreen._handleSubmissionFailure` and `onAction`.
    - Stored `_preservedDraftAdvisoryScanNote` on draft preservation and cleared on successful submission or explicit draft abandonment.
    - Retry does not repeat duplicate scans unnecessarily; preserves incomplete or fail-open advisory note on successful retry (Tests D.8, D.9).
  - **m1 — Submission Error UX:**
    - Replaced raw backend error exposure in `MainShellScreen._handleSubmissionFailure` with concise, user-friendly error messages without exposing sensitive Firebase details.
    - Distinguishes expired authentication (`'Authentication session expired. Please check your connection and try again.'`), permission failures (`'Submission rejected by server permissions. Please ensure your session is valid.'`), App Check verification failures (`'App verification failed. Please ensure you are using the official app.'`), authorization failures (`'Authorization failed. Please ensure your session is valid and try again.'`), network problems (`'Connection failed. Please check your internet connection.'`), and unclassified errors (`'Unable to save restroom. Please try again.'`).
    - Preserves exact pending `CreateRestroomCommand`, `restroomId`, draft coordinates, and recovery options (`Retry`/`Resume`); never shows success when persistence fails.
    - Added regression tests D.10 through D.14 in `test/presentation/p2_5_submission_map_sync_test.dart`.
  - **m2 — Documentation Alignment:**
    - Updated `docs/tasks/P2.5-submission-map-sync.md` with active candidate branch (`phase-2/p2.5-submission`), active status, and required staging execution command (`flutter run --dart-define=APP_ENV=staging`).
    - Updated `docs/07-environment-setup.md` with required staging command (`flutter run --dart-define=APP_ENV=staging`), documenting that unknown or missing `APP_ENV` values fail closed and disable submissions, and that staging requires the configured `flushcrowd-staging` Firebase project.
  - **m3 — PR Description Metadata:**
    - Updated PR #12 description with latest implementation HEAD, total Flutter test count (422), P2.5 regression test count (42), anonymous authentication test count (6), independent audit status, and outstanding owner physical-device staging QA requirements.
  - **N1 — Accurate Audit Status in Documentation:**
    - Corrected `docs/tasks/P2.5-submission-map-sync.md` to accurately reflect audit history without premature 0/0/0 claims: previous audit PASS WITH MINORS (0/0/3) at `de692b5`; remediation at `ece86b9`; latest independent re-audit PASS WITH MINORS (0/0/2); N1/N2 documentation fixes pending verification; code eligible for owner-authorized physical-device staging QA.
  - **N2 — Accurate Environment Mapping Documentation:**
    - Accurately documented `Environment.fromString()` behavior across `docs/tasks/P2.5-submission-map-sync.md` and `docs/07-environment-setup.md`: missing `APP_ENV` defaults to `development`, explicit `development` maps to `development`, unrecognized values map to `unknown` (not `development`), neither `development` nor `unknown` permits contribution submission, and staging submissions strictly require both `APP_ENV=staging` and Firebase project `flushcrowd-staging`.
    - Removed nonexistent quoted error message strings.
- **Prior Findings Remediated:**
  - **BLOCKER-1 — Staging-only Write Safety:** Fail-closed gate requires `config.isStaging` AND `firebaseProjectId == 'flushcrowd-staging'`; tested default/dev/unknown/prod/mismatched configurations (Tests A.4–A.8).
  - **MAJOR-1 — Authoritative Map Refresh Timing:** Coordinates camera settlement with coordinate containment and target zoom verification; tested C.3–C.7.
  - **MAJOR-2 — Submission Single-Flight Lock:** Synchronously acquires `_isSubmitting = true` before awaiting anonymous auth or async stages; tested concurrency with deferred auth (Test B.4).
  - **MINOR-1 — Inaccurate Error Handling:** Distinct error classification for permission-denied, invalid draft, invariant violations; map focus initiation error recovery.
- **P2.5 Testability & Quality Checks:**
  - Expanded `test/presentation/p2_5_submission_map_sync_test.dart` to 42 regression tests (covering A.1–A.11, B.1–B.4, C.1–C.13, D.1–D.14).
  - Authored 6 unit tests in `test/presentation/auth_notifier_test.dart`.
  - Full test suite: 422 Flutter tests pass (0 failures), 49/49 Firestore rules pass, `flutter analyze` 0 warnings, `dart format` clean.
- **Owner Physical-Device Staging QA Findings:**
  - Samsung SM-G998B Android: PASS for adding restrooms and duplicate advisory.
  - Johnmikel Xavier's iPhone: PASS for adding restrooms and duplicate advisory.
  - Pending Pre-Production Staging Verification:
    1. Cross-device visibility & discovery query synchronization (Android-added restroom visible on iOS and vice versa).
    2. Authoritative camera settlement & preview card rendering (zoom 16.5 settlement and Unverified preview without optimistic local state).
    3. Cloud Firestore public/private document pair integrity (matching `/restrooms/{id}` with `status == 'unverified'` and no UID, and `/contributions/restroom_{id}` with `moderationState == 'pending'` and contributor UID).
- **Overlapping PR Disposition:** PR #11 (`phase-2/p2.5-submission-map-sync`) is superseded by PR #12 (`phase-2/p2.5-submission`); awaits human owner action to squash-merge PR #12 into `main` and close PR #11 without merge.

### P2.6 — Hardening, Accessibility, Abuse Rate-Limiting Gate & Validation [PLANNED]
- **Abuse Rate-Limiting Gate:** Enforce server-side per-UID rate limiting (maximum 10 restroom submissions per UID per rolling 24 hours; maximum burst 3 submissions per UID per rolling 10 minutes) before opening production contribution writes. Architectural evaluation confirms Option A (Trusted Cloud Function V2 with transactional array filtering on private rate-limit document) as the only design satisfying rolling windows and atomic OCC concurrency without violating Firestore rules quotas. Closes the direct-write bypass by migrating production Firestore rules to require the trusted server boundary. Detailed task specification authored in `docs/tasks/P2.6-hardening-rate-limit.md`.
- **Accessibility (a11y) Audit:** Audit touch targets (>= 48×48 dp), semantic labels, high contrast (>= 4.5:1), and dynamic text scaling (up to 200%) across all Phase 2 screens (`AddRestroomLocationScreen`, `AddRestroomFormScreen`, `TriStateAmenitySelector`, `DuplicateWarningSheet`).
- **Platform Builds & Static Analysis:** Validate `flutter build apk --debug`, `flutter build ios --debug --no-codesign`, `flutter analyze` (0 issues), and `dart format`.
- **Validation Suite:** Run complete Flutter test suite (422+ tests) and Firestore Security Rules emulator suite (49+ tests).
- **Independent Audit:** Submit for independent 0/0/0 audit to formally close Phase 2.

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

## External staging environment state

Owner-confirmed staging infrastructure state:
- Firebase project `flushcrowd-staging` — CREATED
- Android Firebase app `com.flushcrowd.flushcrowd` — REGISTERED
- iOS Firebase app `com.flushcrowd.flushcrowd` — REGISTERED
- `google-services.json` — DOWNLOADED & PLACED
- `GoogleService-Info.plist` — DOWNLOADED & PLACED
- Anonymous Authentication — ENABLED
- Anonymous account automatic cleanup — ENABLED
- Cloud Firestore — CREATED
- Maps SDK for Android — ENABLED
- Maps SDK for iOS — ENABLED
- Android restricted Maps key — CONFIGURED
- iOS restricted Maps key — CONFIGURED
- Android live staging QA:
  - Firebase initialization — PASS
  - Maps rendering — PASS
  - App Check Debug registration — PASS
  - Firestore backend reached — PASS
  - P2.2 navigation & camera target preservation — PASS
- iOS live staging QA:
  - App launch — PASS
  - Maps rendering — PASS
  - App Check Debug registration — PASS
  - P2.2 navigation & camera target preservation — PASS
- Backend:
  - Firestore Rules/indexes deployment to `flushcrowd-staging` — PASS
- Firestore authorized reads:
  - Post-deployment runtime verification — PASS (previous `PERMISSION_DENIED` no longer occurs)
- Milestone P2.3 gate:
  - MERGED into main (`9cc4b9b779d510de7b73561804443cc21f6454f9`)
  - Manual human QA: PASS on Android, PASS on iOS
- Phase 1 Explore tab restoration:
  - MERGED into main (`ce04479bd3b69ca9b3bc342854583f8ff7544330`, PR #9)
  - Manual human QA: PASS on Android, PASS on iOS
- Milestone P2.4 (Duplicate Detection):
  - SQUASH-MERGED — PR #10, `91ee2612ac5c855da0719a346dc6d16ea7e4d6ee`
  - Owner physical-device QA Test 1 PASS on Samsung SM G998B Android and iPhone 12 Pro Max iOS.
  - QA Test 2 reconciled & unblocked following P2.5 staging contribution writes.
- Milestone P2.5:
  - ACTIVE AUDITED CANDIDATE: PR #12 on branch `phase-2/p2.5-submission`.
  - Overlapping older candidate: PR #11 (`phase-2/p2.5-submission-map-sync`) remains open awaiting human owner disposition (do not merge, close, or audit without owner instruction).
  - Task contract: `docs/tasks/P2.5-submission-map-sync.md`.
  - All 42 P2.5 automated regression tests pass (plus 6 unit tests in `auth_notifier_test.dart`); all 422 Flutter tests pass; 49/49 Firestore rules pass.
  - Owner physical-device QA: PASS on Samsung SM-G998B Android and iPhone (Johnmikel Xavier) for add restroom and duplicate advisory sheet.
  - Pending Pre-Production Staging Verification: Cross-device query sync, camera settlement to zoom 16.5 & preview rendering, and Firestore Console document pair integrity.
  - Disposition: Awaiting human owner squash-merge of PR #12 into `main` and closure of PR #11 without merge.

## Current owner actions / external dependencies

1. Establish and publish external donation/support URL (`AppConstants.buyMeACoffeeUrl`) and privacy policy URL (`AppConstants.privacyPolicyUrl`).
2. Configure GCP billing budget alerts.
3. Production Android signing remains a later release-readiness action.
4. Authorize squash-merge of PR #12 and closure of PR #11.
5. Review and approve proposed Phase Re-Ordering Architecture accelerating Phase 4 (Moderation & Facility Operations) ahead of Phase 3 (Community Ratings & Reporting).

## Current validation status

Milestone P2.5 PR #12 audit-remediation exact-head validation:

- `dart format --output=none --set-exit-if-changed lib test` — PASS (0 changed)
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (422/422 tests passed: 42 tests in `p2_5_submission_map_sync_test.dart` + 6 tests in `auth_notifier_test.dart` + 30 tests in `duplicate_detection_service_test.dart` + 6 tests in `duplicate_warning_sheet_test.dart` + 18 tests in `main_shell_navigation_test.dart` + 11 tests in `map_focus_navigation_test.dart` + 16 tests in `add_restroom_notifier_test.dart` + 54 tests in `firestore_restroom_repository_test.dart` + full existing suite)
- Firestore Security Rules emulator tests — PASS (49/49 tests passed: `npm --prefix rules_tests run test:emulators`)
- `git diff --check` — PASS
- Secrets scan — PASS (0 secrets or private keys in git tree)

## Next recommended action

1. Human owner to squash-merge PR #12 (`phase-2/p2.5-submission`) into `main`.
2. Human owner to close overlapping PR #11 (`phase-2/p2.5-submission-map-sync`) without merge.
3. Complete pending physical-device QA verification (cross-device discovery sync, camera settlement, Firestore document pair check).
4. Create branch `phase-2/p2.6-hardening` from updated `main` to implement Milestone P2.6 (enforceable rate-limiting gate, a11y audit, platform compilation).
5. Human owner to review and approve proposed Phase Re-Ordering Architecture accelerating Phase 4 (Moderation & Facility Operations) ahead of Phase 3 (Community Ratings & Reporting).

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