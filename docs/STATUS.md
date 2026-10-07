# FlushCrowd — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

- **Last updated:** 2026-10-08
- **Project:** FlushCrowd — global community-powered restroom finder
- **Repository:** `mrdzyn/flushcrowd`
- **Overall stage:** Phase 2 Add Restroom / Contribution Form Implementation
- **Current phase:** Phase 2 — Add Restroom
- **Current milestone:** P2.3 — Contribution Form UI, Data-Truth Validation & State Management [ACTIVE — implementation complete pending independent audit]
- **Current branch:** `phase-2/p2.3-contribution-form`
- **Current PR:** TBD
- **Base:** `main` at `ebb9c746e65cc9902a49cfaf96f9bc3e4ffcaf86` (includes PR #7 Add-entry hotfix squash merge)
- **Implementation status:** Phase 0 [MERGED]; Phase 1 [MERGED]; Phase 2 [ACTIVE]; P2.0 [APPROVED — PASS 0/0/0]; P2.1 [APPROVED — PASS 0/0/0]; P2.2 [APPROVED — PASS 0/0/0, merged into main]; Product Rename [MERGED — PASS 0/0/0]; Staging Readiness [MERGED — PR #6]; P2.2 Navigation Hotfix [MERGED — PR #7]; P2.3 [ACTIVE]; P2.4 [NOT STARTED].

## Current objective

Establish and document executable staging environment configuration following the completed product and repository rename:
- **Android Firebase Integration:** Declared `com.google.gms.google-services` plugin (4.4.2) in `settings.gradle.kts` and applied it conditionally in `build.gradle.kts` when `android/app/google-services.json` is present. Preserves credential-free builds in CI and local dev when absent.
- **iOS Firebase Integration:** Added deterministic `Copy GoogleService-Info.plist` Xcode build phase in `Runner.xcodeproj/project.pbxproj` copying `ios/Runner/GoogleService-Info.plist` to the application bundle when present. Preserves credential-free builds when absent.
- **Android Maps Wiring:** Bound `android/local.properties` (`MAPS_API_KEY`) through Gradle `manifestPlaceholders["MAPS_API_KEY"]` to `AndroidManifest.xml` with safe `DEFAULT_MAPS_API_KEY` fallback.
- **iOS Maps Wiring:** Bound `ios/Flutter/Secrets.xcconfig` (`GOOGLE_MAPS_API_KEY`) through `Debug.xcconfig` / `Release.xcconfig` to `Info.plist` (`GoogleMapsApiKey`) and consumed in `AppDelegate.swift` with safe default check.
- **Configuration Hygiene & Truth:** Updated `.env.example` as an informational reference matrix (no runtime dotenv loading). Removed dead Dart maps key and App Check token fields from `AppConfig`.
- **App Check Alignment:** Configured Debug providers for `development` and `staging` (`!config.isProduction`), and Play Integrity / App Attest for `production`. Documented standard debug token console workflow.
- **Scoped Deployment & Correct Activation Order:** Documented explicit project flag (`firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes`) and corrected human activation sequence to deploy audited rules before connectivity verification.
- **Gitignore Protection:** Strengthened `.gitignore` patterns ensuring `google-services.json`, `GoogleService-Info.plist`, `local.properties`, `key.properties`, `Secrets.xcconfig`, `*debug-token*`, and `.env*` cannot be committed across any directory depth.
- **Security & Integrity Preservation:** Production contribution writes remain guarded by the P2.6 abuse rate-limiting release gate. Offline development fallback is preserved and validated.

The active specification is:

- `docs/09-phase-2-add-restroom.md`

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

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management [ACTIVE — implementation complete pending independent audit]
- Implemented `AddRestroomFormScreen` (`lib/presentation/screens/add_restroom_form_screen.dart`) with organized card sections (Facility Identification with compact read-only coordinate display, Indoor Directions & Context, Accessibility & Stalls, Hygiene & Amenities, Access Instructions & Pricing).
- Implemented accessible, reusable `TriStateAmenitySelector` (`lib/presentation/components/inputs/tri_state_amenity_selector.dart`) with min 48×48 touch targets, semantic labels, text scaling, checkmark visual indicators beyond color, and nullable boolean adapter.
- Implemented `AddRestroomNotifier` (`lib/presentation/state/add_restroom_notifier.dart`) managing raw editable state, constructing `RestroomDraft`, validating via `draft.normalized().validate()`, and allocating stable restroom ID only upon valid preparation.
- Implemented `RestroomIdGenerator` and `DefaultRestroomIdGenerator` (`lib/presentation/state/restroom_id_generator.dart`) producing 20-character alphanumeric IDs without network reads.
- Wired P2.2 → P2.3 navigation in `MainShellScreen`: location confirmation opens `AddRestroomFormScreen`, valid continue prepares `CreateRestroomCommand` in memory and displays honest temporary validation notice without claiming submission, and cancel/back pops cleanly with zero writes.
- Zero-persistence milestone: 0 Firestore writes, 0 Firestore reads, 0 Places/Geocoding calls, no personal data or contributor UID collected.
- Manual device QA for P2.3: PENDING.
- Authored 27 new unit and widget tests: 15 in `test/presentation/add_restroom_notifier_test.dart`, 12 in `test/presentation/add_restroom_form_screen_test.dart`, plus updated navigation tests in `test/presentation/main_shell_navigation_test.dart` (297 total Flutter tests, all PASS).

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
  - UNBLOCKED / ACTIVE

## Current owner actions / external dependencies

1. Establish and publish external donation/support URL (`AppConstants.buyMeACoffeeUrl`) and privacy policy URL (`AppConstants.privacyPolicyUrl`).
2. Configure GCP billing budget alerts.
3. Production Android signing remains a later release-readiness action.

## Current validation status

- `dart format --output=none --set-exit-if-changed lib test` — PASS (86 files checked, 0 changed)
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (297/297 passed)
- Firestore Security Rules emulator tests — PASS (49/49 passed: 29 Phase 2 tests + 20 Phase 0 legacy tests)
- `flutter build apk --debug` without credentials — PASS
- `flutter build ios --debug --no-codesign` without credentials — PASS
- `git diff --check` — PASS
- Secrets scan — PASS (0 secrets or private keys in git tree)

## Next recommended action

1. Open PR `feat: implement P2.3 contribution form and state` against `main`.
2. Await exact-head GitHub CI completion.
3. Conduct independent exact-head audit for Milestone P2.3.
4. Following audit pass and merge, proceed to Milestone P2.4 (Bounded Duplicate Detection Engine & Advisory Warning UX).

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