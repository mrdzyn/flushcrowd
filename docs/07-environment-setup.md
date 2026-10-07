# FlushCrowd Environment & Secrets Setup Guide

This document defines configuration, secrets management, staging environment specifications, native build integration paths, and cost-control procedures for FlushCrowd.

---

## 1. Secrets & Configuration Policy

FlushCrowd enforces a strict zero-secrets-in-repo policy:

- Never commit service-account credentials, private signing keys, App Check debug tokens, or unrestricted API keys.
- `.gitignore` protects sensitive configuration across all paths:
  - Environment files: `.env*` (with `!.env.example` tracked as a sanitized reference template)
  - Firebase configuration: `google-services.json`, `**/google-services.json`, `GoogleService-Info.plist`, `**/GoogleService-Info.plist`
  - App Check debug tokens: `*debug-token*`
  - Signing keys & certificates: `*.key`, `*.keystore`, `*.jks`, `*.p8`, `*.p12`, `*.mobileprovision`
  - Local overrides & secrets: `local.properties`, `**/local.properties`, `key.properties`, `**/key.properties`, `ios/Flutter/Secrets.xcconfig`, `**/Secrets.xcconfig`

### Configuration Matrix (No Dotenv Runtime Loader)
FlushCrowd does **not** use a runtime dotenv package; `.env` is not loaded at runtime. Configuration is managed via:
1. **Compile-time Dart defines (`--dart-define`):**
   - `APP_ENV`: `development` | `staging` | `production` (default: `development`)
   - `ENABLE_APP_CHECK`: `true` | `false` (default: `true`)
2. **Platform-native Maps keys:**
   - Android: `android/local.properties` -> `MAPS_API_KEY=<restricted-key>`
   - iOS: `ios/Flutter/Secrets.xcconfig` -> `GOOGLE_MAPS_API_KEY=<restricted-key>`
3. **Platform-native Firebase configuration:**
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

---

## 2. Staging Resource Contract & Identifiers

Staging uses the following canonical configuration:

- **Firebase / GCP Staging Project ID:** `flushcrowd-staging`
- **Android Application ID / Package Name:** `com.flushcrowd.flushcrowd`
- **iOS Bundle Identifier:** `com.flushcrowd.flushcrowd`
- **Flavors / Schemes:** None. The application uses unified bundle identifiers across staging and production without build flavors or custom schemes.
- **Future Production Project:** `flushcrowd-prod` (do **NOT** create or configure production resources during staging readiness).

---

## 3. Google Maps Platform Setup & Native Integration

FlushCrowd requires **Google Maps SDK for Android** and **Google Maps SDK for iOS** for visualization.

### Crucial Cost & Scope Guardrail:
- **DO NOT** enable the Places API, Routes API, Directions API, Geocoding API, or Street View APIs.
- FlushCrowd discovery uses Cloud Firestore spatial geohash queries, and navigation is handed off directly to external navigation applications (Google Maps, Apple Maps, Waze).
- Avoid enabling paid Google Maps Platform Web Services APIs.

### Platform Key Restrictions & Native Wiring:

1. **Android Key Configuration:**
   - In Google Cloud Console -> **APIs & Services** -> **Credentials**.
   - Create an API Key named `FlushCrowd Android Staging Key`.
   - Set **API restrictions**: Select only **Maps SDK for Android**.
   - Set **Application restrictions**: Select **Android apps**.
   - Add package name: `com.flushcrowd.flushcrowd`.
   - Add SHA-1 certificate fingerprint from your staging/debug keystore (`keytool -list -v -keystore ~/.android/debug.keystore`).
   - Add the key to `android/local.properties` (gitignored):
     ```properties
     MAPS_API_KEY=AIzaSy...
     ```
   - **Native Consumption Path:** `android/app/build.gradle.kts` reads `MAPS_API_KEY` from `local.properties` and injects it into `manifestPlaceholders["MAPS_API_KEY"]`. `AndroidManifest.xml` references it via `<meta-data android:name="com.google.android.geo.API_KEY" android:value="${MAPS_API_KEY}" />`. If absent, defaults to `"DEFAULT_MAPS_API_KEY"`.
   - Note: Dart `--dart-define` does not configure the native Android Maps SDK.

2. **iOS Key Configuration:**
   - In Google Cloud Console, create an API Key named `FlushCrowd iOS Staging Key`.
   - Set **API restrictions**: Select only **Maps SDK for iOS**.
   - Set **Application restrictions**: Select **iOS apps**.
   - Add iOS bundle identifier: `com.flushcrowd.flushcrowd`.
   - Add the key to `ios/Flutter/Secrets.xcconfig` (gitignored):
     ```xcconfig
     GOOGLE_MAPS_API_KEY=AIzaSy...
     ```
   - **Native Consumption Path:** `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` set a safe fallback (`GOOGLE_MAPS_API_KEY=DEFAULT_MAPS_API_KEY`) and optionally include `#include? "Secrets.xcconfig"`. `ios/Runner/Info.plist` defines `<key>GoogleMapsApiKey</key><string>$(GOOGLE_MAPS_API_KEY)</string>`. `AppDelegate.swift` reads `Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey")` and calls `GMSServices.provideAPIKey()` only when non-empty, non-default, and non-macro.
   - Note: Dart `--dart-define` does not configure the native iOS Maps SDK.

---

## 4. Firebase Staging Project & Native Integration Paths

### 1. Native Build Integration Boundaries:

- **Android Google Services Plugin (`android/app/google-services.json`):**
  - Declared in `android/settings.gradle.kts`: `id("com.google.gms.google-services") version "4.4.2" apply false`.
  - Conditionally applied in `android/app/build.gradle.kts`:
    ```kotlin
    if (file("google-services.json").exists()) {
        apply(plugin = "com.google.gms.google-services")
    }
    ```
  - **Absent-file behavior:** CI and local development builds without `google-services.json` succeed cleanly without error.
  - **Present-file behavior:** When `android/app/google-services.json` is provided, the plugin generates the required Android resources (`google_app_id`, etc.) consumed by `Firebase.initializeApp()`.

- **iOS GoogleService-Info.plist Bundle Mechanism (`ios/Runner/GoogleService-Info.plist`):**
  - Deterministic Xcode build phase in `ios/Runner.xcodeproj/project.pbxproj`: `Copy GoogleService-Info.plist` executes after `Resources`.
  - Shell script logic:
    ```sh
    PLIST="${PROJECT_DIR}/Runner/GoogleService-Info.plist"
    TARGET_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
    if [ -f "$PLIST" ]; then
      echo "Copying GoogleService-Info.plist into application bundle..."
      mkdir -p "$TARGET_DIR"
      cp "$PLIST" "$TARGET_DIR/GoogleService-Info.plist"
    fi
    ```
  - **Absent-file behavior:** If `GoogleService-Info.plist` is absent, the script exits cleanly; credential-free builds (CI and local) succeed.
  - **Present-file behavior:** When `ios/Runner/GoogleService-Info.plist` is placed by the owner, it is copied directly into the app bundle where `FirebaseApp.configure()` discovers it at runtime.

### 2. Authentication:
- In Firebase Console -> **Build** -> **Authentication** -> **Sign-in method**.
- Enable **Anonymous** provider only.
- **DO NOT** enable email/password, Google sign-in, Apple login, Facebook, phone, or any other identity provider. Traditional login is not required for FlushCrowd V1.

### 3. Cloud Firestore & Explicit Staging Deployment:
- Provision Cloud Firestore in `flushcrowd-staging`.
- Because `.firebaserc` is not checked into version control, all deployment commands **must explicitly specify** the target project:
  ```bash
  firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes
  ```
- **Do NOT deploy security rules during initial staging setup.** Rules are deployed only during the structured activation sequence after explicit human owner approval.
- Public/private separation: `restrooms` and `ratings` are sanitized for public read. `ratingOwnership`, `contributions`, and `reports` are private.

### 4. Firebase App Check Strategy:
FlushCrowd integrates App Check with environment-aligned provider selection:
- **Development & Staging (`!config.isProduction`):**
  - Configured with `AndroidDebugProvider()` and `AppleDebugProvider()`.
  - At runtime, the Firebase SDK logs an App Check debug token to the console.
  - Register the emitted debug token in Firebase Console -> **App Check** -> **Apps** -> **Manage debug tokens**.
  - **Never commit debug tokens to git.**
- **Production (`config.isProduction`):**
  - Android: `AndroidPlayIntegrityProvider()` linked to Google Play Console.
  - iOS: `AppleAppAttestWithDeviceCheckFallbackProvider()`.
- **Enforcement Notice:**
  - Do **NOT** enable App Check enforcement in staging. Leave providers in monitoring/un-enforced mode until valid release traffic metrics are observed.

---

## 5. Corrected Human Staging Activation Sequence

The human owner should follow this exact sequence in order:

1. Create Firebase / GCP project `flushcrowd-staging`.
2. Register Android app with package name `com.flushcrowd.flushcrowd`.
3. Register iOS app with bundle identifier `com.flushcrowd.flushcrowd`.
4. Enable **Anonymous Authentication** in Firebase Authentication sign-in methods.
5. Create Cloud Firestore database in `flushcrowd-staging`.
6. Download Android (`google-services.json`) and iOS (`GoogleService-Info.plist`) configuration files from the Firebase console.
7. Place both config files locally in their documented gitignored paths:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
8. Create Google Maps Android API key in Google Cloud Console; restrict to Android apps (`com.flushcrowd.flushcrowd` + staging SHA-1) and **Maps SDK for Android** only.
9. Create Google Maps iOS API key in Google Cloud Console; restrict to iOS apps (`com.flushcrowd.flushcrowd`) and **Maps SDK for iOS** only.
10. Configure local Maps keys without committing them:
    - Add `MAPS_API_KEY=<restricted-android-key>` to `android/local.properties`
    - Add `GOOGLE_MAPS_API_KEY=<restricted-ios-key>` to `ios/Flutter/Secrets.xcconfig`
11. Build and run Android and iOS staging builds locally; verify native builds succeed and Google Maps render correctly.
12. Verify Firebase SDK initializes successfully on both platforms without fallback error logs.
13. Obtain explicit human owner approval before deploying Firestore security rules.
14. Deploy audited Firestore Rules and indexes explicitly to staging:
    ```bash
    firebase deploy --project flushcrowd-staging --only firestore:rules,firestore:indexes
    ```
15. Verify Cloud Firestore read connectivity under the deployed rules without executing contribution writes.
16. Verify Anonymous Authentication sign-in succeeds and creates an anonymous user session.
17. Verify Firebase App Check debug behavior: note debug token in console and register it in Firebase Console -> App Check -> Manage debug tokens.
18. Evaluate staging acceptance gate: confirm all 11 criteria in Section 6 are verified.
19. Confirm that production contribution writes remain blocked by the P2.6 rate-limiting release gate.
20. Only after observed App Check traffic and validated release builds: consider enabling enforcement later.

> [!NOTE]
> Items 1–20 require manual execution in Google Cloud Console, Firebase Console, and local development environments. They are pending human owner configuration.

---

## 6. Staging Acceptance Gate for P2.3

Implementation of Phase 2 Milestone P2.3 (Contribution Form UI) is blocked until the human owner or live QA verifies the following 11 criteria:

1. Firebase staging project exists (`flushcrowd-staging`).
2. Android Firebase registration is valid (`com.flushcrowd.flushcrowd`).
3. iOS Firebase registration is valid (`com.flushcrowd.flushcrowd`).
4. Anonymous Authentication succeeds and creates anonymous sessions.
5. Cloud Firestore connects successfully.
6. Android map renders correctly with the restricted key.
7. iOS map renders correctly with the restricted key.
8. Firebase local configuration files (`google-services.json`, `GoogleService-Info.plist`) are present locally and verified **not tracked by git**.
9. Google Maps API keys are verified **not committed** to git.
10. Firebase App Check development behavior is understood and verified.
11. No unintended paid Maps APIs (Places, Routes, Directions, Geocoding) are enabled.

> [!IMPORTANT]
> **Production Contribution Release Gate:**
> Cloud Firestore production community contribution writes remain strictly blocked by the P2.6 abuse rate-limiting release gate. Staging environment readiness does **NOT** waive or remove this production security gate.

---

## 7. Google Cloud Budget Alerts & Cost Controls

To ensure FlushCrowd remains low-cost to operate:

1. **GCP Billing Budget:**
   - Go to Google Cloud Console -> **Billing** -> **Budgets & alerts**.
   - Create a monthly budget (e.g. $25.00 / month) with alert thresholds at 50%, 90%, and 100%.
   - Add notification email addresses for project administrators.

2. **Application-level Cost Guards:**
   - **Zero-Fan-Out Data Model:** Restroom documents store precomputed rating averages and counts (`averageRating`, `ratingCount`, `verificationCount`) so discovery never fans out to read child rating documents.
   - **Strict API Scope Restriction:** No Google Maps Platform Web Services (Places, Routes, Directions, Geocoding) are enabled; navigation is strictly external-app handoff.
   - **Debounced Viewport Queries:** Camera movement queries are debounced (400ms after camera idle) to prevent excessive read requests during user gestures.
   - **Geohash Spatial Queries:** Bounded multi-cell queries with exact Haversine post-filtering and bounded candidate limits.
   - **Marker Clustering:** Dense map markers clustered via `ClusterManager` to avoid rendering overload.
   - **Zoom Floor:** Discovery queries are suppressed at zoom levels below 12.0.

---

## 8. Android Signing & Release Readiness Safeguard

- **Current State:** `android/app/build.gradle.kts` uses debug keystore signing for release builds (`signingConfig = signingConfigs.getByName("debug")`) solely as a development convenience to allow local testing with `flutter run --release` and `flutter build apk --debug`.
- **Production Warning:** This configuration is strictly **development-only** and **MUST NOT** be used for store distribution or production releases.
- **Production Setup Procedure:** Prior to production release readiness:
  1. Generate a production upload key:
     ```bash
     keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
     ```
  2. Create `android/key.properties` (strictly gitignored):
     ```properties
     storePassword=<password>
     keyPassword=<password>
     keyAlias=upload
     storeFile=<path-to-keystore>
     ```
  3. Update `android/app/build.gradle.kts` to load `key.properties` for production release signing. Never commit keystores or key properties.
