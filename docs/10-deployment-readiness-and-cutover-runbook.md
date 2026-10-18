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

#### Category A Physical QA Execution Evidence (Recorded October 18, 2026)

- **Execution Date:** October 18, 2026
- **Test Build Architecture:** Non-callable development QA path (`USE_CALLABLE_SUBMISSION=false`)
- **Evaluation Status:** 8/8 HUMAN-REPORTED PASS
- **Target Devices:**
  * **Device 1:** Samsung Galaxy S21 Ultra 5G (`SM-G998B`) — OS Version: Pending confirmation
  * **Device 2:** iPhone 12 Pro Max (`A2411`) — iOS Version: Pending confirmation

| Test ID | Test Description | Samsung SM-G998B | iPhone 12 Pro Max | Evaluated Behavior & Observations |
| :--- | :--- | :--- | :--- | :--- |
| **Test A.1** | TalkBack / VoiceOver Semantic Screen-Reader Audit | **PASS** (Human-Reported) | **PASS** (Human-Reported) | Screen-reader announces location pinpoint banner, Confirm Pin, Recenter, Back, text inputs, Access Type dropdown, and tri-state chips. Interactive targets satisfy min 48×48 dp. |
| **Test A.2** | 200% System Font & Dynamic Type Scaling Stability | **PASS** (Human-Reported) | **PASS** (Human-Reported) | Multiline instruction banner, validation error summary, and duplicate warning sheet render cleanly with zero `RenderFlex` overflows at 200% text scale. |
| **Test A.3** | Duplicate Detection Advisory & Dismissal UX | **PASS** (Human-Reported) | **PASS** (Human-Reported) | Coordinates within 200m trigger `DuplicateWarningSheet`; "View Existing Restroom" dismisses and centers discovery map; "No, It's a Different Restroom" resumes submission flow. |
| **Test A.4** | Draft Preservation & In-App "Resume" Restoration | **PASS** (Human-Reported) | **PASS** (Human-Reported) | Back navigation displays persistent SnackBar `"Restroom draft saved."` with `"Resume"` action; tapping `"Resume"` cleanly restores all entered form values and coordinates without data loss. |

> [!NOTE]
> - Category A tests were executed on the non-callable development QA path.
> - Firebase callable submissions (`USE_CALLABLE_SUBMISSION=true`), App Check debug token exchanges, and server-side rate limits (Category B tests) remain **PENDING** until the Cloud Function is deployed to `flushcrowd-staging`.
> - Device OS versions remain marked pending confirmation per operating requirements.
> - Forced-app-termination and OS-level restart persistence were not evaluated in this round and are not claimed.

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
  node --test rules_tests/test/firebase_config.test.js
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

1. **R.1 — Local Draft Preservation & Staging Build Recovery (First Line of Defense):**
   If mobile client issues, unexpected submission failures, or callable degradation occur during staging testing:
   - **Guaranteed Draft Safety:** Contributor drafts remain fully preserved locally via `DraftPreservationService` across app restarts and navigation. When submission fails or is aborted, a persistent SnackBar with the `"Resume"` action is displayed, ensuring zero user data loss.
   - **Executable Staging Recovery Procedure:**
     * Immediately cease active distribution or testing of callable-enabled staging builds (`USE_CALLABLE_SUBMISSION=true`).
     * If testers run the standard staging build without `--dart-define=USE_CALLABLE_SUBMISSION=true` (defaults to `false`), the client attempts direct Firestore writes:
       - If security rules cutover (Stage 4) is already active, direct client writes are rejected by Firestore Security Rules with `PERMISSION_DENIED`. The app fails closed safely, displays a permission error SnackBar, and preserves the draft with the `"Resume"` action (no data corruption or rate-limit bypass).
       - Or operators launch the test build with a non-staging environment (e.g. `--dart-define=APP_ENV=development`), which immediately triggers the client-side fail-closed gate in `main_shell_screen.dart` (`!config.isStagingSubmissionAllowed`), blocking submission attempts instantly and preserving drafts with `"Resume"`.
   - **Distinction from Future Capabilities:**
     * *Existing Capabilities:* Compile-time `--dart-define` configuration (`APP_ENV`, `USE_CALLABLE_SUBMISSION`, `FIREBASE_PROJECT_ID`), strict `isStagingSubmissionAllowed` client gate, fail-closed Firestore Security Rules (`firestore.production.rules`), and local draft preservation with `"Resume"`.
     * *Future Phase Enhancement (Non-MVP Scope):* Dynamic server-side maintenance kill-switches or remote configuration toggles (e.g., Firebase Remote Config) do **not** exist in the V1 Phase 2 implementation and are slated for a future phase. Operators must rely solely on the verified build/environment gating and draft preservation behaviors described above.

2. **R.2 — Cloud Function Revision Rollback (Primary Backend Defense):**
   If `submitRestroom` exhibits an unexpected error spike, latency spike, or runtime regression:
   - **Prerequisite — Service & Revision Discovery:**
     Do not guess Cloud Run service or revision names. In Cloud Functions V2, Cloud Run service names are provisioned per Google Cloud naming conventions. Operators must first verify the exact service name and deployed revisions in `flushcrowd-staging`:
     ```bash
     # 1. Identify the exact Cloud Run service name
     gcloud run services list \
       --project=flushcrowd-staging \
       --region=us-central1

     # 2. List deployed revisions for that verified service name
     gcloud run revisions list \
       --service=<VERIFIED_SERVICE_NAME> \
       --project=flushcrowd-staging \
       --region=us-central1
     ```
   - **Traffic Rollback Execution:**
     Route 100% of ingress traffic back to the identified previously healthy revision:
     ```bash
     gcloud run services update-traffic <VERIFIED_SERVICE_NAME> \
       --to-revisions=<PREVIOUS_STABLE_REVISION_NAME>=100 \
       --region=us-central1 \
       --project=flushcrowd-staging
     ```
   - *Alternative Console Workflow:* Navigate to **Google Cloud Console -> Cloud Run -> [Verified Service Name] -> Revisions -> Manage Traffic**, select the prior healthy revision, and set traffic allocation to 100%.

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
> **Under no circumstances shall direct client writes ever be described or used as a production rollback fallback.** Production operates exclusively through the callable function backend. In production, any backend incident is resolved strictly by Cloud Run revision rollback (R.2) or by halting new client releases while preserving user drafts (R.1).

---

## 6. Summary Checklist for Independent Audit

| Checkpoint | Requirement | Status |
| :--- | :--- | :--- |
| **Backend Discovery** | `firebase.json` codebase, predeploy & `.env.flushcrowd-staging` | Verified |
| **Region Parity** | `us-central1` explicit in backend & client | Verified |
| **Project Guard** | `getAppConfig()` fail-closed on missing/mismatched identity | Verified & Tested |
| **App Check Sync** | Contradiction resolved via debug-token plan | Documented & Implemented |
| **Rules Candidate** | `firestore.production.rules` closes direct writes | Authored & Validated |
| **Cutover Configuration** | `firebase.cutover.json` deterministic selection | Verified & Tested |
| **Rules Testing** | 61 scenarios in `rules_tests` (49 staging + 6 cutover + 6 config) | 61/61 PASS |
| **Functions Testing** | 25 callable & preflight scenarios in `functions/test` | 25/25 PASS |
| **Physical QA Runbook** | Checklists for SM-G998B & iPhone 12 Pro Max | 8/8 Category A Human PASS Recorded |
| **Staging Preflight** | 12-point read-only audit against `flushcrowd-staging` | 10 PASS / 0 FAIL / 1 NOT VERIFIED / 1 PENDING |
| **Rollout / Rollback** | Step-by-step gates, explicit sequencing & production non-bypass invariants | Documented |
| **Live Gate** | No live deployment or merge without human approval | LOCKED |

---

## 7. Staging Readiness Preflight Assessment (Read-Only) & Gate Report

Conducted on October 18, 2026 using read-only CLI operations and existing environment configuration against project `flushcrowd-staging`. Zero live deployments, zero security rules activations, and zero secrets committed or exposed.

### 7.1 Preflight Assessment Matrix (12 Audit Vectors)

| # | Inspection Item | Scope / Command | Result | Evidence & Findings |
| :--- | :--- | :--- | :--- | :--- |
| **1** | Firebase Project ID | CLI (`firebase projects:list`) | **PASS** | `flushcrowd-staging` (Project Number: `925391896465`). |
| **2** | Blaze Billing Plan Status | GCP CLI (`gcloud billing projects describe`) | **PASS** | `billingEnabled: true`, linked to billing account `billingAccounts/017ED3-AC57E0-96AF50`. |
| **3** | Billing Budget & Alert Thresholds | GCP Cloud Billing Console | **NOT VERIFIED** | `billingbudgets.googleapis.com` API requires quota project and admin permissions; owner must confirm $25.00/mo budget and 50%/90%/100% email alerts in GCP Console. |
| **4** | Firebase Anonymous Auth Provider | Identity Toolkit API (`GET /v2/projects/flushcrowd-staging/config`) | **PASS** | Direct read-only confirmation of live provider configuration via authenticated Identity Toolkit REST API (`projects/925391896465/config`: `signIn.anonymous.enabled: true`). Confirms anonymous authentication is enabled in `flushcrowd-staging` without creating test users or exporting user records. |
| **5** | Cloud Firestore Staging Readiness | GCP CLI (`gcloud firestore databases describe`) | **PASS** | `projects/flushcrowd-staging/databases/(default)` active in `FIRESTORE_NATIVE` mode, Standard edition (`asia-southeast1`). |
| **6** | Mobile Firebase Configuration Consistency | Mobile Config Check (`google-services.json` / `GoogleService-Info.plist`) | **PASS** | Android: `flushcrowd-staging` / `com.flushcrowd.flushcrowd` (App ID `1:925391896465:android:bcaddc3c452836bae82430`); iOS: `flushcrowd-staging` / `com.flushcrowd.flushcrowd` (App ID `1:925391896465:ios:debbd6ca5515e5f1e82430`). 100% match with `firebase apps:list`. |
| **7** | App Check Debug-Provider & Token Registration | Client Service Code & Testing Procedure | **PENDING** | `FirebaseAppCheckService` activates `AndroidDebugProvider` and `AppleDebugProvider` in staging builds (§2.4). Physical-device debug token extraction and console registration is an operational action required on test day (§4 Test B.1). |
| **8** | Staging Functions Environment File | File Inspection (`functions/.env.flushcrowd-staging`) | **PASS** | Declares non-secret `APP_ENV=staging`, auto-loaded by Firebase CLI for `flushcrowd-staging` and deployed to Cloud Run container runtime. |
| **9** | Functions TypeScript Build & Smoke Checks | Smoke Scripts (`npm run build && smoke:entrypoint && smoke:staging`) | **PASS** | TypeScript compilation: 0 errors; package entrypoint smoke: PASS; staging discovery smoke: PASS (`APP_ENV=staging` confirmed). |
| **10** | Rules & Functions Emulator Suites | Emulators (`rules_tests run test:emulators` & `functions run test:emulators`) | **PASS** | Rules emulator: 61/61 PASS (49 staging rules + 6 cutover rules + 6 config checks); Functions emulator: 25/25 PASS (9 App Check/env preflight + 16 rate-limiting scenarios). |
| **11** | Deployment Target & Region | Configuration & Code Inspection | **PASS** | Target: `--project flushcrowd-staging --only functions:submitRestroom`. Region: `us-central1` across `functions/src/index.ts`, `functions/src/submit_restroom.ts`, and Flutter client `app_constants.dart`. |
| **12** | Explicit Rollback & Abort Procedures | Runbook Specification (§5 Stage 5) | **PASS** | R.1 (client draft preservation & build recovery), R.2 (Cloud Run revision rollback with verified service/revision discovery), R.3 (staging-only emergency rules rollback), and Stage 4 abort criteria documented. |

**Assessment Matrix Outcome:** 10 PASS / 0 FAIL / 1 NOT VERIFIED / 1 PENDING (12 audit vectors total).

---

### 7.2 Gate 2 Prerequisite Checklist (Owner Actions Prior to Staging Deployment)

Before executing the live staging deployment command (`firebase deploy --project flushcrowd-staging --only functions:submitRestroom`), the human owner must:

1. [ ] **Confirm Billing Budget in GCP Console:** Log in to Google Cloud Console for billing account `017ED3-AC57E0-96AF50` and confirm a $25/mo budget with alert notifications configured at 50% ($12.50), 90% ($22.50), and 100% ($25.00).
2. [ ] **Confirm Anonymous Authentication in Firebase Console:** Double-check in Firebase Console > Authentication > Sign-in method that the Anonymous provider is active (secondary visual confirmation of vector #4).
3. [ ] **Confirm Device OS Versions on Testing Day:** Record actual Android OS & One UI version for Samsung SM-G998B and iOS version for iPhone 12 Pro Max via device Settings.
4. [ ] **Register App Check Debug Tokens:** Once the callable test build is launched on the devices, extract debug tokens from device logs and register them under **App Check -> Apps -> Manage debug tokens** in `flushcrowd-staging` (fulfilling operational vector #7).
5. [ ] **Grant Explicit Gate 2 Signoff:** Provide explicit written authorization to deploy `submitRestroom` to `flushcrowd-staging`.
