# LooRadar Environment & Secrets Setup Guide

This document defines the configuration, secrets management, and cost-control procedures for LooRadar.

---

## 1. Secrets Policy

LooRadar enforces a strict zero-secrets-in-repo policy:

- Never commit service-account credentials, private signing keys, App Check debug tokens, or unrestricted API keys.
- `.gitignore` is pre-configured to ignore `.env`, `google-services.json`, `GoogleService-Info.plist`, `*debug-token*`, and keystore files.
- Compile-time values are passed using `--dart-define` or injected natively via Gradle / Xcode build properties.

---

## 2. Google Maps Platform Setup

LooRadar requires **Google Maps SDK for Android** and **Google Maps SDK for iOS** for visualization.

### Crucial Cost & Scope Guardrail:
- **DO NOT** enable the Places API, Routes API, Directions API, Geocoding API, or Street View. LooRadar V1 discovery uses Cloud Firestore spatial queries, and navigation is handed off directly to installed navigation applications (Google Maps, Apple Maps, Waze).

### Platform API Key Restrictions:

1. **Android Key:**
   - In Google Cloud Console -> **APIs & Services** -> **Credentials**.
   - Create an API Key named `LooRadar Android Key`.
   - Set **API restrictions**: Select only **Maps SDK for Android**.
   - Set **Application restrictions**: Select **Android apps**.
   - Add package name: `com.looradar.looradar`
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
   - In Google Cloud Console, create an API Key named `LooRadar iOS Key`.
   - Set **API restrictions**: Select only **Maps SDK for iOS**.
   - Set **Application restrictions**: Select **iOS apps**.
   - Add iOS bundle identifier: `com.looradar.looradar`.
   - For local builds, pass via `--dart-define=MAPS_API_KEY_IOS=AIzaSy...` or configure in `ios/Flutter/Debug.xcconfig` / `Release.xcconfig`.

---

## 3. Firebase Project & Authentication

### 1. Project Initialization:
1. Create a Firebase project named `looradar-dev` (or `looradar-prod`).
2. Add an **Android app** with package name `com.looradar.looradar` and download `google-services.json` to `android/app/google-services.json`.
3. Add an **iOS app** with bundle ID `com.looradar.looradar` and download `GoogleService-Info.plist` to `ios/Runner/GoogleService-Info.plist`.

### 2. Anonymous Authentication:
- In Firebase Console -> **Build** -> **Authentication** -> **Sign-in method**.
- Enable **Anonymous** provider.
- Note: LooRadar V1 does not require email, password, or third-party OAuth providers.

### 3. Cloud Firestore & Security Rules:
- Deploy security rules and indexes using Firebase CLI:
  ```bash
  firebase deploy --only firestore:rules,firestore:indexes
  ```
- Public/private separation: `restrooms` and `ratings` are sanitized for public read. `ratingOwnership` and `reports` are private.

---

## 4. Firebase App Check Strategy

LooRadar uses Firebase App Check to protect backend resources from abuse:

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

To ensure LooRadar remains low-cost to operate:

1. **GCP Billing Budget:**
   - Go to Google Cloud Console -> **Billing** -> **Budgets & alerts**.
   - Create a monthly budget (e.g. \$25.00 / month) with alert thresholds at 50%, 90%, and 100%.
   - Add notification email addresses for the project administrators.

2. **Application-level Cost Guards:**
   - Viewport map pan/zoom queries are debounced.
   - Restroom listings store precomputed rating averages and counts (`averageRating`, `ratingCount`) so card views never fan out to read child rating documents.
   - Dense markers are clustered.
   - Cache results locally using Firestore offline cache.
