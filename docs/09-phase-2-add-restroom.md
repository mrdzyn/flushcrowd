# LooRadar Phase 2 — Add Restroom

## 1. Goal

Implement production-quality community restroom contribution with zero mandatory login friction, high data truthfulness, low infrastructure cost, robust abuse resistance, and strict privacy preservation.

Phase 2 enables any user to contribute new restrooms directly from the map-first interface. It builds strictly upon the Phase 0 foundational abstractions and Phase 1 map discovery pipeline, without prematurely introducing ratings submission, verification/reporting workflows, photo uploads, routing, or paid third-party APIs.

---

## 2. Phase 2 Outcomes

By the end of Phase 2, a user should be able to:

1. **Initiate Contribution:** Tap the primary "Add" action button or navigation tab from the map discovery shell.
2. **Refine Location:** Interactively position a map pin with high visual clarity, utilizing a crosshair/draggable marker with live coordinate feedback and zoom-level guidance.
3. **Input Facility Details:** Complete a structured, task-focused form covering basic facility identity, detailed indoor directions (building, floor, wing, landmark), accessibility features, gender/stall configurations, hygiene amenities, payment terms, and access instructions.
4. **Preserve Data Truth:** Ensure unconfirmed or unknown amenities are recorded as `null` (unknown) rather than defaulted to affirmative positive claims or conflated with explicit negative claims.
5. **Receive Duplicate Guidance:** Benefit from a lightweight, bounded duplicate-detection engine reusing Phase 1 GIS spatial primitives that alerts the user if an existing facility matches nearby coordinates and building context, without blocking legitimate separate facilities.
6. **Submit Atomically & Anonymously:** Submit the facility via a single atomic Firestore batch write paired with a private contribution record, authenticated seamlessly via Firebase Anonymous Authentication without requiring personal data or traditional credentials.
7. **Idempotent Retry Resilience:** Experience robust in-flight retry behavior where a stable submission ID prevents accidental duplicate facility creation on network drop or ambiguous commit.
8. **Authoritative Map Synchronization:** Receive clear confirmation feedback, automatically transition back to the map centered on the newly added facility, trigger canonical viewport discovery, and observe the new restroom rendered with an `unverified` status badge.
9. **Experience Resilience:** Benefit from clear error handling, in-flight submission debouncing, offline/network failure preservation (inputs are never discarded on failure), and accessible touch targets.

---

## 3. Locked Phase 2 Principles

- **Product Name:** **LooRadar**.
- **Map-First, Mobile-First:** Contribution originates from and completes directly back into the map discovery context.
- **Zero Login Friction:** Powered exclusively by Firebase Anonymous Authentication for V1; traditional accounts or social logins are strictly prohibited.
- **Strict Privacy Boundary:** Contributor identity (`request.auth.uid`) is NEVER stored in the publicly readable restroom document.
- **Atomic Public/Private Writes:** Every public restroom document write must be accompanied by an atomic private contribution record in `contributions/` within the same `WriteBatch`. Both documents must prove simultaneous creation.
- **Create-Only in Phase 2:** Public restroom documents are strictly **create-only** in Phase 2 (`allow update: if false;`, `allow delete: if false;`). Facility updates and status transitions are not client-controlled.
- **Data Truthfulness (Nullable Booleans):** Public amenity and stall fields are migrated to **nullable booleans** (`bool?`):
  - `true` = explicitly confirmed Yes
  - `false` = explicitly confirmed No
  - `null` = unknown / unspecified
  `false` must never mean both "No" and "Unknown".
- **Initial Facility State:** All newly contributed community restrooms MUST be assigned `status: RestroomStatus.unverified`.
- **Zero Aggregate Tampering:** Initial aggregate statistics must be strictly zeroed (`averageRating = 0.0`, `ratingCount = 0`, `verificationCount = 0`, `negativeVerificationCount = 0`, `lastVerifiedAt = null`).
- **Bounded Infrastructure & Zero Paid APIs:** Zero reliance on Google Places API, Geocoding API, Street View, or external paid lookup services. Duplicate detection runs strictly on bounded Firestore geohash queries using Phase 1 GIS primitives.
- **Advisory, Non-Blocking Duplicate Warning:** Duplicate detection is an advisory warning to guide the user, never a hard submission block.
- **Authoritative Map State:** The discovery repository and viewport query remain the single source of truth for the map. No permanent optimistic cache injection into discovery source results.
- **Production Abuse-Control Gate:** A client-side disabled button is UX protection, not abuse protection. Phase 2 contribution writes must not be enabled in production until enforceable per-UID rate limiting exists.
- **Canonical UI/UX Reference:** Preserves visual and interaction alignment with `docs/assets/looradar-mobile-ux-reference.png` and `docs/06-ui-ux-reference.md`.

---

## 4. User Journey & Screen Architecture

```text
Map Discovery Shell
  ↓ [Tap Add (+)]
Step 1: Location Pinpoint (AddRestroomLocationScreen)
  ├─ Pan/drag map under center target
  ├─ Zoom floor enforcement (zoom ≥ 15.0)
  └─ Live coordinate readouts via Coordinates value object
  ↓ [Confirm Location]
Step 2: Restroom Details & Amenities (AddRestroomFormScreen)
  ├─ Basic Info (Name, Access Type)
  ├─ Indoor Directions (Building, Floor, Wing, Landmark, Directions Note)
  ├─ Accommodations & Amenities (PWD, Baby Change, Stalls, Bidet, Paper, Soap, Dryer)
  └─ Access Instructions & Payment (Fee amount/currency, Access instructions)
  ↓ [Submit Restroom — Allocates Stable submissionId / restroomId]
Duplicate Detection Evaluation (Advisory via Phase 1 GIS)
  ├─ No match found → Proceed directly to Batch Write
  └─ Match found → Advisory Modal Sheet (Top 3 candidates)
       ├─ [View Existing Restroom] → Open Preview on Map & Abandon Submit
       └─ [No, It's a Different Restroom] → Proceed to Batch Write
  ↓ [Batch Write via Anonymous Auth with Stable ID]
  ├─ Ambiguous failure / retry → Reconcile existing pair before retrying same ID
Success Feedback & Authoritative Map Synchronization
  ├─ Show success toast/snackbar
  ├─ Navigate back to Map Discovery Shell
  ├─ Animate camera to new restroom coordinates
  ├─ Trigger canonical viewport discovery refresh
  └─ Repository returns new unverified facility → Select and open preview sheet
```

### 4.1 Entry Points

1. **Bottom Navigation Bar:** Tab index 2 ("Add") in `MainShellScreen`.
2. **Contextual Action:** Tapping "Add Restroom" from an empty discovery state or preview sheet when enabled.

### 4.2 Step 1 — Location Pinpoint (`AddRestroomLocationScreen`)

- **Initial Coordinates:** Defaults to the current map camera target or user's physical GPS location if foreground permission is granted. If neither is available, defaults to default configured city coordinates.
- **Interactive Pin Adjustment:** Map renders a prominent crosshair target or custom marker in the center. As the user pans and zooms, the coordinates update dynamically.
- **Zoom Level Floor:** Users must zoom in to at least `zoom >= 15.0` (recommended `16.0`) before the "Confirm Location" button is enabled. A gentle prompt ("Zoom in closer to pinpoint the exact restroom entrance") ensures high geographic accuracy.
- **Coordinate Display:** Shows current latitude and longitude formatted to 5 decimal places (~1.1 meter precision), validated through the `Coordinates` value object.
- **Zero Paid Geocoding Dependency:** The app does NOT call Google Geocoding or Places APIs. Geographic building and street names are supplied by the user in Step 2.
- **Actions:** "Cancel" (returns to Map) and "Confirm Pin Location" (advances to Step 2 with locked coordinates).

### 4.3 Step 2 — Restroom Details Form (`AddRestroomFormScreen`)

A clean, single-screen scrollable form structured into clear visual card groups:

1. **Facility Identification:**
   - **Restroom / Facility Name:** (Required, 1–100 characters). Label: "Facility Name", Placeholder: "e.g., Central Station Restroom, Ground Floor Cafe Restroom".
   - **Access Type:** (Required single select). Options: `Free`, `Paid`, `Customer Only`, `Key / Code Required`.
2. **Indoor Context & Directions (First-Class Feature):**
   - **Building Name / Landmark:** (Optional, 1–100 characters). Placeholder: "e.g., Terminal 2, Ayala Malls North".
   - **Floor Level:** (Optional, 1–20 characters). Placeholder: "e.g., Ground Floor, 2F, B1, Mezzanine".
   - **Building Section / Wing:** (Optional, 1–100 characters). Placeholder: "e.g., North Wing, Food Court, Gate 14".
   - **Unit or Specific Area:** (Optional, 1–100 characters). Placeholder: "e.g., Beside Cinema 3, Near Elevators".
   - **Indoor Directions Note:** (Optional, 1–500 characters). Placeholder: "e.g., Enter through main lobby, turn right past the coffee shop, located behind escalator".
3. **Accessibility & Stall Configuration:**
   - **PWD / Wheelchair Accessible:** Tri-state toggle (`Yes`, `No`, `Unspecified`).
   - **Baby Changing Station:** Tri-state toggle (`Yes`, `No`, `Unspecified`).
   - **Stalls / Gender Options:** Explicit selection: `Male` (`bool?`), `Female` (`bool?`), `All-Gender` (`bool?`). At least one must be explicitly confirmed `true`, OR all three may remain `null` (unknown). Three `false` booleans are rejected as an invalid specification of unknown.
4. **Hygiene & Amenities:**
   - Explicit tri-state toggles (`Yes`, `No`, `Unspecified`) for:
     - `Bidet available` (`hasBidet`)
     - `Toilet paper provided` (`hasToiletPaper`)
     - `Handwashing soap available` (`hasSoap`)
     - `Hand dryer available` (`hasHandDryer` — strictly hand dryer; paper towels are not conflated here)
5. **Access Instructions & Payment Details:**
   - **Access Instructions (`accessInstructions`):** (Optional, 1–300 characters). Canonical field for door codes, key pickup instructions, or customer-only entry guidance (e.g., "Ask barista for restroom key", "Door code printed on receipt").
   - **Fee Amount (`feeAmount`):** Required if and only if `accessType == AccessType.paid` (>= 0, <= 1,000,000). Prohibited and cleared when not paid.
   - **Fee Currency (`feeCurrency`):** Required if `feeAmount` is provided (exactly 3 alphabetic uppercase characters, e.g., "USD", "EUR", "PHP").
6. **Operating Hours:**
   - **REMOVED FROM PHASE 2.** Operating hours (24/7 toggle, opening/closing times, freeform hours notes) are deferred to a later dedicated availability feature due to the lack of an authoritative structured hours model.

---

## 5. Critical Data-Truth Architecture & Nullable Booleans

### 5.1 The Nullable Truth Contract

In the Phase 0 baseline (`lib/domain/models/restroom.dart`), default parameters were assigned non-nullable positive values (e.g. `hasToiletPaper = true`, `hasSoap = true`).

For Phase 2, LooRadar locks the authoritative representation of community-contributed properties to **nullable booleans** (`bool?`):

| Value | Semantic Meaning | Discovery Filter Behavior | Preview & List UI Presentation |
| :--- | :--- | :--- | :--- |
| `true` | Explicitly confirmed Yes | Matches positive filter (e.g., `toiletPaperOnly`) | Affirmative amenity badge displayed (e.g., "Toilet Paper") |
| `false` | Explicitly confirmed No | Excluded from positive filter | Strikethrough or "No toilet paper" or omitted badge |
| `null` | Unknown / Unspecified | Excluded from positive filter | Omitted from amenity list; never claimed affirmatively |

**Invariants:**
- `false` must NEVER mean both "No" and "Unknown".
- Missing or omitted fields in historical/existing documents decode as `null`.
- Existing documents are NOT silently rewritten in Phase 2.
- Discovery filters match ONLY explicit `true`.

### 5.2 The `RestroomDraft` Domain Model

Phase 2 introduces a dedicated input model:

`lib/domain/models/restroom_draft.dart`

```dart
enum TriStateAmenity {
  yes,
  no,
  unknown;

  bool? toNullableBool() {
    switch (this) {
      case TriStateAmenity.yes:
        return true;
      case TriStateAmenity.no:
        return false;
      case TriStateAmenity.unknown:
        return null;
    }
  }

  static TriStateAmenity fromNullableBool(bool? value) {
    if (value == null) return TriStateAmenity.unknown;
    return value ? TriStateAmenity.yes : TriStateAmenity.no;
  }
}

class RestroomDraft {
  final String name;
  final Coordinates coordinates;
  final AccessType accessType;

  // Indoor context
  final String? countryCode;
  final String? region;
  final String? city;
  final String? buildingName;
  final String? buildingSection;
  final String? floor;
  final String? unitOrArea;
  final String? landmark;
  final String? directionsNote;

  // Access & Pricing
  final String? accessInstructions;
  final double? feeAmount;
  final String? feeCurrency;

  // Stalls (Nullable)
  final bool? male;
  final bool? female;
  final bool? allGender;

  // Accommodations (Tri-State)
  final TriStateAmenity pwdAccessible;
  final TriStateAmenity babyChanging;

  // Hygiene amenities (Tri-State)
  final TriStateAmenity hasBidet;
  final TriStateAmenity hasToiletPaper;
  final TriStateAmenity hasSoap;
  final TriStateAmenity hasHandDryer;

  const RestroomDraft({
    required this.name,
    required this.coordinates,
    required this.accessType,
    this.countryCode,
    this.region,
    this.city,
    this.buildingName,
    this.buildingSection,
    this.floor,
    this.unitOrArea,
    this.landmark,
    this.directionsNote,
    this.accessInstructions,
    this.feeAmount,
    this.feeCurrency,
    this.male,
    this.female,
    this.allGender,
    this.pwdAccessible = TriStateAmenity.unknown,
    this.babyChanging = TriStateAmenity.unknown,
    this.hasBidet = TriStateAmenity.unknown,
    this.hasToiletPaper = TriStateAmenity.unknown,
    this.hasSoap = TriStateAmenity.unknown,
    this.hasHandDryer = TriStateAmenity.unknown,
  });

  /// Normalizes and validates all draft fields according to domain rules.
  List<String> validate() {
    final errors = <String>[];
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) errors.add('Facility name is required');
    if (trimmedName.length > 100) errors.add('Facility name cannot exceed 100 characters');

    // Coordinates validated through Coordinates domain object
    if (coordinates.latitude.isNaN || coordinates.latitude.isInfinite ||
        coordinates.latitude < -90.0 || coordinates.latitude > 90.0) {
      errors.add('Latitude must be a valid number between -90 and 90');
    }
    if (coordinates.longitude.isNaN || coordinates.longitude.isInfinite ||
        coordinates.longitude < -180.0 || coordinates.longitude > 180.0) {
      errors.add('Longitude must be a valid number between -180 and 180');
    }

    if (countryCode != null && (countryCode!.trim().length < 2 || countryCode!.trim().length > 3)) {
      errors.add('Country code must be 2-3 characters');
    }
    if (region != null && region!.trim().length > 100) errors.add('Region cannot exceed 100 characters');
    if (city != null && city!.trim().length > 100) errors.add('City cannot exceed 100 characters');
    if (buildingName != null && buildingName!.trim().length > 100) errors.add('Building name cannot exceed 100 characters');
    if (buildingSection != null && buildingSection!.trim().length > 100) errors.add('Building section cannot exceed 100 characters');
    if (floor != null && floor!.trim().length > 20) errors.add('Floor identifier cannot exceed 20 characters');
    if (unitOrArea != null && unitOrArea!.trim().length > 100) errors.add('Unit or area cannot exceed 100 characters');
    if (landmark != null && landmark!.trim().length > 100) errors.add('Landmark cannot exceed 100 characters');
    if (directionsNote != null && directionsNote!.trim().length > 500) errors.add('Directions note cannot exceed 500 characters');
    if (accessInstructions != null && accessInstructions!.trim().length > 300) {
      errors.add('Access instructions cannot exceed 300 characters');
    }

    if (accessType == AccessType.paid) {
      if (feeAmount == null || feeAmount!.isNaN || feeAmount! < 0 || feeAmount! > 1000000) {
        errors.add('Paid restrooms require a valid fee amount between 0 and 1,000,000');
      }
      if (feeCurrency == null || feeCurrency!.trim().length != 3 || !RegExp(r'^[A-Z]{3}$').hasMatch(feeCurrency!.trim())) {
        errors.add('Fee currency must be a valid 3-letter uppercase code (e.g., USD)');
      }
    } else {
      if (feeAmount != null) errors.add('Fee amount must be empty for non-paid restrooms');
      if (feeCurrency != null) errors.add('Fee currency must be empty for non-paid restrooms');
    }

    // Gender stall configuration: either at least one is explicitly true, or all are null (unknown)
    final hasExplicitGender = (male == true) || (female == true) || (allGender == true);
    final allGenderNull = (male == null) && (female == null) && (allGender == null);
    if (!hasExplicitGender && !allGenderNull) {
      errors.add('Select applicable gender stalls or leave all unspecified');
    }

    return errors;
  }
}
```

### 5.3 Enforcing Initial State & Aggregates

When converting a `RestroomDraft` to a public Firestore document:
- `status`: Strictly set to `'unverified'` (`RestroomStatus.unverified`).
- `averageRating`: Strictly `0.0`.
- `ratingCount`: Strictly `0`.
- `verificationCount`: Strictly `0`.
- `negativeVerificationCount`: Strictly `0`.
- `lastVerifiedAt`: Strictly `null`.
- `createdAt` and `updatedAt`: `FieldValue.serverTimestamp()`.
- Public document NEVER contains any contributor UID (`userUid`, `createdByUid`, `authorUid`, etc.).

---

## 6. Atomic Submission & Public/Private Separation

### 6.1 The Two-Document Batch Contract

A contribution must never create an orphan public restroom or an orphan private record. Submission executes a single atomic Firestore `WriteBatch`:

```text
WriteBatch
  ├── 1. SET /restrooms/{restroomId} (Public Document)
  └── 2. SET /contributions/restroom_{restroomId} (Private Document)
```

### 6.2 Bidirectional Atomic Verification

To strictly prove that both documents are newly created together in the same atomic operation, Firestore Security Rules must validate pre-state and post-state conditions on **BOTH sides**:

#### Public Restroom Side (`/restrooms/{restroomId}`)
1. **Pre-state check (Both must NOT exist prior to write):**
   - `!exists(/databases/$(database)/documents/restrooms/$(restroomId))`
   - `!exists(/databases/$(database)/documents/contributions/$('restroom_' + restroomId))`
2. **Post-state check (Paired contribution MUST exist after write):**
   - `existsAfter(/databases/$(database)/documents/contributions/$('restroom_' + restroomId))`
3. **Data Linkage check:**
   - `let contrib = getAfter(/databases/$(database)/documents/contributions/$('restroom_' + restroomId));`
   - `contrib.data.contributionType == 'restroom'`
   - `contrib.data.resourceId == restroomId`
   - `contrib.data.restroomId == restroomId`
   - `contrib.data.userUid == request.auth.uid`
   - `contrib.data.moderationState == 'pending'`

#### Private Contribution Side (`/contributions/{contributionId}`)
1. **Document ID Determinism:**
   - `contributionId == ('restroom_' + request.resource.data.resourceId)`
2. **Pre-state check (Both must NOT exist prior to write):**
   - `!exists(/databases/$(database)/documents/contributions/$(contributionId))`
   - `!exists(/databases/$(database)/documents/restrooms/$(request.resource.data.resourceId))`
3. **Post-state check (Paired public restroom MUST exist after write):**
   - `existsAfter(/databases/$(database)/documents/restrooms/$(request.resource.data.resourceId))`
4. **Data Linkage check:**
   - `let rest = getAfter(/databases/$(database)/documents/restrooms/$(request.resource.data.resourceId));`
   - `rest.data.id == request.resource.data.resourceId`
   - `rest.data.status == 'unverified'`
   - `request.resource.data.id == contributionId`
   - `request.resource.data.restroomId == request.resource.data.resourceId`
   - `request.resource.data.contributionType == 'restroom'`
   - `request.resource.data.moderationState == 'pending'`
   - `request.resource.data.userUid == request.auth.uid`

### 6.3 Orphaning & Out-of-Order Attack Vectors Prevented

This bidirectional contract strictly prevents:
1. **Restroom created without contribution:** Fails because `existsAfter()` on contribution path returns false.
2. **Contribution created without restroom:** Fails because `existsAfter()` on restroom path returns false.
3. **Contribution pre-created first, restroom created later:** Fails because restroom create requires `!exists()` on contribution, which evaluates to false.
4. **Restroom pre-created first, contribution created later:** Fails because contribution create requires `!exists()` on restroom, which evaluates to false.
5. **Contribution linked to another restroom:** Fails because `resourceId` must match the restroom ID on both documents.
6. **Forged contribution ID:** Fails because contribution ID is strictly enforced as `'restroom_' + resourceId`.
7. **Forged UID:** Fails because `userUid == request.auth.uid`.

*Note on Rules Primitives:* `getAfter()` alone does NOT prove same-batch creation because it resolves to an existing document if one was committed previously. Combining `!exists(...)` (ensuring neither document existed prior to the write) with `existsAfter(...)` / `getAfter(...)` (ensuring both documents exist after the write with cross-referenced keys) provides a watertight cryptographic proof of simultaneous batch creation.

---

## 7. Firestore Security Rules Specification

### 7.1 Security Invariants for Phase 2

1. **Unauthenticated Writes Rejected:** `isAuthenticated()` is mandatory.
2. **Status Restriction:** Restrooms created by clients must have `request.resource.data.status == 'unverified'`.
3. **ID Invariant:** `request.resource.data.id == restroomId`.
4. **Aggregate Protection:** Initial aggregates must be 0 or null (`isValidInitialAggregates`).
5. **No Contributor UID:** Public document rejects all UID-like fields (`hasNoContributorUid`).
6. **Create-Only Public Restrooms:** Public restroom updates and deletes are strictly prohibited in Phase 2 (`allow update, delete: if false;`).
7. **Bidirectional Atomic Pairing:** Validated via pre-state and post-state rules on both paths.

### 7.2 Target Rules Expression

```javascript
// Restrooms: Public facilities (CREATE-ONLY in Phase 2)
match /restrooms/{restroomId} {
  // Publicly readable by all users
  allow read: if true;

  // Only authenticated users can contribute; requires bidirectional atomic pairing
  allow create: if isAuthenticated() &&
                   !exists(/databases/$(database)/documents/restrooms/$(restroomId)) &&
                   !exists(/databases/$(database)/documents/contributions/$('restroom_' + restroomId)) &&
                   existsAfter(/databases/$(database)/documents/contributions/$('restroom_' + restroomId)) &&
                   isValidRestroomCreate(restroomId);

  // Facility updates and deletions are strictly disabled in Phase 2
  allow update: if false;
  allow delete: if false;
}

function isValidRestroomCreate(restroomId) {
  let contributionPath = /databases/$(database)/documents/contributions/$('restroom_' + restroomId);
  let contrib = getAfter(contributionPath);

  return isValidRestroomSchema(request.resource.data) &&
         request.resource.data.id == restroomId &&
         request.resource.data.status == 'unverified' &&
         isValidInitialAggregates(request.resource.data) &&
         contrib != null &&
         contrib.data.contributionType == 'restroom' &&
         contrib.data.resourceId == restroomId &&
         contrib.data.restroomId == restroomId &&
         contrib.data.userUid == request.auth.uid &&
         contrib.data.moderationState == 'pending';
}

// Contributions: Private tracking & audit log
match /contributions/{contributionId} {
  // Strictly private: users may only read their own contributions
  allow read: if isAuthenticated() && resource.data.userUid == request.auth.uid;

  // Authenticated users can log contribution metadata with bidirectional pairing
  allow create: if isAuthenticated() &&
                   !exists(/databases/$(database)/documents/contributions/$(contributionId)) &&
                   isValidContributionCreate(contributionId);

  allow update, delete: if false;
}

function isValidContributionCreate(contributionId) {
  let data = request.resource.data;

  // For restroom contributions, enforce strict bidirectional batch pairing
  return isValidContribution(data) &&
         data.userUid == request.auth.uid &&
         (data.contributionType != 'restroom' || (
           contributionId == ('restroom_' + data.resourceId) &&
           data.id == contributionId &&
           data.restroomId == data.resourceId &&
           data.moderationState == 'pending' &&
           !exists(/databases/$(database)/documents/restrooms/$(data.resourceId)) &&
           existsAfter(/databases/$(database)/documents/restrooms/$(data.resourceId)) &&
           getAfter(/databases/$(database)/documents/restrooms/$(data.resourceId)).data.id == data.resourceId &&
           getAfter(/databases/$(database)/documents/restrooms/$(data.resourceId)).data.status == 'unverified'
         ));
}
```

---

## 8. Canonical Document ID & Idempotent Submission

### 8.1 Stable Submission ID Allocation

A single logical contribution workflow generates a stable `submissionId` / `restroomId` **ONCE**, at the moment the user taps "Submit Restroom" and validation passes:

```text
Draft State
  ↓ [User taps Submit]
Validate Draft
  ↓ [Valid]
Check if draft has assigned submissionId:
  ├─ None: Allocate canonical restroomId = _collection.doc().id
  └─ Present: Reuse existing restroomId
  ↓
Run Bounded Duplicate Detection
  ├─ Matches found → Show advisory warning → User confirms "Different Restroom"
  └─ No matches → Proceed to submit
  ↓
Submit Batch (restrooms/{restroomId} + contributions/restroom_{restroomId})
  ├─ SUCCESS → Clear draft, trigger map sync
  ├─ RECOVERABLE FAILURE / NETWORK DROP → Retain SAME restroomId on draft
  └─ RETRY → Attempt write using SAME restroomId
```

The `restroomId` remains attached to the draft across all recoverable retry attempts. A new ID is allocated if and only if the user cancels or discards the draft to start a completely new contribution.

### 8.2 Ambiguous Commit Reconciliation

If a network timeout or connection drop occurs during `batch.commit()`, the write may or may not have succeeded on the server. Before attempting a retry:

1. **Reconciliation Read:** The client issues read requests for:
   - `restrooms/{restroomId}`
   - `contributions/restroom_{restroomId}`
2. **State Evaluation:**
   - **Both exist and match contract:** The write succeeded before the network dropped. Treat the operation as an immediate **SUCCESS**, navigate to map, and synchronize.
   - **Neither exists:** The write failed before committing. Safely re-execute the batch write using the **SAME** `restroomId`.
   - **Only one exists:** This represents an invariant violation (e.g. partial write or race). Surface a clear, recoverable error to the user without attempting to create an orphaned second facility.

---

## 9. Bounded Duplicate Detection Engine & Scoring Model

### 9.1 Spatial Search Reusing Phase 1 GIS Primitives

Duplicate detection reuses the proven Phase 1 spatial algorithm:
- Center: `(draft.coordinates.latitude, draft.coordinates.longitude)`.
- Search radius: 500 meters.
- Primitive: `GeohashService.getCandidatePrefixes(coordinates, radiusInMeters: 500)`.
- Range cap: Maximum **16 ranges** (`take(AppConstants.maxGeohashQueryRanges)`), matching the Phase 1 GIS safety model.
- Per-range read limit: `.limit(20)`.
- **Cost Math & Read Upper Bound:**
  - Theoretical raw documents read ceiling: `16 ranges × 20 docs = 320 documents`.
  - Candidates are deduplicated in memory by `restroomId`.
  - Candidates are filtered with exact Haversine distance ($D \le 500\text{m}$).
  - Truncation / range cap flags duplicate scan as `partial`.
  - A partial duplicate scan **NEVER implies "no duplicates exist"**.
  - Duplicate detection is strictly **advisory**; users are never blocked from submitting.

### 9.2 String Normalization

All text fields are normalized prior to comparison:
- Lowercase conversion.
- Unicode-safe whitespace trimming.
- Punctuation removal (strip characters outside `[a-z0-9\s]`).
- Whitespace collapse (multiple spaces collapsed to single space).
- Tokenization into word sets.

### 9.3 Explicit Deterministic Scoring Formula

Each nearby candidate facility $C$ is compared against draft $D$:

1. **Distance Metric ($S_{\text{dist}}$):**
   - $D < 30\text{m}$: `1.0`
   - $30\text{m} \le D < 100\text{m}$: `0.7`
   - $100\text{m} \le D < 300\text{m}$: `0.3`
   - $300\text{m} \le D \le 500\text{m}$: `0.1`
2. **Name Similarity Metric ($S_{\text{name}}$):**
   - Normalized Dice coefficient / token overlap: $\frac{2 \times |T_D \cap T_C|}{|T_D| + |T_C|} \in [0.0, 1.0]$.
3. **Building Context Metric ($S_{\text{building}}$):**
   - Both have non-empty `buildingName` and match: `1.0`.
   - Both have non-empty `buildingName` and conflict: `0.0`.
   - Either is empty/unspecified: `0.5` (neutral).
4. **Section / Unit Metric ($S_{\text{section}}$):**
   - Match on `buildingSection` or `unitOrArea`: `1.0`.
   - Either unspecified: `0.5`.
   - Conflicting: `0.0`.
5. **Landmark Metric ($S_{\text{landmark}}$):**
   - Match on `landmark`: `1.0`.
   - Either unspecified: `0.5`.
   - Conflicting: `0.0`.
6. **Floor Conflict Penalty ($P_{\text{floor}}$):**
   - If both have non-empty normalized `floor` and they **conflict** (e.g. "B1" vs "4F"): `P_{\text{floor}} = 0.40`.
   - If both have non-empty normalized `floor` and they **match**: `P_{\text{floor}} = 0.0` (with $+0.05$ bonus).
   - If either is empty/unspecified: `P_{\text{floor}} = 0.0`.

**Weighted Score Formula:**
```text
rawScore = (0.40 * S_dist) + (0.30 * S_name) + (0.15 * S_building) + (0.10 * S_section) + (0.05 * S_landmark) - P_floor
score = clamp(rawScore, 0.0, 1.0)
```

### 9.4 Classification Thresholds & Tie-Breaking

- **HIGH Duplicate Warning:** `score >= 0.75`
- **MODERATE Duplicate Warning:** `score >= 0.50`
- **DISTINCT Facility (No Warning):** `score < 0.50`

Floor conflicts strongly suppress false-positive warnings, allowing legitimate separate facilities in the same building (e.g., Floor 1 vs Floor 4) to proceed without annoying duplicate alerts.

**Deterministic Tie-Breaking:**
When presenting candidates, order by:
1. `score` descending
2. `distance` ascending
3. `normalized name` ascending
4. `restroomId` ascending

Display at most the **top 3** candidate warnings.

### 9.5 Advisory UX Contract

If one or more candidates score $\ge 0.50$:
1. Display a modal bottom sheet:
   - **Header:** "Similar restrooms found nearby"
   - **Explanation:** "We found an existing restroom near this location. Is this the same facility?"
   - **Candidate Cards:** Up to 3 candidates showing name, distance, floor, and access type.
   - **Actions:**
     - `View Existing Restroom`: Dismisses sheet, closes form, centers map on candidate, and opens preview sheet.
     - `No, It's a Different Restroom`: Acknowledges warning and proceeds to execute batch write with stable `restroomId`.

---

## 10. Concurrency & Abuse Prevention Architecture

### 10.1 Client-Side Debounce (UX Protection)
- Tapping "Submit" immediately disables the button and all inputs, showing a progress indicator.
- Client maintains in-flight state to prevent double-tap submissions.

### 10.2 Production Abuse-Control Gate
A client-side disabled button is UX protection, not abuse protection.

To ensure production abuse resistance, Phase 2 defines an explicit **Production Release Gate**:

> [!IMPORTANT]
> **Phase 2 community contribution writes must NOT be enabled in production until enforceable per-UID rate limiting exists.**

**Enforcement Architecture:**
- A private per-user tracking document: `contributionRateLimits/{uid}`.
- Updated via a trusted server boundary (Cloud Function or Firestore rule-backed counter).
- Evaluated baseline policy:
  - Maximum **10 restroom submissions per UID per 24 hours**.
  - Maximum burst **3 submissions per UID per 10 minutes**.
- Split across milestones:
  - **P2.1–P2.5:** Develops core contribution models, repository batch writes, client debounce, and strict rules.
  - **P2.6:** Validates the production rate-limiting release gate before opening production contribution writes.

---

## 11. Auth & App Check Architecture

### 11.1 Separate Enforcement Boundaries
Firebase App Check and Firestore Security Rules are distinct layers:
- **Firebase App Check:** Validates that incoming requests originate from a genuine, untampered instance of the official LooRadar mobile app at the Firebase service boundary.
- **Firestore Security Rules:** Enforces authenticated identity (`request.auth.uid`), data schema validation, status invariants (`unverified`), zero aggregates, and bidirectional atomic batch pairing.

### 11.2 Error Messaging
- Do NOT map all `permission-denied` errors to "App verification failed".
- When an operation fails:
  - If network unavailable: `"Connection failed. Please check your internet connection."`
  - If permission denied / App Check rejected: `"Unable to save restroom. Please ensure you are using the official app."`
  - Form state is strictly preserved on all errors.

---

## 12. Authoritative Map Discovery Synchronization

### 12.1 Elimination of Permanent Optimistic Injection
Phase 1 established the discovery repository and viewport query pipeline as the **single authoritative source of truth**.

In Phase 2, successful contributions do NOT inject the new restroom permanently into the `MapDiscoveryNotifier` source results. Instead, the workflow follows canonical discovery:

1. Batch write commits successfully to Firestore.
2. Form screen is popped, returning to `MapDiscoveryScreen`.
3. Map camera animates to the new restroom coordinates `(draft.coordinates.latitude, draft.coordinates.longitude)` at `zoom: 16.5`.
4. Camera idle trigger initiates canonical viewport query refresh through the existing debounced pipeline.
5. The repository returns the newly created facility (retrieved from Firestore server or local cache).
6. Notifier automatically selects the new facility by its `restroomId` and opens `RestroomPreviewSheet`.
7. Preview sheet prominently displays the `"Unverified"` status badge.

---

## 13. Read and Cost Upper Bounds for Phase 2

| Operation | Query / Action | Maximum Reads | Cost Guardrail |
| :--- | :--- | :--- | :--- |
| **Location Pinpoint** | Interactive Map Drag | 0 Firestore reads | Client-side map rendering; no reverse geocoding API calls. |
| **Duplicate Detection** | Nearby candidate search | Max 320 raw reads (theoretical ceiling) | 16 ranges × 20 limit; deduplicated and filtered in memory. |
| **Restroom Submission** | Atomic Batch Write | 2 Firestore writes | 1 public write (`restrooms/`), 1 private write (`contributions/`). |
| **Reconciliation Read** | Retry ambiguity check | Max 2 Firestore reads | Direct document lookups for `restrooms/{id}` and `contributions/restroom_{id}`. |
| **Anonymous Auth** | Background sign-in | 0 Firestore reads | Native Firebase Auth token exchange. |

---

## 14. Phase 2 Implementation Milestones

### P2.0 — Specification & Task Contract (ACTIVE)
- Author this specification document (`docs/09-phase-2-add-restroom.md`).
- Update `docs/STATUS.md`, `docs/02-data-model.md`, and `docs/03-privacy-security.md`.
- Ensure draft PR #4 is updated and ready for exact-head audit.
- *P2.1 implementation is BLOCKED pending independent P2.0 specification re-audit.*

### P2.1 — Contribution Domain Model (`RestroomDraft`), Nullable Schema Migration, Repository Batch Write Contract, Firestore Rules & Emulator Tests
- Implement `RestroomDraft`, `TriStateAmenity`, and full domain validation.
- Migrate `Restroom` public domain model to nullable booleans (`bool?` for amenities/stalls).
- Update `RestroomFirestoreCodec` for nullable booleans and new `accessInstructions` field.
- Update `RestroomRepository` interface with `Future<Restroom> submitRestroom(RestroomDraft draft)`.
- Implement atomic batch write in `FirestoreRestroomRepository` writing `/restrooms/{id}` and `/contributions/restroom_{id}` with stable ID allocation and reconciliation.
- Update `InMemoryRestroomRepository` with draft and batch support.
- Update `firestore.rules`: create-only (`allow update, delete: if false;`), status `'unverified'`, zero aggregates, bidirectional pairing (`!exists` + `existsAfter` / `getAfter`).
- Author comprehensive Firestore emulator tests in `rules_tests/p2_add_restroom_rules_test.js` (29 test cases).
- *Explicitly excludes form UI.*

### P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX
- Implement `AddRestroomLocationScreen` with interactive center crosshair / draggable pin on Google Maps.
- Enforce zoom floor (`zoom >= 15.0`) with visual hint.
- Display live formatted coordinate readouts (5 decimal places) via `Coordinates`.
- Unit and widget tests for location selection interactions.

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management
- Implement `AddRestroomFormScreen` with organized card sections (Basic Info, Indoor Directions, Accessibility, Amenities, Access Instructions & Fee).
- Implement tri-state amenity selector widgets.
- Implement `AddRestroomNotifier` form state management and input validation.
- Unit tests for form validation and widget tests for form rendering and error states.

### P2.4 — Bounded Duplicate Detection Engine & Advisory Warning UX
- Implement `DuplicateDetectionService` with 500m geohash candidate retrieval (max 16 ranges, `.limit(20)`) and deterministic scoring model.
- Implement `DuplicateWarningSheet` advisory UI showing top 3 candidates.
- Unit tests for similarity heuristics and edge cases; widget tests for modal display and button actions.

### P2.5 — End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback
- Connect anonymous authentication lifecycle.
- Wire submit action through repository batch write with stable submission ID and ambiguous commit reconciliation.
- Sync successful submissions with canonical viewport refresh and preview selection.
- End-to-end integration and widget tests.

### P2.6 — Hardening, Accessibility, Abuse Rate-Limiting Gate & Validation
- Audit touch targets (>= 48×48), semantic labels, and contrast.
- Verify production abuse rate-limiting release gate.
- Run complete test suite (`flutter test`, Firestore emulator rules tests).
- Validate platform compilation (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`).
- Update `docs/STATUS.md` and prepare Phase 2 for audit.

---

## 15. Testing Contract

### 15.1 Unit Tests
- `RestroomDraft` field validations (all fields, coordinate limits, text lengths, currency format, fee constraints).
- `TriStateAmenity` mapping to nullable booleans (`true`, `false`, `null`).
- Stable submission ID generation and idempotency retention across retries.
- Duplicate detection scoring algorithm (exact name matches, partial matches, conflicting floors, distance weighting, tie-breaking).

### 15.2 Firestore Security Rules Emulator Tests (29 Scenarios in P2.1)

#### Public/Private Pair Invariants (10 Tests)
1. Valid atomic restroom + contribution pair -> ALLOW.
2. Restroom created without contribution -> REJECT.
3. Contribution created without restroom -> REJECT.
4. Pre-existing contribution then restroom created -> REJECT.
5. Pre-existing restroom then contribution created -> REJECT.
6. Mismatched `resourceId` between restroom and contribution -> REJECT.
7. Mismatched `restroomId` between restroom and contribution -> REJECT.
8. Wrong deterministic contribution ID format (not `restroom_{id}`) -> REJECT.
9. Forged `userUid` in contribution record -> REJECT.
10. Wrong `moderationState` on creation (not `pending`) -> REJECT.

#### Public Restroom Creation & Restrictions (5 Tests)
11. Unauthenticated restroom creation -> REJECT.
12. Attempt to create restroom with `status: 'active'` -> REJECT.
13. Attempt to create restroom with non-zero initial aggregates -> REJECT.
14. Contributor UID injected into public restroom document -> REJECT.
15. Public `id` field does not match Firestore document ID -> REJECT.

#### Updates & Deletions Prohibited (5 Tests)
16. Original creator attempts direct update of public restroom -> REJECT.
17. Another authenticated user attempts direct update of public restroom -> REJECT.
18. Client attempts status modification on public restroom -> REJECT.
19. Client attempts coordinate or geohash update on public restroom -> REJECT.
20. Client attempts deletion of public restroom -> REJECT.

#### Nullable Truth & Field Validation (5 Tests)
21. Explicit `true` amenity allowed -> ALLOW.
22. Explicit `false` amenity allowed -> ALLOW.
23. Explicit `null` / omitted amenity allowed -> ALLOW.
24. Invalid amenity data type (e.g. string instead of bool) -> REJECT.
25. Missing optional amenity decodes as unknown `null`.

#### Idempotency & Reconciliation (4 Tests)
26. Submission retry reuses identical `restroomId`.
27. Reconciliation reads verify existing pair and return success on lost network ack.
28. Retry after ambiguous failure does not generate a second restroom ID.
29. In-flight submit debounce prevents concurrent duplicate batch writes.

### 15.3 Widget & State Tests (Milestones P2.2–P2.5)
- `AddRestroomLocationScreen`: Zoom floor disables/enables "Confirm Pin" button.
- `AddRestroomFormScreen`: Form validation errors render appropriately.
- Tri-state amenity toggles switch between Yes, No, and Unspecified states.
- Duplicate advisory sheet displays candidate facilities and handles "View Existing" vs "Continue" actions.
- Submission button enters loading state and disables inputs while in flight.

---

## 16. Non-Goals (Explicitly Excluded from Phase 2)

- **Photo Uploads:** Deferred to Phase 5.
- **Rating / Review Submission:** Phase 3.
- **Verification / Reporting Submission:** Phase 3.
- **Public Restroom Editing / Updates:** Deferred to a later explicitly designed facility editing workflow.
- **Google Places Autocomplete / Geocoding API:** Prohibited due to cost and architecture invariants.
- **Routing / Turn-by-Turn Navigation:** Prohibited; external navigation apps handle routing.
- **Social Login / Traditional User Accounts:** Prohibited in V1.
- **Moderation Dashboard:** Phase 4.

---

## 17. Definition of Done for Phase 2

Phase 2 is complete when:

1. Users can initiate contribution from the map shell, pinpoint an exact entrance on the map with zoom enforcement, and input complete facility and indoor direction details.
2. Form fields adhere to data-truth invariants: unconfirmed amenities are recorded as `null` and never defaulted to positive claims.
3. Newly contributed restrooms are saved with `status: 'unverified'` and zero initial aggregates.
4. Submissions are atomic across `/restrooms/{id}` and `/contributions/restroom_{id}` via Firestore `WriteBatch`, bidirectionally enforced by Security Rules.
5. Contributor UID is never stored in public documents; private ownership is secured in `/contributions/`.
6. Public restrooms are strictly create-only in Phase 2; updates and deletions are rejected.
7. Bounded duplicate detection alerts users of potential nearby matches without blocking submission.
8. Submissions are idempotent, with stable ID retention and ambiguous commit reconciliation.
9. Submitting a restroom immediately reflects on the discovery map via canonical viewport discovery and preview selection.
10. The production abuse rate-limiting release gate is verified.
11. All format, analysis, Flutter tests, and emulator tests pass.
12. `docs/STATUS.md` is updated with accurate evidence.
