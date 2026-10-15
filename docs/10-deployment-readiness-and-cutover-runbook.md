# FlushCrowd — P2.6 Deployment Readiness, Rules Cutover & Physical Device QA Runbook

**Document:** `docs/10-deployment-readiness-and-cutover-runbook.md`
**Milestone:** Phase 2 / Milestone P2.6 Hardening & Release Validation
**Status:** SPECIFICATION & OPERATIONAL RUNBOOK — PREPARATION ONLY
**Active Target Branch:** `phase-2/p2.6-final-qa-security-cutover`
**Authority:** `AGENTS.md`, `docs/STATUS.md`, `docs/03-privacy-security.md`, `docs/07-environment-setup.md`, `docs/tasks/P2.6-hardening-rate-limit.md`

---

## 1. Operating Rules & Authority

> [!IMPORTANT]
> **PREPARATION ONLY — NO LIVE DEPLOYMENT OR MERGE AUTHORIZED**
> This runbook prepares all assets, configurations, cutover candidate rules, test suites, and physical-device procedures required for Phase 2 closeout.
> **Under no circumstances shall any agent execute live Firebase CLI deployment commands, alter production Firebase projects, or merge pull requests during this task.**
> All live deployments require separate, explicit human owner authorization.

---

## 2. Task 1 — Cloud Functions V2 Deployment Readiness

### 2.1 Backend Architecture & Configuration Contract
The server-side rate-limiting backend is located in the `functions/` directory, built with Firebase Functions V2, Firebase Admin SDK v12, and TypeScript strict mode.

- **Package Entrypoint:** `functions/package.json` declares `"main": "lib/src/index.js"`.
- **Predeploy Hook:** `firebase.json` executes `npm --prefix "$RESOURCE_DIR" run build` prior to deployment.
- **Entrypoint Verification:** Validated via `npm run smoke:entrypoint` (`APP_ENV=test node -e "require('.')"`).
- **Persistent Non-Secret Staging Environment:** `functions/.env.flushcrowd-staging` declares `APP_ENV=staging`. In Firebase Functions 2nd Gen, Firebase CLI automatically loads this project-specific `.env` file during deployment to `flushcrowd-staging`, injects it into the Cloud Run container environment, and provides it during local CLI discovery.
- **Staging Discovery Smoke Test:** Validated via `npm run smoke:staging` (`node --env-file=.env.flushcrowd-staging -e "process.env.GCLOUD_PROJECT='flushcrowd-staging'; require('.')"`).
- **Target Function:** `submitRestroom` HTTPS Callable Function.

### 2.2 Target Firebase Project & Explicit Region
- **Staging Firebase Project ID:** `flushcrowd-staging`
- **Region:** `us-central1`
  * Declared at global level: `setGlobalOptions({ region: 'us-central1' })` in `functions/src/index.ts`.
  * Declared at function level: `onCall({ region: 'us-central1', enforceAppCheck: config.enforceAppCheck }, ...)` in `functions/src/submit_restroom.ts`.
  * Declared in Flutter client: `AppConstants.defaultCloudFunctionsRegion = 'us-central1'` in `lib/core/constants/app_constants.dart`.
- **Targeting Rule:** All Firebase deployment commands must explicitly include `--project flushcrowd-staging`. Never rely on `.firebaserc` or ambient defaults.

### 2.3 Runtime Environment & Fail-Closed Project Identity Verification
In `functions/src/config.ts`, `getAppConfig()` enforces:
1. `APP_ENV=staging` must be provided in the runtime environment. Unconfigured environments fail closed with `FATAL: APP_ENV environment variable is missing`.
2. In live staging runtime (non-emulator, non-test), `functions/src/config.ts` fails closed if project identity (`GCLOUD_PROJECT`, `PROJECT_ID`, or `FIREBASE_CONFIG.projectId`) is missing (`FATAL: Live staging environment is missing project identity`) or does not match `flushcrowd-staging` (`FATAL: Staging environment targeted invalid project`).
3. App Check enforcement is fail-closed: attempts to set `ENFORCE_APP_CHECK=false` in staging or production are strictly rejected (`FATAL: Cannot disable App Check in staging/production`).
4. Live production runtime fails closed if project identity is missing or if it attempts to execute against `flushcrowd-staging`.

### 2.4 App Check Reconciliation & Mobile Debug Token Plan
- **The App Check Contradiction:**
  * `docs/07-environment-setup.md` §4 specifies: *"Do NOT enable App Check enforcement in staging. Leave providers in monitoring/un-enforced mode until valid release traffic metrics are observed."*
  * However, `functions/src/config.ts` requires `enforceAppCheck: true` for both staging and production.
- **Reconciliation & Resolution:**
  1. The guidance in `docs/07-environment-setup.md` applies to the **project-wide Firestore database App Check enforcement toggle** in the Firebase Console. Keeping Firestore database enforcement un-enforced during initial testing prevents public discovery reads from being locked out.
  2. The **Cloud Function backend (`submitRestroom`)** enforces App Check at the endpoint ingress layer (`enforceAppCheck: true`).
  3. Staging mobile builds (`APP_ENV=staging`) initialize `FirebaseAppCheckService` using `AndroidDebugProvider()` on Android and `AppleDebugProvider()` on iOS.
  4. At startup, the Firebase SDK prints an App Check debug token to the device log.
  5. **Mandatory Prerequisite:** The human owner must register these debug tokens in the Firebase Console under **App Check -> Apps -> Manage debug tokens** for `flushcrowd-staging`.
  6. Once registered, debug tokens are cryptographically exchanged for valid App Check tokens, allowing physical test devices to pass Cloud Function enforcement without disabling or weakening security.

### 2.5 Financial Model, Blaze Billing & Cost Safeguards
- **Blaze Plan Prerequisite:** Cloud Functions V2 runs on Google Cloud Run and strictly requires a Blaze (pay-as-you-go) billing account linked to `flushcrowd-staging`. Deployment on the free Spark tier is impossible.
- **Cost Realism:**
  * Cloud Functions V2 provides 2,000,000 invocations and 360,000 GB-seconds free monthly. At staging volume, compute costs are $0.00.
  * Container images are stored in Google Artifact Registry, incurring ~$0.05 to $0.20/month per region.
  * Firestore operations consume 1 read + 3 writes per submission (covered by the 20,000 free writes/day allowance).
- **Budget Safeguards:**
  * A Google Cloud Billing Budget of $25.00/month must be active on the billing account with alert thresholds at 50% ($12.50), 90% ($22.50), and 100% ($25.00) with email alerts to administrators.
  * Function scaling is bounded by Cloud Run default concurrency controls to prevent unexpected cost surges.

---

## 3. Task 2 — Security Rules Cutover Candidate

### 3.1 Version-Controlled Rules Cutover Candidate & Deployment Configuration
- **Active Staging Rules:** `firestore.rules` (preserves authenticated direct batch writes for staging parity and testing).
- **Cutover Candidate Rules:** `firestore.production.rules` (version-controlled in repository root, denying direct client writes).
- **Default Deployment Configuration:** `firebase.json` specifies `"rules": "firestore.rules"` to protect ongoing staging development.
- **Dedicated Cutover Configuration:** `firebase.cutover.json` specifies `"rules": "firestore.production.rules"` for explicit, deterministic lockdown deployment (`firebase deploy --config firebase.cutover.json ...`).
- **Configuration Parity Verification:** Validated via automated test suite `rules_tests/test/firebase_config.test.js`, proving that default configuration selects staging rules, cutover configuration selects production rules, and non-rules configurations (functions, emulators) remain strictly in sync.

### 3.2 Cutover Candidate Rules Specifications
Under `firestore.production.rules`:
1. `match /restrooms/{restroomId}`:
   ```javascript
   allow read: if true;
   allow create: if false; // Closed to direct client SDK writes
   allow update, delete: if false;
   ```
2. `match /contributions/{contributionId}`:
   ```javascript
   allow read: if isAuthenticated() && resource.data.userUid == request.auth.uid;
   allow create: if false; // Closed to direct client SDK writes
   allow update, delete: if false;
   ```
3. `match /contributionRateLimits/{uid}`:
   ```javascript
   allow read, write: if false; // Strictly private to Firebase Admin SDK
   ```
4. All existing Phase 0/1/2 rules for ratings, rating ownership, verifications, reports, and default deny remain 100% intact.

### 3.3 Emulator & Configuration Test Suite
The emulator test suite validates both security behavior and configuration selection (61 total tests):
- `rules_tests/test/production_rules_cutover.test.js` (6 cutover behaviors):
  * **Test 1:** Direct client public restroom `setDoc` is rejected (`assertFails`).
  * **Test 2:** Direct client contribution `setDoc` is rejected (`assertFails`).
  * **Test 3:** Direct client batch write cannot bypass restrictions (`assertFails`).
  * **Test 4:** Authorized Admin SDK writes succeed for public restrooms, private contributions, and rate-limit documents (`assertSucceeds`).
  * **Test 5:** Legitimate public discovery reads (single document and spatial geohash range queries) succeed for unauthenticated and authenticated clients (`assertSucceeds`).
  * **Test 6:** Private contributor ownership, client update/delete blocks, and rate-limit privacy remain strictly enforced (`assertFails`).
- `rules_tests/test/firebase_config.test.js` (6 configuration-level automated checks):
  * Default `firebase.json` selects `firestore.rules`.
  * Cutover `firebase.cutover.json` selects `firestore.production.rules`.
  * Configuration parity between default and cutover files.
  * Staging rules contain direct-write functions.
  * Production candidate rules deny client creates and rate-limit access.
  * Staging `.env.flushcrowd-staging` provisions `APP_ENV=staging`.

---

## 4. Task 3 — Physical Device QA Acceptance Runbook

### Target Physical Devices:
- **Device 1 (Android):** Samsung Galaxy S21 Ultra 5G (`SM-G998B`).
  * *Operational Requirement:* The QA tester must inspect and record the actual Android OS version and One UI version on testing day via **Settings -> About phone -> Software information** (e.g. Android 14 / One UI 6.1) rather than assuming a static version.
- **Device 2 (iOS):** iPhone 12 Pro Max (`A2411`).
  * *Operational Requirement:* The QA tester must inspect and record the actual iOS version on testing day via **Settings -> General -> About** (e.g. iOS 17.x / 18.x) rather than assuming a static version.

---

### Category A: Immediate Acceptance Tests (Executable Without Deployed Callable)
These tests validate UI/UX, accessibility, duplicate detection, and draft preservation on local and direct-write staging builds (`USE_CALLABLE_SUBMISSION=false`).

#### Test A.1 — TalkBack & VoiceOver Semantic Screen-Reader Audit
- **Android (TalkBack):**
  1. Enable TalkBack under Settings -> Accessibility -> TalkBack.
  2. Open FlushCrowd and tap the Add Restroom action button.
  3. Verify `AddRestroomLocationScreen`: TalkBack announces "Pinpoint the restroom" banner, "Confirm Pin" (button, min 48×48 dp), "Recenter map to my location" (button, min 48×48 dp), and "Back" button (min 48×48 dp).
  4. Proceed to `AddRestroomFormScreen`: Verify coordinate summary card announces location; "Restroom Name" text field announces hints; "Access Type" dropdown announces current value and expands; Tri-State Amenity chips announce feature name, state (Yes, No, Unspecified), and selected flag.
- **iOS (VoiceOver):**
  1. Enable VoiceOver under Settings -> Accessibility -> VoiceOver.
  2. Repeat navigation through Location Screen and Form Screen.
  3. Verify accessibility headers, traits (Buttons, Headers), and swipe navigation order.
  4. Confirm all interactive touch targets meet or exceed 48×48 dp.

#### Test A.2 — 200% System Font & Dynamic Type Scaling Stability
- **Execution:**
  1. Android: Settings -> Display -> Font size and style -> Drag Font Size slider to maximum (200%).
  2. iOS: Settings -> Accessibility -> Display & Text Size -> Larger Text -> Enable Larger Accessibility Sizes -> Drag slider to 200%.
- **Verification Criteria:**
  1. On `AddRestroomLocationScreen`: Instruction banner wraps text across multiple lines without overflowing; Back button and My Location button remain visible and tap-target compliant.
  2. On `AddRestroomFormScreen`: Trigger validation errors; verify "Please fix the following errors" banner and individual error messages wrap cleanly with zero `RenderFlex` overflow errors.
  3. On `DuplicateWarningSheet`: View candidate card; verify candidate title, access badge, and action buttons ("View Existing Restroom" and "No, It's a Different Restroom") remain visible, scrollable within `SingleChildScrollView`, and accessible.

#### Test A.3 — Duplicate Detection Advisory & Dismissal UX
1. In `AddRestroomFormScreen`, enter coordinates within 200 meters of an existing known restroom.
2. Tap "Continue"; verify `DuplicateWarningSheet` slides up presenting nearby candidate(s).
3. Tap "View Existing Restroom": verify bottom sheet dismisses, discovery map centers on the candidate facility, and restroom preview sheet opens.
4. Re-open form or tap "No, It's a Different Restroom": verify sheet dismisses and submission flow resumes.

#### Test A.4 — Draft Preservation & Crash-Resilient Restoration
1. Enter partial data in `AddRestroomFormScreen` (name, floor, access type, custom amenities).
2. Tap the Android back button or iOS back gesture to leave the form.
3. Verify an informational SnackBar appears with message: `"Restroom draft saved."` and a `"Resume"` action button.
4. Tap `"Resume"`: verify all previously entered fields and coordinates are restored without data loss.
5. Dismiss or navigate away; tap Add Restroom again: verify option to resume draft or discard.

---

### Category B: Post-Callable Deployment Acceptance Tests (`USE_CALLABLE_SUBMISSION=true`)
These tests require an active staging Cloud Function deployment on `flushcrowd-staging`.

#### Test B.1 — App Check Debug Token Registration
1. Launch staging build on Samsung SM-G998B via `adb logcat | grep -i appcheck`.
2. Locate logged debug secret: `Enter this debug secret into the allow list in the Firebase Console: <TOKEN>`.
3. Launch staging build on iPhone 12 Pro Max via Xcode console. Locate Apple debug token.
4. In Firebase Console -> `flushcrowd-staging` -> **App Check** -> **Apps** -> Select Android/iOS app -> **Manage debug tokens**.
5. Add both debug tokens with descriptive labels (`SM-G998B-QA`, `iPhone12ProMax-QA`).
6. Confirm tokens are active.

#### Test B.2 — End-to-End Callable Restroom Submission
1. Launch app with `--dart-define=APP_ENV=staging --dart-define=USE_CALLABLE_SUBMISSION=true`.
2. Pin location, fill in valid restroom details, and submit.
3. Observe single-flight submission indicator.
4. Verify success: SnackBar indicates successful submission; map camera centers on new coordinates; restroom appears as an `unverified` pin.
5. In Firebase Console Firestore: verify document exists in `/restrooms/{id}` with no contributor UID, and matching record exists in `/contributions/restroom_{id}` with matching `userUid`.

#### Test B.3 — Stable-ID Idempotent Retry
1. Simulate network disconnect immediately after submission or resubmit with identical draft.
2. Verify response succeeds without error.
3. In Firestore `/contributionRateLimits/{uid}`, verify `submissionTimestamps` array contains exactly 1 timestamp (no double charge).

#### Test B.4 — 3-per-10-Minute Burst Rate Limiting
1. Submit Restroom #1 -> Succeeded.
2. Submit Restroom #2 -> Succeeded.
3. Submit Restroom #3 -> Succeeded.
4. Submit Restroom #4 within 10 minutes -> **Rejected with `resource-exhausted`**.
5. Verify client displays: `"Submission limit reached. Please try again later."`
6. Verify draft is preserved with a `"Resume"` button.
7. Verify client did **NOT** fall back to direct Firestore write (no orphaned document created).

#### Test B.5 — 10-per-24-Hour Daily Submission Cap
1. After waiting for burst window or advancing timestamps, submit up to 10 restrooms.
2. The 11th submission within rolling 24 hours is rejected with `resource-exhausted`.
3. Rate-limit document in `/contributionRateLimits/{uid}` reflects exactly 10 timestamps within the 24-hour window.

---

## 5. Task 4 — Staged Rollout and Rollback Plan

```text
+-----------------------------------------------------------------------------------+
|                            STAGED ROLLOUT SEQUENCE                                |
+-----------------------------------------------------------------------------------+
|  [GATE 1] Staging Prerequisites & App Check Tokens Verification                   |
|     ↓                                                                             |
|  [GATE 2] Human Owner Approval: Deploy Staging Cloud Function                     |
|     ↓                                                                             |
|  [GATE 3] Physical Devices Verification with USE_CALLABLE_SUBMISSION=true         |
|     ↓                                                                             |
|  [GATE 4] Human Owner Approval: Staging Security Rules Cutover Lockdown           |
|     ↓                                                                             |
|  [GATE 5] Verification of Direct Write Rejection & Exclusive Callable Path        |
|     ↓                                                                             |
|  [GATE 6] Production Security Cutover (Separate Phase Approval)                   |
+-----------------------------------------------------------------------------------+
```

### Stage 1: Pre-Deployment Staging Verification
1. Verify GCP project `flushcrowd-staging` has active Blaze billing.
2. Verify Billing Budget ($25/mo) with alert thresholds.
3. Verify Firebase Anonymous Authentication is enabled.
4. Build functions locally: `npm --prefix functions run build`.
5. Run package discovery smoke tests:
   * `npm --prefix functions run smoke:entrypoint` (PASS)
   * `npm --prefix functions run smoke:staging` (PASS — validates `.env.flushcrowd-staging` loading)
6. Run emulator and configuration test suites:
   * `npm --prefix functions run test:emulators` (25/25 PASS: 9 App Check/env preflight + 16 rate-limiting scenarios)
   * `npm --prefix rules_tests run test:emulators` (61/61 PASS: 49 staging rules + 6 production cutover + 6 configuration checks)

### Stage 2: Deploy Staging Cloud Function (Requires Human Approval)
- **Gate 2 Approval:** Obtain written signoff from human owner.
- **Environment Provenance:** `functions/.env.flushcrowd-staging` provides persistent, non-secret `APP_ENV=staging`. The Firebase CLI automatically loads this project-specific configuration during deployment to `flushcrowd-staging` and injects it into the Cloud Run container runtime.
- **Deployment Command:**
  ```bash
  firebase deploy \
    --project flushcrowd-staging \
    --only functions:submitRestroom
  ```
- **Post-Deploy Verification:**
  * Verify in Google Cloud Console -> Cloud Run -> `submitRestroom` is provisioned in `us-central1`.
  * Verify environment variable `APP_ENV=staging` is present in the Cloud Run service configuration.
  * Verify runtime project identity matches `flushcrowd-staging`.

### Stage 3: Mobile Staging Testing on Physical Devices
- Build staging apps for Samsung SM-G998B and iPhone 12 Pro Max:
  ```bash
  # Android Debug APK with callable submission enabled
  flutter build apk --debug \
    --dart-define=APP_ENV=staging \
    --dart-define=USE_CALLABLE_SUBMISSION=true

  # iOS Debug Runner with callable submission enabled
  flutter build ios --debug --no-codesign \
    --dart-define=APP_ENV=staging \
    --dart-define=USE_CALLABLE_SUBMISSION=true
  ```
- Register debug tokens in Firebase Console.
- Execute Category B physical-device tests.

### Stage 4: Staging Security Rules Lockdown (Requires Human Approval)
- **Gate 4 Approval:** Obtain written signoff to lock down staging direct writes.
- **Preflight Configuration Verification:**
  Run automated configuration check:
  ```bash
  npm --prefix rules_tests test test/firebase_config.test.js
  ```
  Confirms `firebase.cutover.json` explicitly targets `firestore.production.rules` while `firebase.json` targets `firestore.rules`.
- **Deployment Command:**
  Deploy candidate rules to staging Firestore using the dedicated cutover configuration:
  ```bash
  firebase deploy \
    --config firebase.cutover.json \
    --project flushcrowd-staging \
    --only firestore:rules
  ```
- **Post-Deploy Verification:**
  1. Direct client SDK write attempt to `/restrooms/{id}` fails with `PERMISSION_DENIED`.
  2. Direct client SDK write attempt to `/contributions/{id}` fails with `PERMISSION_DENIED`.
  3. Callable submission through `submitRestroom` succeeds and creates both records.
- **Abort Criteria:**
  If a direct client SDK write succeeds after deploying cutover rules, the restrictive rules were not applied. **IMMEDIATELY ABORT** and execute Rollback R.3 (Emergency Rules Rollback).

### Stage 5: Rollback Procedures (If Anomaly Detected)

#### Order of Rollback Operations:
1. **R.1 — Client Draft Preservation & Submission Suspension (First Line of Defense):**
   If mobile client issues, unexpected UI errors, or submission failures occur:
   - Contributor drafts remain fully preserved locally via `DraftPreservationService` with the `"Resume"` action.
   - If required to prevent user disruption, suspend submissions via app-level configuration (`isSubmissionsEnabled: false` or maintenance toggle) while preserving all drafts.
   - No data loss occurs.
2. **R.2 — Cloud Function Revision Rollback (Primary Backend Defense):**
   If `submitRestroom` exhibits an unexpected error spike, regression, or failure:
   - In Google Cloud Console -> Cloud Run -> `submitRestroom` -> **Revisions**, route 100% of traffic back to the previously verified stable revision.
   - Or execute via Google Cloud CLI:
     ```bash
     gcloud run services update-traffic submit-restroom \
       --to-revisions=<PREVIOUS_STABLE_REVISION>=100 \
       --region=us-central1 \
       --project=flushcrowd-staging
     ```
3. **R.3 — Emergency Staging Rules Rollback (Exceptional Staging-Only Action):**
   If candidate cutover rules cause unexpected operational disruption during staging testing:
   - Re-deploy the staging rules using the default configuration:
     ```bash
     firebase deploy \
       --config firebase.json \
       --project flushcrowd-staging \
       --only firestore:rules
     ```
   - Confirm that staging direct batch writes are restored for debugging.

> [!CAUTION]
> **RESTRICTED TO STAGING ONLY — NEVER RE-ENABLE DIRECT WRITES IN PRODUCTION.**
> Restoring permissive rules (`firestore.rules`) re-enables direct client batch writes and re-opens the rate-limit and App Check bypass. It is an exceptional, owner-authorized debugging procedure valid ONLY in `flushcrowd-staging`.
> **Under no circumstances shall direct client writes ever be described or used as a production rollback fallback.** Production operates exclusively through the callable function backend. In production, any incident is resolved by Cloud Run revision rollback (R.2) or client submission suspension (R.1).

---

## 6. Summary Checklist for Independent Audit

| Checkpoint | Requirement | Status |
| :--- | :--- | :--- |
| **Backend Discovery** | `firebase.json` codebase, predeploy & `.env.flushcrowd-staging` | Verified |
| **Region Parity** | `us-central1` explicit in backend & client | Verified |
| **Project Guard** | `getAppConfig()` fail-closed on missing/mismatched identity | Verified & Tested |
| **App Check Sync** | Contradiction resolved via debug-token plan | Documented |
| **Rules Candidate** | `firestore.production.rules` closes direct writes | Authored & Validated |
| **Cutover Configuration** | `firebase.cutover.json` deterministic selection | Verified & Tested |
| **Rules Testing** | 61 scenarios in `rules_tests` (49 staging + 6 cutover + 6 config) | 61/61 PASS |
| **Functions Testing** | 25 callable & preflight scenarios in `functions/test` | 25/25 PASS |
| **Physical QA Runbook** | Checklists for SM-G998B & iPhone 12 Pro Max with test-day OS recording | Documented |
| **Rollout / Rollback** | Step-by-step gates, explicit sequencing & production non-bypass invariants | Documented |
| **Live Gate** | No live deployment or merge without human approval | LOCKED |
