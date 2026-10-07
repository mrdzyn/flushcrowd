# FlushCrowd Environment & Secrets Setup Guide

This document defines configuration, secrets management, staging environment specifications, and cost-control procedures for FlushCrowd.

---

## 1. Secrets & Configuration Policy

FlushCrowd enforces a strict zero-secrets-in-repo policy:

- Never commit service-account credentials, private signing keys, App Check debug tokens, or unrestricted API keys.
- `.gitignore` protects sensitive configuration across all paths:
  - Environment files: `.env*` (with `!.env.example` tracked as a sanitized template)
  - Firebase configuration: `google-services.json`, `**/google-services.json`, `GoogleService-Info.plist`, `**/GoogleService-Info.plist`
  - App Check debug tokens: `*debug-token*`
  - Signing keys & certificates: `*.key`, `*.keystore`, `*.jks`, `*.p8`, `*.p12`, `*.mobileprovision`
  - Local overrides: `local.properties`, `**/local.properties`, `key.properties`, `**/key.properties`
- Compile-time values are passed using `--dart-define` or injected natively via Gradle / Xcode build properties.

---

## 2. Staging Resource Contract & Identifiers

Staging uses the following canonical configuration:

- **Firebase / GCP Staging Project ID:** `flushcrowd-staging`
- **Android Application ID / Package Name:** `com.flushcrowd.flushcrowd`
- **iOS Bundle Identifier:** `com.flushcrowd.flushcrowd`
- **Flavors / Schemes:** None. The application uses unified bundle identifiers across staging and production unless future scope explicitly requires build flavors.
- **Future Production Project:** `flushcrowd-prod` (do **NOT** create or configure production resources during staging readiness).

---

## 3. Google Maps Platform Setup & Restrictions

FlushCrowd requires **Google Maps SDK for Android** and **Google Maps SDK for iOS** for visualization.

### Crucial Cost & Scope Guardrail:
- **DO NOT** enable the Places API, Routes API, Directions API, Geocoding API, or Street View APIs.
- FlushCrowd discovery uses Cloud Firestore spatial geohash queries, and navigation is handed off directly to external navigation applications (Google Maps, Apple Maps, Waze).
- Avoid enabling paid Google Maps Platform Web Services APIs.

### Platform API Key Restrictions:

1. **Android Key:**
   - In Google Cloud Console -> **APIs & Services** -> **Credentials**.
   - Create an API Key named `FlushCrowd Android Staging Key`.
   - Set **API restrictions**: Select only **Maps SDK for Android**.
   - Set **Application restrictions**: Select **Android apps**.
   - Add package name: `com.flushcrowd.flushcrowd`
   - Add SHA-1 certificate fingerprint from your debug keystore (`keytool -list -v -keystore ~/.android/debug.keystore`) or release keystore.
   - For local builds, add the key to `android/local.properties` (gitignored):
     ```properties
     MAPS_API_KEY=AIzaSy...
     ```
     Or build with:
     ```bash
     flutter run --dart-define=MAPS_API_KEY_ANDROID=AIzaSy...
     ```

2. **iOS Key:**
   - In Google Cloud Console, create an API Key named `FlushCrowd iOS Staging Key`.
   - Set **API restrictions**: Select only **Maps SDK for iOS**.
   - Set **Application restrictions**: Select **iOS apps**.
   - Add iOS bundle identifier: `com.flushcrowd.flushcrowd`.
   - For local builds, pass via `--dart-define=MAPS_API_KEY_IOS=AIzaSy...` or configure in `ios/Flutter/Debug.xcconfig` / `Release.xcconfig`.
   - Never commit API keys.

---

## 4. Firebase Staging Project & Services

### 1. App Registrations & Configuration Files:
- **Android App:** Registered with package `com.flushcrowd.flushcrowd`. Download `google-services.json` and place at `android/app/google-services.json` (gitignored).
- **iOS App:** Registered with bundle identifier `com.flushcrowd.flushcrowd`. Download `GoogleService-Info.plist` and place at `ios/Runner/GoogleService-Info.plist` (gitignored).
- Both configuration files must strictly remain outside version control.

### 2. Authentication:
- In Firebase Console -> **Build** -> **Authentication** -> **Sign-in method**.
- Enable **Anonymous** provider only.
- **DO NOT** enable email/password, Google sign-in, Apple login, Facebook, phone, or any other identity provider. Traditional login is not required for FlushCrowd V1.

### 3. Cloud Firestore:
- Provision Cloud Firestore in the `flushcrowd-staging` project.
- **Do NOT deploy security rules during initial staging setup.**
- When ready and explicitly approved by the owner, rules and indexes are deployed via:
  ```bash
  firebase deploy --only firestore:rules,firestore:indexes
  ```
- Public/private separation: `restrooms` and `ratings` are sanitized for public read. `ratingOwnership`, `contributions`, and `reports` are private.

### 4. Firebase App Check Strategy:
FlushCrowd integrates App Check to protect backend resources from abuse:
- **Staging / Local Development / Simulator / CI:**
  - Configured with `AndroidDebugProvider()` and `AppleDebugProvider()`.
  - For local device testing, register the printed debug token in Firebase Console -> **App Check** -> **Apps** -> **Manage debug tokens**.
  - **Never commit debug tokens to git.**
- **Production Android:** Configured with `AndroidPlayIntegrityProvider()` linked to Google Play Console.
- **Production Apple:** Configured with `AppleAppAttestWithDeviceCheckFallbackProvider()`.
- **Enforcement Notice:**
  - Do **NOT** enable App Check enforcement in staging. Leave providers in monitoring/un-enforced mode until traffic metrics are observed and validated.

---

## 5. Human Staging Activation Sequence

The human owner can follow this exact 20-step sequence to activate the staging environment:

1. Create Firebase / GCP project `flushcrowd-staging`.
2. Register Android app with package name `com.flushcrowd.flushcrowd`.
3. Register iOS app with bundle identifier `com.flushcrowd.flushcrowd`.
4. Enable **Anonymous Authentication** in Firebase Authentication sign-in methods.
5. Create Cloud Firestore database in `flushcrowd-staging`.
6. Download Android (`google-services.json`) and iOS (`GoogleService-Info.plist`) configuration files from the Firebase console.
7. Place both config files locally in their documented gitignored paths:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
8. Create Google Maps Android API key in Google Cloud Console.
9. Restrict Android key: Application restriction to Android apps (`com.flushcrowd.flushcrowd` + staging SHA-1 fingerprint) and API restriction to **Maps SDK for Android** only.
10. Create Google Maps iOS API key in Google Cloud Console.
11. Restrict iOS key: Application restriction to iOS apps (`com.flushcrowd.flushcrowd`) and API restriction to **Maps SDK for iOS** only.
12. Configure local keys without committing them (in `android/local.properties` or via `--dart-define`).
13. Register App Check debug token in Firebase Console only when local device/simulator testing requires it.
14. Build and run Android staging build locally (`flutter run -d <android-device>`).
15. Build and run iOS staging build locally (`flutter run -d <ios-device>`).
16. Verify anonymous authentication sign-in succeeds in the staging console.
17. Verify Google Map tiles render correctly on both platforms using the restricted keys.
18. Verify Cloud Firestore connectivity without executing live contribution writes.
19. Only after explicit owner approval: deploy Firestore Rules and indexes via `firebase deploy --only firestore:rules,firestore:indexes`.
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
