# FlushCrowd — Project Status

> Current-state coordination file for humans and AI agents. Keep this concise and update it at every meaningful handoff. Detailed history belongs in Git commits and PRs.

- **Last updated:** 2026-10-07
- **Project:** FlushCrowd — global community-powered restroom finder
- **Repository:** `mrdzyn/flushcrowd`
- **Overall stage:** Staging Environment Readiness / Phase 2 Preparation
- **Current phase:** Phase 2 — Add Restroom
- **Current milestone:** Staging repository configuration wiring complete; external Firebase/Maps provisioning and live QA pending owner verification
- **Current branch:** `chore/flushcrowd-staging-readiness`
- **Current PR:** [#6](https://github.com/mrdzyn/flushcrowd/pull/6) — `chore: prepare FlushCrowd staging environment`
- **Base:** `main` at `60ed8096ee1bc132c4a6144943a735e164ca86f0` (includes PR #5 product rename squash merge)
- **Implementation status:** Phase 0 [MERGED]; Phase 1 [MERGED]; Phase 2 [ACTIVE]; P2.0 [APPROVED — PASS 0/0/0]; P2.1 [APPROVED — PASS 0/0/0]; P2.2 [APPROVED — PASS 0/0/0, merged into main]; Product Rename [MERGED — PASS 0/0/0]; Staging Readiness [ACTIVE / CONFIGURATION WIRING COMPLETE]; P2.3 [NOT STARTED — blocked pending live staging verification].

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

### Staging Environment Readiness [ACTIVE / CONFIGURATION WIRING COMPLETE]
- Defined canonical staging resource contract in `docs/07-environment-setup.md` (`flushcrowd-staging`, `com.flushcrowd.flushcrowd`).
- Wired executable Android Firebase integration: declared `com.google.gms.google-services` (4.4.2) in `settings.gradle.kts` and conditionally applied in `build.gradle.kts` when `google-services.json` is present; credential-free builds succeed when absent.
- Wired executable iOS Firebase integration: added `Copy GoogleService-Info.plist` build phase in `project.pbxproj` copying into the application bundle when present; credential-free builds succeed when absent.
- Wired executable Android Maps integration: `android/local.properties` (`MAPS_API_KEY`) via Gradle manifest placeholder with `DEFAULT_MAPS_API_KEY` fallback.
- Wired executable iOS Maps integration: `ios/Flutter/Secrets.xcconfig` (`GOOGLE_MAPS_API_KEY`) via `Debug.xcconfig` / `Release.xcconfig` to `Info.plist` (`GoogleMapsApiKey`) and `AppDelegate.swift`.
- Cleaned up dead configuration: converted `.env.example` to truthful configuration matrix reference; removed unused maps key and debug token fields from `AppConfig`.
- Aligned App Check providers: development & staging use Debug providers, production uses Play Integrity / App Attest.
- Hardened `.gitignore` to protect `Secrets.xcconfig`, `google-services.json`, `GoogleService-Info.plist`, `local.properties`, `key.properties`, `*debug-token*`, and `.env*`.
- Documented explicit-scoped staging deployment command (`firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes`) and corrected 20-step human activation sequence.
- Documented 11-point acceptance criteria for unblocking Milestone P2.3.
- External cloud provisioning and live QA pending owner verification.

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management [NOT STARTED — blocked pending live staging verification]
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

## External staging environment state

Owner-confirmed staging infrastructure state:
- Firebase project `flushcrowd-staging` — CREATED
- Android Firebase app `com.flushcrowd.flushcrowd` — REGISTERED
- iOS Firebase app `com.flushcrowd.flushcrowd` — REGISTERED
- `google-services.json` — DOWNLOADED; local placement/verification pending unless independently confirmed
- `GoogleService-Info.plist` — DOWNLOADED; local placement/verification pending unless independently confirmed
- Anonymous Authentication — ENABLED
- Anonymous account automatic cleanup — ENABLED
- Cloud Firestore — CREATED
- Maps SDK for Android — ENABLED
- Maps SDK for iOS — ENABLED
- Android restricted Maps key — PENDING
- iOS restricted Maps key — PENDING
- App Check live/debug verification — NOT RUN
- Firestore Rules/index staging deployment — NOT RUN
- Android live staging QA — NOT RUN
- iOS live staging QA — NOT RUN

## Current owner actions / external dependencies

Remaining human owner actions required for live staging QA and P2.3 acceptance gate:

1. Verify downloaded Firebase config files (`google-services.json` and `GoogleService-Info.plist`) are placed in their documented local gitignored paths:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
2. Create and restrict Android Maps API key in Google Cloud Console:
   - Application restriction: Android apps (`com.flushcrowd.flushcrowd` + staging/debug SHA-1)
   - API restriction: **Maps SDK for Android** only
3. Create and restrict iOS Maps API key in Google Cloud Console:
   - Application restriction: iOS apps (`com.flushcrowd.flushcrowd`)
   - API restriction: **Maps SDK for iOS** only
4. Configure local native Maps key files (outside version control):
   - Add `MAPS_API_KEY=<restricted-android-key>` to `android/local.properties`
   - Add `GOOGLE_MAPS_API_KEY=<restricted-ios-key>` to `ios/Flutter/Secrets.xcconfig`
5. Run Android and iOS staging builds locally and perform live QA.
6. Verify Firebase initialization and Anonymous Authentication in the live staging project.
7. Verify App Check debug-token workflow (token emitted in runtime console registered in Firebase Console).
8. After explicit owner approval, deploy audited Firestore Rules and indexes using:
   ```bash
   firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes
   ```
9. Verify Firestore read connectivity under the deployed staging rules.
10. Establish and publish external donation/support URL (`AppConstants.buyMeACoffeeUrl`) and privacy policy URL (`AppConstants.privacyPolicyUrl`).
11. Configure GCP billing budget alerts.
12. Production Android signing remains a later release-readiness action.

## Current validation status

- `dart format --output=none --set-exit-if-changed lib test` — PASS
- `flutter analyze` — PASS (0 issues found)
- `flutter test` — PASS (260/260 passed)
- Firestore Security Rules emulator tests — PASS (49/49 passed: 29 Phase 2 tests + 20 Phase 0 legacy tests)
- `flutter build apk --debug` without credentials — PASS
- `flutter build ios --debug --no-codesign` without credentials — PASS
- `git diff --check` — PASS
- Secrets scan — PASS (0 secrets or private keys in git tree)
- Exact-head CI (`FlushCrowd CI`) — PASS (all 4 GitHub Actions checks passed on exact head)

## Next recommended action

Human owner to complete remaining external setup steps (verify local Firebase config placement, generate restricted Maps keys, run live staging QA, and deploy audited rules via `firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes`) to satisfy the 11-point staging acceptance gate and unblock Milestone P2.3.

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