# LooRadar Phase 2 — Add Restroom

## 1. Goal

Implement production-quality community restroom contribution with zero mandatory login friction, high data truthfulness, low infrastructure cost, robust abuse resistance, and strict privacy preservation.

Phase 2 enables any user to contribute new restrooms directly from the map-first interface. It builds strictly upon the Phase 0 foundational abstractions and Phase 1 map discovery pipeline, without prematurely introducing ratings submission, verification/reporting workflows, photo uploads, routing, or paid third-party APIs.

---

## 2. Phase 2 Outcomes

By the end of Phase 2, a user should be able to:

1. **Initiate Contribution:** Tap the primary "Add" action button or navigation tab from the map discovery shell.
2. **Refine Location:** Interactively position a map pin with high visual clarity, utilizing a crosshair/draggable marker with live coordinate feedback and zoom-level guidance.
3. **Input Facility Details:** Complete a structured, task-focused form covering basic facility identity, detailed indoor directions (building, floor, wing, landmark), accessibility features, gender/stall configurations, hygiene amenities, payment terms, and operational access notes.
4. **Preserve Data Truth:** Ensure unconfirmed or unknown amenities are never silently recorded as positive verified claims.
5. **Receive Duplicate Guidance:** Benefit from a lightweight, bounded duplicate-detection engine that alerts the user if an existing facility matches nearby coordinates and building context, without blocking legitimate separate facilities.
6. **Submit Atomically & Anonymously:** Submit the facility via a single atomic Firestore batch write paired with a private contribution record, authenticated seamlessly via Firebase Anonymous Authentication without requiring personal data or traditional credentials.
7. **Immediate Map Feedback:** Receive clear confirmation feedback, automatically transition back to the map centered on the newly added facility, and observe the new restroom rendered immediately with an `unverified` status badge.
8. **Experience Resilience:** Benefit from clear error handling, in-flight submission debouncing, offline/network failure preservation (inputs are never discarded on failure), and accessible touch targets.

---

## 3. Locked Phase 2 Principles

- **Product Name:** **LooRadar**.
- **Map-First, Mobile-First:** Contribution originates from and completes directly back into the map discovery context.
- **Zero Login Friction:** Powered exclusively by Firebase Anonymous Authentication for V1; traditional accounts or social logins are strictly prohibited.
- **Strict Privacy Boundary:** Contributor identity (`request.auth.uid`) is NEVER stored in the publicly readable restroom document.
- **Atomic Public/Private Writes:** Every public restroom document write must be accompanied by an atomic private contribution record in `contributions/` within the same `WriteBatch`.
- **Data Truthfulness:** Amenities and features must use explicit opt-in or tri-state representations (`true`, `false`, `null` / unselected); form defaults must never convert unknown attributes into positive claims.
- **Initial Facility State:** All newly contributed community restrooms MUST be assigned `status: RestroomStatus.unverified`.
- **Zero Aggregate Tampering:** Initial aggregate statistics must be strictly zeroed (`averageRating = 0.0`, `ratingCount = 0`, `verificationCount = 0`, `negativeVerificationCount = 0`, `lastVerifiedAt = null`).
- **Bounded Infrastructure & Zero Paid APIs:** Zero reliance on Google Places API, Geocoding API, Street View, or external paid lookup services. Duplicate detection runs strictly on bounded Firestore geohash queries.
- **Advisory, Non-Blocking Duplicate Warning:** Duplicate detection is an advisory warning to guide the user, never a hard submission block.
- **Canonical UI/UX Reference:** Preserves visual and interaction alignment with `docs/assets/looradar-mobile-ux-reference.png` and `docs/06-ui-ux-reference.md`.

---

## 4. User Journey & Screen Architecture

```text
Map Discovery Shell
  ↓ [Tap Add (+)]
Step 1: Location Pinpoint (AddRestroomLocationScreen)
  ├─ Pan/drag map under center target
  ├─ Zoom floor enforcement (zoom ≥ 15.0)
  └─ Live coordinate readouts
  ↓ [Confirm Location]
Step 2: Restroom Details & Amenities (AddRestroomFormScreen)
  ├─ Basic Info (Name, Access Type)
  ├─ Indoor Directions (Building, Floor, Wing, Landmark, Directions Note)
  ├─ Accommodations & Amenities (PWD, Baby Change, Stalls, Bidet, Paper, Soap)
  └─ Payment / Key Notes (Fee amount/currency, Key instructions)
  ↓ [Submit Restroom]
Duplicate Detection Evaluation (Advisory)
  ├─ No match found → Proceed directly to Batch Write
  └─ Match found → Advisory Modal Sheet
       ├─ [View Existing Restroom] → Open Preview on Map & Cancel Submit
       └─ [No, Create New Restroom] → Proceed to Batch Write
  ↓ [Batch Write via Anonymous Auth]
Success Feedback & Map Synchronization
  ├─ Show success toast/snackbar
  ├─ Center map camera on new pin
  ├─ Optimistically update local discovery cache
  └─ Open preview sheet showing newly added unverified restroom
```

### 4.1 Entry Points

1. **Bottom Navigation Bar:** Tab index 2 ("Add") in `MainShellScreen`.
2. **Contextual Action:** Tapping "Add Restroom" from an empty discovery state or preview sheet when enabled.

### 4.2 Step 1 — Location Pinpoint (`AddRestroomLocationScreen`)

- **Initial Coordinates:** Defaults to the current map camera target or user's physical GPS location if foreground permission is granted. If neither is available, defaults to default configured city coordinates.
- **Interactive Pin Adjustment:** Map renders a prominent crosshair target or custom marker in the center. As the user pans and zooms, the coordinates update dynamically.
- **Zoom Level Floor:** Users must zoom in to at least `zoom >= 15.0` (recommended `16.0`) before the "Confirm Location" button is enabled. A gentle prompt ("Zoom in closer to pinpoint the exact restroom entrance") ensures high geographic accuracy.
- **Coordinate Display:** Shows current latitude and longitude formatted to 5 decimal places (~1.1 meter precision).
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
   - **Stalls / Gender Options:** Multi-select chips: `Male`, `Female`, `All-Gender / Gender-Neutral`.
4. **Hygiene & Amenities:**
   - Explicit toggles/checkboxes for:
     - `Bidet available`
     - `Toilet paper provided`
     - `Handwashing soap available`
     - `Hand dryer or paper towels`
5. **Fee & Key Details (Conditional):**
   - Visible if `AccessType.paid`:
     - **Fee Amount:** Numeric (>= 0).
     - **Currency Code:** 3-character string (default: user locale or empty).
   - Visible if `AccessType.keyRequired` or `AccessType.customerOnly`:
     - **Key / Access Instructions:** Text field (e.g., "Ask cashier for key", "Door code printed on receipt").
6. **Operating Hours (Optional):**
   - 24/7 toggle or opening/closing hours notes.

---

## 5. Critical Data-Truth Architecture & `RestroomDraft`

### 5.1 The Problem with Existing Phase 0 Defaults

In the Phase 0 baseline (`lib/domain/models/restroom.dart`), default parameters were assigned non-nullable positive values:
- `accessType = AccessType.free`
- `male = true`
- `female = true`
- `hasToiletPaper = true`
- `hasSoap = true`
- `status = RestroomStatus.active`

If a user contributes a facility and leaves checkboxes unselected, defaulting them to `true` produces **false claims** (e.g., claiming free toilet paper and soap exist when they were never verified).

### 5.2 The `RestroomDraft` Domain Model

To strictly preserve data truth, Phase 2 introduces a dedicated input model:

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
  final double latitude;
  final double longitude;
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

  // Pricing / Access
  final double? feeAmount;
  final String? feeCurrency;
  final String? keyOrCodeNote;

  // Stalls
  final bool male;
  final bool female;
  final bool allGender;

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
    required this.latitude,
    required this.longitude,
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
    this.feeAmount,
    this.feeCurrency,
    this.keyOrCodeNote,
    this.male = false,
    this.female = false,
    this.allGender = false,
    this.pwdAccessible = TriStateAmenity.unknown,
    this.babyChanging = TriStateAmenity.unknown,
    this.hasBidet = TriStateAmenity.unknown,
    this.hasToiletPaper = TriStateAmenity.unknown,
    this.hasSoap = TriStateAmenity.unknown,
    this.hasHandDryer = TriStateAmenity.unknown,
  });

  /// Validates all draft fields according to domain rules.
  List<String> validate() {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Facility name is required');
    if (name.trim().length > 100) errors.add('Facility name cannot exceed 100 characters');
    if (latitude < -90.0 || latitude > 90.0) errors.add('Latitude must be between -90 and 90');
    if (longitude < -180.0 || longitude > 180.0) errors.add('Longitude must be between -180 and 180');
    if (buildingName != null && buildingName!.length > 100) errors.add('Building name too long');
    if (floor != null && floor!.length > 20) errors.add('Floor identifier too long');
    if (directionsNote != null && directionsNote!.length > 500) errors.add('Directions note cannot exceed 500 characters');
    if (accessType == AccessType.paid) {
      if (feeAmount == null || feeAmount! < 0) errors.add('Paid restrooms require a valid fee amount');
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

#### Document 1: Public Restroom (`/restrooms/{restroomId}`)

- **Document ID:** Generated on the client using `_firestore.collection('restrooms').doc().id`.
- **Publicly Readable:** Yes (`allow read: if true`).
- **Data Schema:**
  - `id`: Exact match with `restroomId`.
  - `name`, `latitude`, `longitude`, `geohash`: Validated spatial and identity primitives.
  - Context fields: `buildingName`, `floor`, `landmark`, `directionsNote`, etc.
  - Amenities: Stored as sanitized booleans or nulls.
  - Aggregates: Explicitly 0 / null.
  - `status`: `'unverified'`.
  - Timestamps: `createdAt`, `updatedAt`.
  - **Contributor ID:** STABLE PROHIBITION. Zero contributor identity fields.

#### Document 2: Private Contribution (`/contributions/restroom_{restroomId}`)

- **Document ID:** Deterministic format: `restroom_{restroomId}` (allowing direct `getAfter()` rules validation).
- **Private:** Only readable by the authenticated creator (`resource.data.userUid == request.auth.uid`).
- **Data Schema:**
  - `id`: `'restroom_' + restroomId`
  - `contributionType`: `'restroom'`
  - `resourceId`: `restroomId`
  - `restroomId`: `restroomId`
  - `userUid`: `request.auth.uid`
  - `moderationState`: `'pending'`
  - `createdAt`: `FieldValue.serverTimestamp()`
  - `updatedAt`: `FieldValue.serverTimestamp()`

---

## 7. Firestore Security Rules Specifications

### 7.1 Security Invariants

In `firestore.rules`:

1. **Unauthenticated Writes Rejected:** `isAuthenticated()` is mandatory.
2. **Status Restriction:** Restrooms created by clients must have `request.resource.data.status == 'unverified'`.
3. **ID Invariant:** `request.resource.data.id == restroomId`.
4. **Aggregate Protection:** Initial aggregates must be 0 or null (`isValidInitialAggregates`).
5. **No Contributor UID:** Public document rejects all UID-like fields (`hasNoContributorUid`).
6. **Atomic Contribution Validation:** The creation of `/restrooms/{restroomId}` is authorized IF AND ONLY IF an atomic private contribution record `/contributions/restroom_{restroomId}` is created simultaneously in the same transaction/batch.

### 7.2 Target Rules Expression

```javascript
function isValidRestroomCreate(restroomId) {
  let contributionPath = /databases/$(database)/documents/contributions/$('restroom_' + restroomId);
  return isValidRestroomSchema(request.resource.data) &&
         request.resource.data.id == restroomId &&
         request.resource.data.status == 'unverified' &&
         isValidInitialAggregates(request.resource.data) &&
         // Atomic pairing check via getAfter
         getAfter(contributionPath) != null &&
         getAfter(contributionPath).data.contributionType == 'restroom' &&
         getAfter(contributionPath).data.resourceId == restroomId &&
         getAfter(contributionPath).data.userUid == request.auth.uid;
}

match /restrooms/{restroomId} {
  allow read: if true;
  allow create: if isAuthenticated() && isValidRestroomCreate(restroomId);
  allow update: if isAuthenticated() && isValidRestroomUpdate();
  allow delete: if false;
}

match /contributions/{contributionId} {
  allow read: if isAuthenticated() && resource.data.userUid == request.auth.uid;
  allow create: if isAuthenticated() &&
                   isValidContribution(request.resource.data) &&
                   request.resource.data.userUid == request.auth.uid;
  allow update, delete: if false;
}
```

---

## 8. Canonical Document ID & Repository Debt Resolution

### 8.1 Existing Codebase Defect

In `FirestoreRestroomRepository.submitRestroom`:
```dart
// DEFECT: If id is empty, _collection.add() assigns an ID in Firestore, but data['id'] is empty!
// DEFECT: If id is provided, .set(data, SetOptions(merge: true)) can overwrite an existing facility!
```

### 8.2 Phase 2 Clean Contract

1. In `RestroomRepository`:
   ```dart
   abstract class RestroomRepository {
     // ... existing discovery methods ...

     /// Submits a new community restroom draft atomically.
     /// Returns the newly created public [Restroom] entity.
     Future<Restroom> submitRestroom(RestroomDraft draft);
   }
   ```
2. In `FirestoreRestroomRepository`:
   - Generate document reference beforehand: `final newDocRef = _collection.doc();`
   - Derive `final restroomId = newDocRef.id;`
   - Calculate geohash: `final geohash = _geohashService.encode(draft.latitude, draft.longitude, precision: 9);`
   - Instantiate batch: `final batch = _firestore.batch();`
   - Add public doc: `batch.set(newDocRef, publicData);` (WITHOUT merge options)
   - Add private doc: `batch.set(_firestore.collection('contributions').doc('restroom_$restroomId'), contributionData);`
   - Await `batch.commit();`
   - Return clean `Restroom` instance.
3. In `InMemoryRestroomRepository`:
   - Implement the identical `submitRestroom(RestroomDraft draft)` contract, generating a mock ID, recording to in-memory store with `RestroomStatus.unverified`, and maintaining an in-memory `_contributions` table for unit/widget test fidelity.

---

## 9. Bounded Duplicate Detection Contract

### 9.1 Purpose & Guardrails

The goal of duplicate detection is to help contributors discover that a restroom is already listed before submitting a second entry.
- **Zero Paid APIs:** Never invoke Google Places or Geocoding APIs.
- **Strictly Bounded Reads:** Reuse Phase 1 geohash candidate retrieval.
- **Advisory Only:** Never block submission. If a user intends to add a separate restroom on a different floor or wing in the same building, they can acknowledge the warning and proceed.

### 9.2 Spatial Search Bounds

When the user clicks "Submit Restroom" on the form:
1. Query candidate restrooms within a 500m radius around `(draft.latitude, draft.longitude)`:
   - Precision: 6 (~1.2 km × 0.6 km).
   - Max geohash ranges: 9 (`take(9)`).
   - Document limit: `.limit(20)`.
   - Max raw Firestore reads: 20 documents.
2. Filter candidates in memory using exact Haversine distance ($D \le 500\text{m}$).

### 9.3 Heuristic Scoring Engine

Each nearby candidate restroom $C$ is evaluated against draft $D$:

1. **Distance Metric ($S_{\text{dist}}$):**
   - If $D < 30\text{m}$: score = 1.0
   - If $D < 100\text{m}$: score = 0.7
   - If $D < 300\text{m}$: score = 0.3
   - Else: score = 0.0
2. **Name Similarity Metric ($S_{\text{name}}$):**
   - Normalize strings: lowercase, remove punctuation (`[^\w\s]`), collapse whitespace.
   - Calculate token overlap / Dice coefficient between normalized names.
3. **Context / Floor Overlap ($S_{\text{context}}$):**
   - If both have `buildingName` and they match: bonus +0.3.
   - If both have `floor` and they match: bonus +0.2.
   - If both have `floor` and they **conflict** (e.g. "Floor 1" vs "Floor 4"): penalty -0.4 (indicates distinct facilities).

**Classification Thresholds:**
- **High Potential Duplicate:** (Overall score $\ge 0.75$) OR (Distance $< 50\text{m}$ AND name similarity $> 0.7$).
- **Moderate Potential Duplicate:** (Overall score $\ge 0.50$) OR (Distance $< 100\text{m}$ AND same building).
- **Distinct Facility:** Overall score $< 0.50$.

### 9.4 Advisory Warning UX

If one or more candidates score $\ge 0.50$:
1. Suspend submission and display a non-blocking modal bottom sheet:
   - **Header:** "Similar restrooms found nearby"
   - **Explanation:** "We found an existing restroom near this location. Is this the same facility?"
   - **Candidate List:** Up to 3 top candidates showing name, distance, floor, and access type.
   - **Actions:**
     - `View Existing Restroom`: Dismisses sheet, closes form, centers map on the candidate, and opens its preview sheet.
     - `No, It's a Different Restroom`: Confirms user intent and immediately proceeds with the atomic batch submission.

---

## 10. Concurrency, In-Flight Protection & Idempotency

1. **Button Debounce:** Tapping "Submit" immediately sets `isSubmitting = true`, disabling all inputs and rendering a circular progress indicator on the primary button.
2. **Fresh Client ID:** Every submit attempt generates a fresh UUID/Firestore document ID. Re-submitting after an error generates a clean document ID without collisions.
3. **Firestore Collision Guard:** Rules verify document does not already exist via `allow create: if !exists(...)`.
4. **Form State Preservation:** If submission fails due to network outage or server error, form state is strictly preserved so the user never loses typed descriptions or selections.

---

## 11. Auth & App Check Integration

1. **Transparent Anonymous Sign-In:**
   - Entering the Add Restroom flow checks `FirebaseAuth.instance.currentUser`.
   - If null, triggers `FirebaseAuth.instance.signInAnonymously()`.
   - If sign-in succeeds, user proceeds uninterrupted.
   - If offline or blocked, displays an inline retry banner: "Unable to connect anonymously. Please check your internet connection."
2. **Firebase App Check:**
   - Operates transparently on all batch write requests.
   - If an App Check verification token is missing or invalid in production, Firestore rules reject the write (`permission-denied`).
   - The UI surfaces a helpful error: "App verification failed. Please ensure you are running the official LooRadar app."

---

## 12. Success & Feedback Lifecycle

Upon successful completion of the atomic batch write:

1. **Success Notification:** Display an accessible toast or floating snackbar: `"Restroom added! Thank you for contributing."`
2. **Navigation:** Pop the `AddRestroomFormScreen` and return to `MapDiscoveryScreen`.
3. **Map Discovery Synchronization:**
   - Smoothly animate the map camera to `(draft.latitude, draft.longitude)` at `zoom: 16.5`.
   - Inject the newly created `Restroom` entity directly into the `MapDiscoveryNotifier` result set as an optimistic entry.
   - Set the newly added restroom as the selected item, opening its `RestroomPreviewSheet`.
   - The preview sheet prominently displays the `"Unverified"` status badge, reinforcing that community confirmation is required.

---

## 13. Read and Cost Upper Bounds for Phase 2

| Operation | Query / Action | Maximum Reads | Cost Guardrail |
| :--- | :--- | :--- | :--- |
| **Location Pinpoint** | Interactive Map Drag | 0 Firestore reads | Relies entirely on client-side map rendering; no reverse geocoding API calls. |
| **Duplicate Detection** | Nearby candidate search | Max 20 Firestore reads | Precision 6, max 9 geohash ranges, `.limit(20)` document cap. |
| **Restroom Submission** | Atomic Batch Write | 2 Firestore writes | 1 public write (`restrooms/`), 1 private write (`contributions/`). |
| **Anonymous Auth** | Background sign-in | 0 Firestore reads | Native Firebase Auth token exchange. |

---

## 14. Phase 2 Implementation Milestones

### P2.0 — Specification & Task Contract (ACTIVE)
- Author this specification document (`docs/09-phase-2-add-restroom.md`).
- Update `docs/STATUS.md` and `docs/README.md`.
- Open draft PR `Phase 2 — Add Restroom` on `phase-2/add-restroom`.
- Pass independent exact-head audit.

### P2.1 — Contribution Domain Model (`RestroomDraft`), Repository Batch Write Contract, Firestore Rules & Emulator Tests
- Implement `RestroomDraft`, `TriStateAmenity`, and validation in `lib/domain/models/restroom_draft.dart`.
- Update `RestroomRepository` interface with `submitRestroom(RestroomDraft draft)`.
- Update `FirestoreRestroomRepository` with atomic `WriteBatch` (`restrooms/` and `contributions/restroom_{id}`).
- Update `InMemoryRestroomRepository` with draft support.
- Update `firestore.rules` for status enforcement (`unverified`), ID invariance, aggregate protection, and atomic contribution validation.
- Author comprehensive Firestore emulator tests in `rules_tests/p2_add_restroom_rules_test.js`.

### P2.2 — Interactive Location Pinpoint & Map Pin Adjustment UX
- Implement `AddRestroomLocationScreen` with interactive center crosshair / draggable pin on Google Maps.
- Enforce zoom floor (`zoom >= 15.0`) with visual helper hint.
- Display live formatted coordinate readouts.
- Unit and widget tests for location selection interactions.

### P2.3 — Contribution Form UI, Data-Truth Validation & State Management
- Implement `AddRestroomFormScreen` with organized card sections (Basic Info, Indoor Directions, Accessibility, Amenities, Fee/Key notes).
- Implement tri-state amenity selector widgets.
- Implement `AddRestroomNotifier` form state management and input validation.
- Unit tests for form validation and widget tests for form rendering and error states.

### P2.4 — Bounded Duplicate Detection Engine & Advisory Warning UX
- Implement `DuplicateDetectionService` with 500m geohash candidate retrieval and heuristic scoring.
- Implement `DuplicateWarningSheet` advisory UI.
- Unit tests for similarity heuristics and edge cases; widget tests for modal display and button actions.

### P2.5 — End-to-End Anonymous Auth Submission, Map Discovery Sync & Feedback
- Connect anonymous authentication lifecycle.
- Wire submit action through repository batch write.
- Sync successful submissions with `MapDiscoveryNotifier` (camera move, optimistic cache injection, preview selection).
- End-to-end integration and widget tests.

### P2.6 — Hardening, Accessibility, Regression Suite & Validation
- Audit touch targets (>= 48×48), semantic labels, and contrast.
- Run complete test suite (`flutter test`, Firestore emulator rules tests).
- Validate platform compilation (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`).
- Update `docs/STATUS.md` and prepare Phase 2 for audit.

---

## 15. Testing Contract

### 15.1 Unit Tests
- `RestroomDraft` field validations (name lengths, coordinate ranges, directions note limits).
- Tri-state amenity transformations to nullable booleans.
- Geohash calculation and precision verification for new drafts.
- Duplicate detection scoring algorithm (exact name matches, partial matches, conflicting floors, distance weighting).

### 15.2 Firestore Security Rules Emulator Tests
- Unauthenticated user cannot create restroom -> REJECT.
- Authenticated user can create valid restroom with atomic contribution -> ALLOW.
- Client cannot forge `status: 'active'` on creation -> REJECT.
- Client cannot forge positive initial ratings or aggregates -> REJECT.
- Client cannot write contributor UID inside `/restrooms/{id}` -> REJECT.
- Client cannot create `/restrooms/{id}` without creating paired `/contributions/restroom_{id}` -> REJECT.
- Client cannot create `/contributions/{id}` with mismatched `userUid` -> REJECT.
- Unauthenticated and other users cannot read `/contributions/{id}` -> REJECT.

### 15.3 Widget & State Tests
- `AddRestroomLocationScreen`: Zoom threshold disables/enables "Confirm Pin" button.
- `AddRestroomFormScreen`: Form validation errors render appropriately.
- Tri-state amenity toggles switch between Yes, No, and Unspecified states.
- Duplicate advisory sheet displays candidate facilities and handles "View Existing" vs "Continue" actions.
- Submission button enters loading state and disables inputs while in flight.

---

## 16. Non-Goals (Explicitly Excluded from Phase 2)

- **Photo Uploads:** Deferred to Phase 5.
- **Rating / Review Submission:** Phase 3.
- **Verification / Reporting Submission:** Phase 3.
- **Google Places Autocomplete / Geocoding API:** Prohibited due to cost and architecture invariants.
- **Routing / Turn-by-Turn Navigation:** Prohibited; external navigation apps handle routing.
- **Social Login / Traditional User Accounts:** Prohibited in V1.
- **Moderation Dashboard:** Phase 4.

---

## 17. Definition of Done for Phase 2

Phase 2 is complete when:

1. Users can initiate contribution from the map shell, pinpoint an exact entrance on the map with zoom enforcement, and input complete facility and indoor direction details.
2. Form fields adhere to data-truth invariants: unconfirmed amenities are never defaulted to positive verified claims.
3. Newly contributed restrooms are saved with `status: 'unverified'` and zero initial aggregates.
4. Submissions are atomic across `/restrooms/{id}` and `/contributions/restroom_{id}` via Firestore `WriteBatch`.
5. Contributor UID is never stored in public documents; private ownership is secured in `/contributions/`.
6. Firestore Security Rules enforce authentication, schema, status, zero aggregates, and atomic contribution pairing, with 100% passing emulator tests.
7. Bounded duplicate detection alerts users of potential nearby matches without blocking submission.
8. Submitting a restroom immediately reflects on the discovery map with camera recentering and preview selection.
9. All format, analysis, Flutter tests, and emulator tests pass.
10. `docs/STATUS.md` is updated with accurate evidence.
