# FlushCrowd Environment & Secrets Setup Guide

This document defines the configuration, secrets management, and cost-control procedures for FlushCrowd.

---

## 1. Secrets Policy

FlushCrowd enforces a strict zero-secrets-in-repo policy:

- Never commit service-account credentials, private signing keys, App Check debug tokens, or unrestricted API keys.
- `.gitignore` is pre-configured to ignore `.env`, `google-services.json`, `GoogleService-Info.plist`, `*debug-token*`, and keystore files.
- Compile-time values are passed using `--dart-define` or injected natively via Gradle / Xcode build properties.

---

## 2. Google Maps Platform Setup

FlushCrowd requires **Google Maps SDK for Android** and **Google Maps SDK for iOS** for visualization.

### Crucial Cost & Scope Guardrail:
- **DO NOT** enable the Places API, Routes API, Directions API, Geocoding API, or Street View. FlushCrowd V1 discovery uses Cloud Firestore spatial queries, and navigation is handed off directly to installed navigation applications (Google Maps, Apple Maps, Waze).

### Platform API Key Restrictions:

1. **Android Key:**
   - In Google Cloud Console -> **APIs & Services** -> **Credentials**.
   - Create an API Key named `FlushCrowd Android Key`.
   - Set **API restrictions**: Select only **Maps SDK for Android**.
   - Set **Application restrictions**: Select **Android apps**.
   - Add package name: `com.flushcrowd.flushcrowd`
   - Add SHA-1 certificate fingerprint from your debug keystore (`keytool -list -v -keystore ~/.android/debug.keystore`) or release keystore.
   - For local builds, add the key to `android/local.properties`:
     ```properties
     MAPS_API_KEY=AIzaSy...
     ```
     Or build with:
     ```bash
     flutter run --dart-define=MAPS_API_KEY_ANDROID=AIzaSy...
     ```

2. **iOS Key:**
   - In Google Cloud Console, create an API Key named `FlushCrowd iOS Key`.
   - Set **API restrictions**: Select only **Maps SDK for iOS**.
   - Set **Application restrictions**: Select **iOS apps**.
   - Add iOS bundle identifier: `com.flushcrowd.flushcrowd`.
   - For local builds, pass via `--dart-define=MAPS_API_KEY_IOS=AIzaSy...` or configure in `ios/Flutter/Debug.xcconfig` / `Release.xcconfig`.

---

## 3. Firebase Project & Authentication

### 1. Project Initialization:
1. Create a Firebase project named `flushcrowd-staging` (or `flushcrowd-prod`).
2. Add an **Android app** with package name `com.flushcrowd.flushcrowd` and download `google-services.json` to `android/app/google-services.json`.
3. Add an **iOS app** with bundle ID `com.flushcrowd.flushcrowd` and download `GoogleService-Info.plist` to `ios/Runner/GoogleService-Info.plist`.

### 2. Anonymous Authentication:
- In Firebase Console -> **Build** -> **Authentication** -> **Sign-in method**.
- Enable **Anonymous** provider.
- Note: FlushCrowd V1 does not require email, password, or third-party OAuth providers.

### 3. Cloud Firestore & Security Rules:
- Deploy security rules and indexes using Firebase CLI:
  ```bash
  firebase deploy --only firestore:rules,firestore:indexes
  ```
- Public/private separation: `restrooms` and `ratings` are sanitized for public read. `ratingOwnership` and `reports` are private.

---

## 4. Firebase App Check Strategy

FlushCrowd uses Firebase App Check to protect backend resources from abuse:

- **Local Development / Simulator / CI:**
  - Uses `AndroidDebugProvider()` and `AppleDebugProvider()`.
  - For local device testing, register the printed debug token in Firebase Console -> **App Check** -> **Apps** -> **Manage debug tokens**.
  - **Never commit debug tokens to git.**
- **Production Android:**
  - Configured with `AndroidPlayIntegrityProvider()`.
  - Linked to Google Play Console before enabling enforcement.
- **Production Apple:**
  - Configured with `AppleAppAttestWithDeviceCheckFallbackProvider()`.
- **Enforcement Notice:**
  - Verify valid release metrics in the App Check dashboard before switching rules from "Monitor" to "Enforce".

---

## 5. Google Cloud Budget Alerts & Cost Controls

To ensure FlushCrowd remains low-cost to operate:

1. **GCP Billing Budget:**
   - Go to Google Cloud Console -> **Billing** -> **Budgets & alerts**.
   - Create a monthly budget (e.g. \$25.00 / month) with alert thresholds at 50%, 90%, and 100%.
   - Add notification email addresses for the project administrators.

2. **Application-level Cost Guards:**

   **IMPLEMENTED IN PHASE 0 BASELINE:**
   - **Zero-Fan-Out Data Model:** Restroom documents store precomputed rating averages and counts (`averageRating`, `ratingCount`, `verificationCount`) so map and preview cards never fan out to read child rating documents.
   - **Strict API Scope Restriction:** No Google Maps Platform Web Services (Places, Routes, Directions, Geocoding) are enabled; navigation is strictly external-app handoff.
   - **Deferred Spatial Execution:** Production Firestore spatial discovery (`getNearbyRestrooms`, `getViewportRestrooms`) is explicitly deferred to Phase 1 via fail-safe `UnsupportedError`, preventing accidental un-debounced or incomplete queries during Phase 0.

   **REQUIRED & PLANNED FOR PHASE 1:**
   - **Debounced Viewport Queries:** Map camera movement queries will be debounced (e.g. 300–500ms delay after idle) to avoid triggering queries on each pan/zoom frame.
   - **9-Neighbor Geohash Expansion:** Multi-cell candidate expansion with strict distance post-filtering and bounded radius limits.
   - **Marker Clustering:** Dense map markers clustered dynamically by zoom level to avoid map marker explosion.
   - **Offline Caching:** Explicit Firestore cache sizing and query persistence policies.

---

## 6. Android Signing & Release Readiness Safeguard

- **Current State (Phase 0):** `android/app/build.gradle.kts` uses debug keystore signing for release builds (`signingConfig = signingConfigs.getByName("debug")`) solely as a development convenience to allow local testing with `flutter run --release` and `flutter build apk --debug`.
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
