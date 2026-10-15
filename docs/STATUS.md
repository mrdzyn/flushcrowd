# FlushCrowd — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

- **Last updated:** 2026-10-15
- **Project:** FlushCrowd — global community-powered restroom finder
- **Repository:** `mrdzyn/flushcrowd`
- **Overall stage:** Phase 2 Add Restroom
- **Current phase:** Phase 2 Add Restroom
- **Current milestone:** Milestone P2.6-F/G Accessibility Audit, Remediation & Platform Release Validation — COMPLETED
- **Current branch:** `phase-2/p2.6-fg-accessibility-platform-validation`
- **Current PR:** #15 — P2.6-F/G Accessibility & Platform Validation (https://github.com/mrdzyn/flushcrowd/pull/15)
- **Base:** `main` at `059fefbba63b8adad6c2887dccd20f910c8068d9` (squash-merge of PR #14)
- **Implementation status:** Phase 0 [MERGED]; Phase 1 [MERGED]; Phase 2 [ACTIVE]; P2.0 [APPROVED — PASS 0/0/0]; P2.1 [APPROVED — PASS 0/0/0]; P2.2 [APPROVED — PASS 0/0/0, merged into main]; Product Rename [MERGED — PASS 0/0/0]; Staging Readiness [MERGED — PR #6]; P2.2 Navigation Hotfix [MERGED — PR #7]; P2.3 [APPROVED & MERGED into main]; P2.4 [MERGED — PR #10]; P2.5 [MERGED — PR #12]; P2.6-A [MERGED — PR #13]; P2.6-B [MERGED — PR #14]; P2.6-F [COMPLETED]; P2.6-G [COMPLETED].

## Current objective

Complete and validate **P2.6-F** (Accessibility audit & remediation) and **P2.6-G** (Platform compilation & release validation) on branch `phase-2/p2.6-fg-accessibility-platform-validation`, based on `main` at `059fefbba63b8adad6c2887dccd20f910c8068d9`:

- **P2.6-F — Accessibility (a11y) Audit & Remediation:** [COMPLETED]
  * **Touch Targets (>= 48x48 dp):** Migrated `LooPrimaryButton` and `LooSecondaryButton` from fixed `SizedBox(height: ...)` to `ConstrainedBox(constraints: BoxConstraints(minHeight: ...))` with 16x12 padding; verified `MapRecenterButton` (48x48) and `TriStateOptionButton` (minHeight 48.0, width >= 48.0).
  * **Screen Reader Semantics & Announcements:**
    - `TriStateAmenitySelector`: Option button sets `excludeSemantics: true` with clean announcement `"$title, $option"` and selection flag; decorative title icon excluded from semantics; `maxLines: 2` allows text wrapping without ellipsis at 200% scale.
    - `AddRestroomFormScreen`: Added `Semantics(header: true)` on card titles for heading navigation; excluded decorative icons from semantics; wrapped validation error banner in `Semantics(liveRegion: true)` for immediate TalkBack/VoiceOver announcement on failure.
    - `DuplicateWarningSheet`: Excluded decorative warning icon, added `Semantics(header: true)` on warning header, added explicit `label: 'View existing restroom: ${restroom.name}'` on candidate card action button.
    - `MainShellScreen`: Excluded submission progress `CircularProgressIndicator` from semantics so only 'Submitting restroom...' is announced without raw progress control stutter.
  * **Color Contrast (WCAG 2.1 AA >= 4.5:1):** Remediated `DuplicateWarningSheet` access badge from `AppColors.textSecondary` (4.28:1) to `AppColors.textPrimary` (12.4:1 contrast ratio against `surfaceVariant`).
  * **200% Text Scaling Stability:**
    - `AddRestroomLocationScreen`: AppBar bottom instruction banner calculates dynamic preferred size adapting to `textScaler`; coordinate readout row migrated from rigid Row to responsive `Wrap`, eliminating 3.7px right overflow.
    - `AddRestroomFormScreen`: `DropdownButtonFormField` configured with `isExpanded: true`; fee amount and currency fields utilize `LayoutBuilder` stacking into a `Column` when text scale is high (>= 1.5) or narrow, preventing overflow.
  * **Automated Accessibility Tests:** Added 12 new dedicated widget tests in `test/presentation/p2_6_accessibility_test.dart` locking in touch targets, semantics, contrast, and 200% text scaling stability.
- **P2.6-G — Platform Compilation & Release Validation:** [COMPLETED]
  * `flutter build apk --debug` — PASS (`✓ Built build/app/outputs/flutter-apk/app-debug.apk` in 83.1s)
  * `flutter build ios --debug --no-codesign` — PASS (`✓ Built build/ios/iphoneos/Runner.app` in 77.1s)
  * Full Flutter test suite: 448/448 tests passed (0 failures).
  * Functions smoke and App Check isolated tests: 4/4 tests passed.
  * Firestore rules emulator test suite: 49/49 tests passed.
  * Cloud Functions emulator test suite: 20/20 tests passed.

The active specifications are:

- `docs/tasks/P2.6-hardening-rate-limit.md` (active P2.6 task specification)
- `docs/03-privacy-security.md` (abuse-control release gate & contribution controls)
- `docs/09-phase-2-add-restroom.md` (Phase 2 specification)

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

### P2.5 — End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback [MERGED — PR #12]
- Squash-merged into `main` at `ce208ee6be4364ad5fd39364d596725548c525b9` (PR #12).
- Overlapping PR #11 closed without merge.
- Owner physical-device QA: PASS on Samsung SM-G998B Android and iPhone (Johnmikel Xavier) for add restroom and duplicate advisory sheet.
- All 42 P2.5 automated regression tests pass (plus 6 unit tests in `auth_notifier_test.dart`); full test suite (422 Flutter tests, 49 Firestore rules tests) passing.

### P2.6 — Production Abuse Rate-Limiting Gate, Accessibility Audit & Release Validation [ACTIVE]
- **Active Branch:** `phase-2/p2.6-hardening`
- **Base:** `main` at `ce208ee6be4364ad5fd39364d596725548c525b9`
- **P2.6-A Rate-Limiting Backend & Direct-Write Bypass Prevention [FINAL AUDIT REMEDIATION COMPLETE]:**
  - Scaffolded `functions/` TypeScript Cloud Functions V2 project (Node 20/22, `firebase-functions` v5.1.1, `firebase-admin` v12.7.0, `firebase-tools` v13.31.0, TypeScript 5.6 strict mode).
  - Implemented `submitRestroom` callable backend with server-authoritative validation, canonical Base32 geohash calculation, atomic OCC transaction on `/contributionRateLimits/{uid}`, locked rate limits (10/24h rolling daily, 3/10m rolling burst), timestamp array pruning, stable-ID idempotency retry, ID collision defense, and strict public privacy exclusion of contributor UIDs.
  - **BLOCKER-1 Remediated (Package Entrypoint Packaging):**
    * Corrected `functions/package.json` `"main"` field from `lib/index.js` to `lib/src/index.js` matching emitted TypeScript layout.
    * Added `smoke:entrypoint` npm script (`APP_ENV=test node -e "require('.')"`).
    * Added CI smoke test step to `.github/workflows/ci.yml` (`APP_ENV=test node -e "require('./functions')"`) executing after TypeScript compilation.
  - **MAJOR-1 Remediated (Idempotency Integrity & Private Linkage Invariants):**
    * Implemented `matchesCanonicalSubmission` in `functions/src/submit_restroom.ts` comparing core identifiers, coordinates, access types, fees, location descriptors, and nullable amenities against existing public documents.
    * Enforced full private contribution linkage verification during stable-ID reconciliation: validates `id === 'restroom_' + restroomId`, `contributionType === 'restroom'`, `resourceId === restroomId`, `restroomId === restroomId`, `userUid === uid`, and public `id === restroomId`.
    * Rejects modified payloads and mismatched/corrupted linkage invariants with `already-exists` without charging rate limits or mutating existing documents.
    * Validated via Scenarios 7a, 7b, 7c, 7d, and 7e.
  - **MAJOR-2 & MINOR-1 Remediated (App Check Fail-Closed Configuration & Initialization Evidence):**
    * Implemented `getAppConfig()` in `functions/src/config.ts` enforcing strict configuration validation.
    * Staging and production strictly enforce App Check (`enforceAppCheck: true`); attempting to disable App Check in staging/production throws a fatal error.
    * Missing `APP_ENV` outside test/emulator environments fails closed.
    * Implemented `createSubmitRestroom(config)` factory and added isolated test suite in `functions/test/app_check_init.test.ts`.
    * Proved SDK-level transport rejection: callable initialized in staging and production rejects HTTP requests without `X-Firebase-AppCheck` with HTTP 401 `UNAUTHENTICATED` at ingress before any handler logic runs.
    * Validated via `app_check_init.test.ts` (4/4 tests passed) and Scenarios 9b and 9c.
  - **MAJOR-3 Remediated (CI Coverage):**
    * Updated `.github/workflows/ci.yml` adding canonical `functions` job ("Cloud Functions Build & Emulator Tests") executing Node 22, Java 17, `npm --prefix functions ci`, `npm --prefix functions run build`, package entrypoint smoke test, and `npm --prefix functions run test:emulators`.
    * Added `firebase-tools` devDependency to `functions/package.json` for self-contained CI execution.
  - **MINOR-1 Remediated (Production Rules Evidence & Staging Parity):**
    * Documented explicit distinction between the inline proposed production rules test (Scenario 10) and root `firestore.rules`.
    * Root `firestore.rules` is deliberately NOT modified in this checkpoint, preserving staging parity and backward compatibility during P2.6-B development.
    * Proved that direct client SDK writes under proposed production rules fail with `PERMISSION_DENIED` while Cloud Function Admin SDK writes succeed, conclusively closing the direct-write bypass without deploying rules to live infrastructure.
  - **Comprehensive Emulator Test Suites (20 tests across 2 suites, all PASS):**
    * *App Check Callable Initialization Contract (`app_check_init.test.ts`):*
      1. Staging environment initializes callable with SDK-level App Check enforcement enabled -> PASS
      2. Production environment initializes callable with SDK-level App Check enforcement enabled -> PASS
      3. Development environment with enforceAppCheck=false allows SDK-level pass-through -> PASS
      4. Staging and Production configurations strictly reject attempts to disable App Check -> PASS
    * *Rate Limiting & Abuse Prevention (`rate_limit.test.ts`):*
      1. Initial Submission -> PASS
      2. Rolling 10-Minute Burst Limit -> PASS
      3. Rolling 24-Hour Daily Limit -> PASS
      4. Boundary Timestamps -> PASS
      5. Timestamp Pruning -> PASS
      6. Concurrent Submissions (OCC serialization) -> PASS
      7a. Identical retry succeeds without consuming quota -> PASS
      7b. Same UID, same ID, modified contents fails and rejects payload mutation -> PASS
      7c. Existing private contribution without public restroom (orphaned private) fails safely -> PASS
      7d. Existing public restroom without matching private contribution (orphaned public) fails safely -> PASS
      7e. Same UID, same ID, corrupted/mismatched private linkage invariants fails safely -> PASS
      8. Document ID Collision -> PASS
      9. Forged / Missing Identity & Malformed Input -> PASS
      9b. App Check enforcement fails closed when enabled and missing valid token -> PASS
      9c. getAppConfig fails closed on unconfigured or insecure deployment settings -> PASS
      10. Direct Write Bypass Prevention under Proposed Production Rules -> PASS
- **Next Sub-Milestones:**
  - P2.6-B: Flutter `CallableFirestoreMutationAdapter` connecting `FirestoreRestroomRepository` to `submitRestroom` callable backend with fail-closed semantics.
  - P2.6-F: Accessibility audit of Phase 2 screens (touch targets >= 48×48 dp, semantics, 200% text scaling).
  - P2.6-G: Debug platform compilation (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`).

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
  - SQUASH-MERGED into `main` at `ce208ee6be4364ad5fd39364d596725548c525b9` (PR #12).
  - Overlapping older candidate PR #11 closed without merge.
  - All 42 P2.5 automated regression tests passed; 422 total Flutter tests passed; 49/49 Firestore rules tests passed.
  - Owner physical-device QA: PASS on Samsung SM-G998B Android and iPhone (Johnmikel Xavier) for add restroom and duplicate advisory sheet.
  - Pending Pre-Production Staging Verification: Cross-device query sync, camera settlement to zoom 16.5 & preview rendering, and Firestore Console document pair integrity.
- Milestone P2.6-A:
  - SQUASH-MERGED into `main` at `05ad76b3a20af18f83df69d552bb2c30f3958087` (PR #13).
  - Backend rate limiting with Cloud Functions V2 (`submitRestroom`), 10/24h and 3/10m rolling limits, OCC transactional rate-limit tracking, stable-ID idempotency reconciliation, ID collision rejection, and direct-write bypass prevention.
- Milestone P2.6-B:
  - ACTIVE on branch `phase-2/p2.6-b-callable-integration` based on `main` at `05ad76b3a20af18f83df69d552bb2c30f3958087`.
  - Added `cloud_functions: ^6.5.0` dependency; defined `AppConstants.defaultCloudFunctionsRegion = 'us-central1'`.
  - Added `useCallableSubmission` flag to `AppConfig` (defaults to `false`, configurable via compile-time define or constructor).
  - Introduced `RestroomSubmissionTransport` boundary with `DirectFirestoreRestroomSubmissionTransport` and `CallableRestroomSubmissionTransport`.
  - Implemented `CallableRestroomSubmissionTransport` serializing commands without sentinels, contributor UIDs, trusted aggregates, or status (backend authoritative).
  - Preserved existing staging direct-write default for zero disruption until explicit cutover.
  - Enforced `production-writes-blocked` in `FirestoreRestroomRepository`.
  - Zero direct-write fallback: failed callable never falls back to direct Firestore writes.
  - Comprehensive exception mapping (`resource-exhausted` -> `rate-limited`, `unauthenticated`, `permission-denied`/`failed-precondition` -> `app-check-failed`, `already-exists`, `unavailable`/`deadline-exceeded`).
  - Ambiguous network timeout verification via complete public/private document pair verification (`contributions/restroom_{id}` and `restrooms/{id}`) matching canonical command and contributor UID via `validateReconciliationPair`.
  - Authoritative callable response validation (`validateCallableResponse`) checking `success == true`, ID match, canonical attributes match, valid types, and status `unverified`.
  - Full UX preservation: single-flight submission lock, duplicate advisory notes, draft recovery with preserved stable ID, Resume dialog action, authoritative map refresh at zoom 16.5, single Unverified preview bottom sheet, and independent discovery verification without false optimistic preview.
  - Milestone P2.6-F/G (Accessibility Audit & Platform Release Validation):
  - ACTIVE / COMPLETED on branch `phase-2/p2.6-fg-accessibility-platform-validation` based on `main` at `059fefbba63b8adad6c2887dccd20f910c8068d9`.
  - Audited and remediated 5 screens/components: `AddRestroomLocationScreen`, `AddRestroomFormScreen`, `TriStateAmenitySelector`, `DuplicateWarningSheet`, `MainShellScreen`, and button primitives (`LooPrimaryButton`, `LooSecondaryButton`).
  - Enforced minimum 48x48 dp touch targets with flexible `ConstrainedBox` container scaling.
  - Corrected screen reader semantics, header roles, live regions, and excluded decorative icons.
  - Remediated contrast on `DuplicateWarningSheet` access badge from 4.28:1 to 12.4:1 (`AppColors.textPrimary`).
  - Fixed 200% text scaling across all Phase 2 screens; resolved 3.7px RenderFlex overflow on location screen coordinate readout via responsive `Wrap`.
  - Added dedicated test suite `test/presentation/p2_6_accessibility_test.dart` (12 tests).
  - Executed full suite of 448 Flutter tests, 49 Firestore rules tests, 20 Functions emulator tests, and verified `flutter build apk --debug` and `flutter build ios --debug --no-codesign`.

## Current owner actions / external dependencies

1. Establish and publish external donation/support URL (`AppConstants.buyMeACoffeeUrl`) and privacy policy URL (`AppConstants.privacyPolicyUrl`).
2. Configure GCP billing budget alerts for Cloud Functions V2 / Artifact Registry.
3. Production Android signing remains a later release-readiness action.
4. Review and approve proposed Phase Re-Ordering Architecture accelerating Phase 4 (Moderation & Facility Operations) ahead of Phase 3 (Community Ratings & Reporting).
5. Deploy `submitRestroom` Cloud Function to live staging environment prior to flipping `useCallableSubmission: true` in staging.
6. Conduct physical device VoiceOver (iOS) and TalkBack (Android) qualitative testing of Phase 2 contribution workflow.

## Current validation status

Milestone P2.6-F/G exact-head validation:

- `dart format --output=none --set-exit-if-changed lib test` — PASS (0 changed)
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (448/448 tests passed, +12 new accessibility tests)
- `flutter test test/presentation/p2_6_accessibility_test.dart` — PASS (12/12 a11y tests passed)
- Functions package entrypoint smoke test: `npm --prefix functions run smoke:entrypoint` — PASS
- TypeScript build: `npm --prefix functions run build` — PASS (0 errors)
- Functions isolated App Check test suite: `APP_ENV=test node --test functions/lib/test/app_check_init.test.js` — PASS (4/4 tests passed)
- Firestore rules emulator test suite: `npm --prefix rules_tests run test:emulators` — PASS (49/49 tests passed)
- Functions emulator test suite: `npm --prefix functions run test:emulators` — PASS (20/20 tests passed)
- Android debug build: `flutter build apk --debug` — PASS (`✓ Built build/app/outputs/flutter-apk/app-debug.apk` in 83.1s)
- iOS debug build: `flutter build ios --debug --no-codesign` — PASS (`✓ Built build/ios/iphoneos/Runner.app` in 77.1s)
- `git diff --check` — PASS
- Secrets scan — PASS (0 secrets or private keys in git tree)

## Next recommended action

1. Push `phase-2/p2.6-fg-accessibility-platform-validation` branch to remote origin.
2. Open Pull Request on GitHub against `main`.
3. Submit for independent audit review.
4. Conduct manual physical device screen-reader QA (VoiceOver / TalkBack) with owner.

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