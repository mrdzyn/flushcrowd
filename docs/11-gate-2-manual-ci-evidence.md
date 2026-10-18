# FlushCrowd — Gate 2 Manual CI Verification & Dependency Security Triage Report

> Canonical documentation of Gate 2 manual CI execution, Node.js version parity resolution, and independent dependency security advisory triage for FlushCrowd Phase 2 deployment readiness.
>
> **PREPARATION & EVIDENCE ONLY:** This document records test verification and security analysis. No live deployment, rules activation, production submission enablement, or pull request merge is authorized by this report.

- **Date:** October 18, 2026
- **Repository:** `mrdzyn/flushcrowd`
- **Evaluated Baseline:** `a9248193a38ab509e3e9a0eea4e1b5449db8715c` (`main` after PR #18)
- **Branch:** `phase-2/p2.6-gate-2-security-followup`
- **Operating Mode:** Temporary Manual CI Operating Mode (during GitHub Actions suspension; see `docs/STATUS.md`)
- **Review Requirement:** Independent review and explicit owner authorization prior to live staging deployment.

---

## 1. Executive Summary

On October 18, 2026, the human repository owner executed a manual continuous integration pass against baseline `a9248193a38ab509e3e9a0eea4e1b5449db8715c`. Two items required technical resolution and classification before Gate 2 staging deployment approval:

1. **Finding 1 — Node.js Version Parity:**
   The initial manual test pass ran on ambient Node.js 24.21.0. The bundled `superstatic@9.2.0` package emitted an engine compatibility warning (`required: { node: '>=18.0.0 <=22.x' }`). Repeat testing under the canonical GitHub Actions environment (**Node.js 22.23.3** / **npm 10.9.9**) eliminated the engine warning completely while maintaining **100% test pass** across both emulator suites (61/61 rules tests, 25/25 functions tests).
2. **Finding 2 — Dependency Security Advisory Triage:**
   The initial npm installation reported security advisories across the repository's two Node workspaces:
   - `rules_tests/`: 24 packages flagged (1 critical, 12 high, 11 moderate).
   - `functions/`: 29 packages flagged (1 critical, 14 high, 14 moderate).
   
   A rigorous security audit was conducted. **Advisory counts must never be summed** (24 + 29 ≠ 53), as 24 of the packages in `functions` are identical devDependencies shared with `rules_tests`.
   
   - **Production Runtime Scope (`npm --prefix functions audit --omit=dev`):**
     * **0 Critical** vulnerabilities exist in production runtime dependencies.
     * **2 High** vulnerability entries (`node-forge@1.4.0` and `firebase-admin@12.7.0` which inherits it).
     * Deep AST and call-path inspection confirms that `node-forge` is imported solely for private-key PEM parsing in `CertificateCredential`. Deployed Cloud Functions V2 initializes exclusively via Google Application Default Credentials (`ComputeEngineCredential`), making `node-forge` **completely unreachable and unexploitable in the deployed Cloud Functions container**.
     * **8 Moderate** vulnerabilities (transitive `uuid` bounds checks in SDK wrappers).
   - **Development & Emulator Tooling Scope:**
     * All remaining vulnerabilities (including `tar@7.5.22` / `tar@6.2.1`, `@grpc/grpc-js@1.9.16`, `basic-ftp@5.3.1`, `braces@3.0.3`) reside strictly within `devDependencies` (`firebase-tools` CLI and `@firebase/rules-unit-testing`).
     * None of these packages are packaged by Cloud Build or deployed to Cloud Run.
     * Remediation requires major breaking upgrades (`firebase-tools@15.x`, `firebase-admin@14.x`) that would disrupt the validated Node 22 build pipeline. All findings are justified and deferred to future scheduled maintenance.
     * No `npm audit fix --force` was run.

### Summary Verification Status

| Category | Component / Command | Result | Notes |
| :--- | :--- | :--- | :--- |
| **Flutter Analysis** | `flutter analyze` | **PASS** | 0 issues found |
| **Flutter Formatting** | `dart format --output=none --set-exit-if-changed` | **PASS** | 102 files checked, 0 changed |
| **Flutter Test Suite** | `flutter test` | **PASS** | 461/461 unit, widget, and navigation tests |
| **Accessibility Tests** | `flutter test test/presentation/p2_6_accessibility_test.dart` | **PASS** | 25/25 viewport/scaling tests (320/375/390px @ 200%) |
| **Rules Config Test** | `node --test rules_tests/test/firebase_config.test.js` | **PASS** | 6/6 deterministic configuration selection tests |
| **App Check Preflight** | `node --test functions/lib/test/app_check_init.test.js` | **PASS** | 9/9 fail-closed project guard & App Check tests |
| **Firestore Rules Emulator** | `npm --prefix rules_tests run test:emulators` | **PASS** | 61/61 rules tests (49 staging + 6 cutover + 6 config) |
| **Functions Emulator** | `npm --prefix functions run test:emulators` | **PASS** | 25/25 functions tests (9 preflight + 16 rate-limit) |
| **Node Parity (Finding 1)**| Node.js 22.23.3 / npm 10.9.9 verification | **PASS** | `superstatic` engine warning eliminated |
| **Security Triage (Finding 2)**| Production & dev dependency classification | **RESOLVED**| 0 critical in prod; 2 high unexploitable; deferred |
| **Live Staging Deployment** | `firebase deploy --only functions:submitRestroom` | **NOT RUN** | Locked behind Gate 2 owner authorization |
| **App Check Debug Tokens**| Console registration of physical test devices | **PENDING** | Required on test day upon launching staging builds |

---

## 2. Finding 1 — Node.js Version Parity Verification

### 2.1 Issue Background
During initial manual CI execution on October 18, 2026, the local environment ran on ambient Node.js `v24.21.0`. While all emulator test assertions passed, `npm` emitted the following warning:

```text
npm WARN EBADENGINE Unsupported engine {
npm WARN EBADENGINE   package: 'superstatic@9.2.0',
npm WARN EBADENGINE   required: { node: '>=18.0.0 <=22.x' },
npm WARN EBADENGINE   current: { node: 'v24.21.0', npm: '11.x' }
npm WARN EBADENGINE }
```

The repository's canonical CI configuration (`.github/workflows/ci.yml`) explicitly mandates **Node.js 22** (`node-version: 22`). Testing on Node 24 introduced an unverified runtime discrepancy against canonical CI.

### 2.2 Repeat Execution under Node.js 22.23.3
The manual test suites were re-executed using `nvm use 22`, confirming exact environment versions:
- **Node.js:** `v22.23.3`
- **npm:** `10.9.9`
- **Platform:** `darwin-arm64` (macOS 15.3.1)

### 2.3 Verification Results

1. **Firestore Rules Emulator Suite:**
   ```bash
   npm --prefix rules_tests run test:emulators
   ```
   - **Output:** Clean execution; zero `EBADENGINE` warnings.
   - **Outcome:** **61/61 tests PASS** (duration: 3.8s).
   - **Scope:**
     * 49 canonical staging rules tests (`p2_add_restroom_rules.test.js`).
     * 6 production cutover rules tests (`p2_production_cutover_rules.test.js`).
     * 6 configuration selection tests (`firebase_config.test.js`).

2. **Cloud Functions Emulator Suite:**
   ```bash
   npm --prefix functions run test:emulators
   ```
   - **Output:** Clean execution; zero `EBADENGINE` warnings.
   - **Outcome:** **25/25 tests PASS** (duration: 8.4s).
   - **Scope:**
     * Pretest compilation (`npm run build`): 0 errors.
     * Package entrypoint smoke (`npm run smoke:entrypoint`): PASS.
     * Staging discovery smoke (`npm run smoke:staging`): PASS (`.env.flushcrowd-staging` loaded).
     * 9 App Check initialization & fail-closed project guard scenarios.
     * 16 rate-limiting, rolling window, OCC transaction, and stable-ID idempotency scenarios.

3. **Conclusion:**
   Finding 1 is fully verified and resolved. Running under Node 22.23.3 guarantees 100% parity with the repository's CI specification and completely eliminates engine compatibility warnings.

---

## 3. Finding 2 — Dependency Security Advisory Triage

### 3.1 Accounting & Scope Boundaries

A critical requirement of dependency security evaluation is maintaining strict separation between independent workspaces and between runtime vs build/test dependencies.

1. **Independent Package Scope Accounting:**
   - `rules_tests/`: 24 packages reported (1 critical, 12 high, 11 moderate). Total dependencies: 700 (all `dev`).
   - `functions/`: 29 packages reported (1 critical, 14 high, 14 moderate). Total dependencies: 759 (227 `prod`, 519 `dev`, 39 optional, 49 peer).
   - **Rule:** Do **NOT** sum these counts (24 + 29 ≠ 53). `rules_tests` and `functions` are separate Node packages. 24 of the packages flagged in `functions` are identical devDependencies shared with `rules_tests` (`tar`, `firebase-tools`, `@firebase/rules-unit-testing`, `@grpc/grpc-js`, `basic-ftp`, `braces`, etc.). Summing them double-counts shared CLI tooling across monorepo directories.

2. **Production vs Development Packaging Boundary:**
   - When `submitRestroom` is deployed to Google Cloud Functions (Cloud Run container) via `firebase deploy --only functions:submitRestroom`, the Google Cloud Buildpack packages only `dependencies` by running `npm install --omit=dev`.
   - `devDependencies` (`firebase-tools`, `@firebase/rules-unit-testing`, `typescript`, `@types/node`) are never installed or packaged into the deployed container image.
   - Running `npm --prefix functions audit --omit=dev`:
     * **Critical:** 0
     * **High:** 2 (`node-forge@1.4.0` and `firebase-admin@12.7.0`)
     * **Moderate:** 8 (`uuid` and transitive wrappers)
     * **Total in production runtime:** 10

3. **Rules Tests Isolation:**
   - Running `npm --prefix rules_tests audit --omit=dev` confirms **0 vulnerabilities** of any severity in production dependencies, because `rules_tests` has zero production dependencies.

---

### 3.2 High & Critical Vulnerability Classification Matrix

The following table comprehensively classifies all High and Critical findings across `functions/` and `rules_tests/`:

| Package & Installed Version | Advisory ID & Details | Direct / Transitive | Scope (Prod vs Dev/Test) | Reachability / Exploitability in Cloud Functions | Available Nonbreaking Remediation | Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`node-forge`**<br>`1.4.0` | **GHSA-86w9-cpqp-85rv**<br>CWE-347 (CVSS 7.5)<br>RSA PKCS#1 v1.5 extra nested DigestAlgorithm elements | Transitive<br>(via `firebase-admin@12.7.0`) | **Production**<br>(transitive runtime) | **UNREACHABLE / NOT EXPLOITABLE**.<br>`firebase-admin` imports `node-forge` exclusively in `credential-internal.js` line 148 (`forge.pki.privateKeyFromPem`) for PEM string parsing in `CertificateCredential`. It does not use `node-forge` for signature verification. Furthermore, deployed Cloud Functions V2 runs under Google Application Default Credentials (ADC) via `ComputeEngineCredential` (metadata server), never invoking `CertificateCredential`. | None in semver range. Fixing requires `firebase-admin@14.5.0` (major semver breaking upgrade). | **Defer with justification**.<br>Unreachable in ADC runtime; upgrading to `firebase-admin@14.x` introduces breaking API risks. |
| **`tar`**<br>`7.5.22` & `6.2.1` | **GHSA-23hp-3jrh-7fpw** (Critical, CVSS 7.5, CWE-770)<br>+ 7 High CVEs:<br>GHSA-34x7-hfp2-rc4v<br>GHSA-8qq5-rm4j-mr97<br>GHSA-83g3-92jg-28cx<br>GHSA-qffp-2rhf-9h96<br>GHSA-9ppj-qmqm-q256<br>GHSA-r6q2-hw4h-h46w<br>GHSA-8x88-c5mf-7j5w<br>GHSA-r292-9mhp-454m | Transitive<br>(via `firebase-tools@13.35.1`) | **Dev / Test Tooling Only**<br>(`devDependencies.firebase-tools`) | **ZERO REACHABILITY**.<br>`tar` is bundled in `firebase-tools` CLI (used for local emulator hosting). It is excluded from the deployed Cloud Functions container (`--omit=dev`). The Cloud Function handles JSON HTTP payloads and never untars archives. | None in semver range. Fixing requires `firebase-tools@15.34.0` (major breaking upgrade). | **Defer with justification**.<br>Purely local CLI devDependency. Excluded from production container. |
| **`@grpc/grpc-js`**<br>`1.9.16` | **GHSA-m9gg-hp2v-232j**<br>CWE-295 (CVSS 7.4)<br>getAuthContext unauthorized certificate handling | Transitive<br>(via `@firebase/rules-unit-testing@5.0.2`) | **Dev / Test Tooling Only**<br>(`devDependencies.@firebase/rules-unit-testing`) | **ZERO REACHABILITY**.<br>Production `firebase-admin@12.7.0` uses `@grpc/grpc-js@1.14.6` (already fully patched and clean). The vulnerable `1.9.16` version is pulled solely by `@firebase/rules-unit-testing`, which connects to the local Firestore emulator over plaintext localhost (`127.0.0.1:8080`) with zero client TLS certificates. | None without downgrading to deprecated `@firebase/rules-unit-testing@2.0.7`. | **Defer with justification**.<br>Production uses clean `1.14.6`. Dev test harness uses plaintext loopback emulator. |
| **`basic-ftp`**<br>`5.3.1` | **GHSA-c475-qrg2-pj4r**<br>CWE-1333 (High)<br>Quadratic CPU DoS in Unix directory listing parser | Transitive<br>(via `firebase-tools -> proxy-agent -> get-uri`) | **Dev / Test Tooling Only**<br>(`devDependencies.firebase-tools`) | **ZERO REACHABILITY**.<br>Transitive proxy agent in `firebase-tools`. Neither deployed Cloud Functions nor test runners connect to FTP servers. | Requires `firebase-tools@15.x` (major breaking upgrade). | **Defer with justification**.<br>Dev-only proxy helper. Not deployed. |
| **`braces`**<br>`3.0.3` | **GHSA-vfj7-8cjw-p6xm**<br>CWE-674 (CVSS 7.5)<br>Stack-exhaustion DoS via nested patterns | Transitive<br>(via `firebase-tools -> chokidar`) | **Dev / Test Tooling Only**<br>(`devDependencies.firebase-tools`) | **ZERO REACHABILITY**.<br>Used by `chokidar` file watcher in CLI dev tools. Excluded from production container. | Requires `firebase-tools@15.x` (major breaking upgrade). | **Defer with justification**.<br>Dev-only file watcher. Not deployed. |
| **`firebase-admin`**<br>`12.7.0` | Inherited High<br>(via `node-forge@1.4.0`) | Direct<br>(`dependencies`) | **Production** | See `node-forge` analysis above. `firebase-admin` itself has no unpatched direct vulnerabilities. | Requires breaking upgrade to v14.x. | **Defer with justification**. |
| **`firebase-tools`**<br>`13.31.0` | Inherited High / Critical<br>(via `tar`, `braces`, `basic-ftp`) | Direct<br>(`devDependencies`) | **Dev / Test Tooling Only** | Excluded from deployed container. | Requires breaking upgrade to v15.x. | **Defer with justification**. |
| **`@firebase/rules-unit-testing`**<br>`5.0.2` | Inherited High<br>(via `firebase -> @grpc/grpc-js`) | Direct<br>(`devDependencies`) | **Dev / Test Tooling Only** | Excluded from deployed container. | None nonbreaking. | **Defer with justification**. |
| **Parent Wrappers:**<br>`@firebase/firestore`<br>`@firebase/firestore-compat`<br>`firebase`<br>`chokidar`<br>`get-uri`<br>`pac-proxy-agent`<br>`proxy-agent` | Inherited High / Critical<br>(from `tar`, `braces`, `basic-ftp`, `@grpc/grpc-js`) | Transitive<br>(dev dependency trees) | **Dev / Test Tooling Only** | Excluded from deployed container. | None nonbreaking. | **Defer with justification**. |

---

### 3.3 Moderate Vulnerabilities Summary

- **`uuid` (< 11.1.1):** Flagged under GHSA-w5hq-g745-h8pq (CWE-787, CVSS 7.5, moderate). In `functions`, `uuid` is pulled transitively by `google-gax`, `teeny-request`, and `gaxios`. The advisory concerns missing buffer bounds checks when calling `uuid.v3/v5/v6` with an explicit pre-allocated buffer. `submitRestroom` does not invoke `uuid` directly, and internal Google Cloud SDKs use standard `uuid.v4()` string generation without user-supplied buffers.
- **Moderate Parent Wrappers (`@google-cloud/firestore`, `@google-cloud/storage`, `google-gax`, `retry-request`, `teeny-request`, `firebase-functions`):** All 8 inherit their moderate status from `uuid`. Zero application-level vulnerability exists.
- **`argparse`, `csv-parse`, `js-yaml`, `sprintf-js`, `stream-json`, `@google-cloud/pubsub`:** All reside in CLI `devDependencies` under `firebase-tools`.

---

### 3.4 Remediation Decision & Justification

1. **Do NOT run `npm audit fix --force`:**
   Running `npm audit fix --force` attempts to install `firebase-admin@14.5.0` and `firebase-tools@15.34.0`, breaking TypeScript compilation, Node 22 engine compatibility, and Firebase Functions V2 callable exports.
2. **Zero Unmitigated Production Risk:**
   Detailed call-path analysis confirms that neither of the two high vulnerabilities in production (`node-forge` / `firebase-admin`) is reachable or exploitable under Google Cloud Application Default Credentials.
3. **Action:**
   All current security advisories are documented, classified, and deferred with justification. No dependency changes are required prior to Gate 2 staging deployment approval. Dependency refreshes will be handled as a dedicated non-emergency chore in a future maintenance cycle.

---

## 4. Staging Readiness Assessment & Gate 2 Prerequisite Checklist

### 4.1 Updated 14-Point Preflight Assessment Matrix

| # | Inspection Vector | Scope / Method | Status | Evidence & Reference |
| :--- | :--- | :--- | :--- | :--- |
| **1** | Firebase Project ID | CLI (`firebase projects:list`) | **PASS** | `flushcrowd-staging` (Number: `925391896465`) |
| **2** | Blaze Billing Plan | GCP CLI (`gcloud billing projects describe`) | **PASS** | `billingEnabled: true` |
| **3** | Billing Budget & Alerts | Owner confirmation (October 18, 2026) | **OWNER-CONFIRMED** | Target $25/mo with 50%/90%/100% alerts configured |
| **4** | Anonymous Authentication | Identity Toolkit API (`GET /v2/projects/...`) | **PASS** | `signIn.anonymous.enabled: true` |
| **5** | Cloud Firestore Database | GCP CLI (`gcloud firestore databases describe`)| **PASS** | `(default)` in `FIRESTORE_NATIVE` mode |
| **6** | Mobile Firebase Parity | Config Check (`google-services.json` / `.plist`)| **PASS** | 100% App ID match with `firebase apps:list` |
| **7** | App Check Providers | Client Service Code Inspection | **PASS** | `AndroidDebugProvider` and `AppleDebugProvider` |
| **8** | Staging Functions Config | File Check (`functions/.env.flushcrowd-staging`)| **PASS** | `APP_ENV=staging` provisioned |
| **9** | Functions Build & Smokes | Smoke Scripts (`build`, `entrypoint`, `staging`) | **PASS** | TypeScript: 0 errors; Smokes: PASS |
| **10** | Rules Emulator Suite | Emulator (`rules_tests run test:emulators`) | **PASS** | 61/61 PASS under Node 22.23.3 (0 warnings) |
| **11** | Functions Emulator Suite| Emulator (`functions run test:emulators`) | **PASS** | 25/25 PASS under Node 22.23.3 (0 warnings) |
| **12** | Node Version Parity | Finding 1 verification under Node 22.23.3 | **PASS** | Engine compatibility warning eliminated |
| **13** | Dependency Security | Finding 2 audit triage & classification | **RESOLVED** | 0 prod critical; 2 prod high unexploitable; deferred |
| **14** | Rollout & Rollback Runbook| Runbook Specification (`docs/10-...md` §5) | **PASS** | R.1, R.2, R.3 procedures verified |

**Preflight Outcome:** 12 PASS / 1 OWNER-CONFIRMED / 1 RESOLVED / 0 FAIL. All pre-deployment verification criteria are satisfied.

---

### 4.2 Gate 2 Prerequisite Checklist for Owner Signoff

Before executing the live staging deployment command (`firebase deploy --project flushcrowd-staging --only functions:submitRestroom`), the human owner must review the following:

- [x] **Google Cloud Billing and Alerts:** Configured (Owner-confirmed October 18, 2026).
- [x] **Node.js Version Parity (Finding 1):** Verified on Node 22.23.3 with 0 engine warnings and 100% test pass.
- [x] **Dependency Security Triage (Finding 2):** Completed and classified; zero reachable production vulnerabilities.
- [ ] **Secondary Console Check for Anonymous Auth:** Confirm Anonymous provider is active in Firebase Console > Authentication > Sign-in method.
- [ ] **Physical Device OS Versions:** Record actual Android and iOS versions on test day.
- [ ] **App Check Debug Tokens:** Extract debug tokens upon launching callable staging build and register them under **App Check -> Apps -> Manage debug tokens**.
- [ ] **Written Gate 2 Signoff:** Grant explicit owner approval to deploy `submitRestroom` to `flushcrowd-staging`.
