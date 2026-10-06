# LooRadar Data Model

## Design goals

- Support global restroom discovery.
- Support multiple restrooms at the same building coordinates.
- Keep reads inexpensive.
- Avoid storing unnecessary personal information.
- Support ratings, verification, reports, and future moderation.
- Keep contributor identity/ownership metadata out of publicly readable documents.
- Keep the schema portable if spatial workloads later move to PostGIS.

## Public/private data boundary

Firestore authorization applies to documents, not individual returned fields. Therefore a publicly readable document must not contain contributor UIDs or other private moderation/ownership metadata.

LooRadar uses an explicit separation:

- **public collections/documents** contain only data safe for any app user to read;
- **private contribution/ownership documents** contain anonymous Firebase UID, moderation state, abuse-control metadata, and other internal fields;
- trusted server-side code may join or aggregate these domains when required, but public clients must never receive private ownership fields.

Do not place `createdByUid` or `userUid` in a publicly readable restroom, rating, verification, report, or photo document.

## Collections

### `restrooms` — public

Suggested fields:

```text
id
name
latitude
longitude
geohash
countryCode
region
city
buildingName
buildingSection
floor
unitOrArea
landmark
directionsNote
accessType
accessInstructions
feeAmount
feeCurrency
male
female
allGender
pwdAccessible
babyChanging
hasBidet
hasToiletPaper
hasSoap
hasHandDryer
averageRating
ratingCount
verificationCount
negativeVerificationCount
lastVerifiedAt
status
createdAt
updatedAt
```

### Nullable Amenity & Stall Semantics

In Phase 2 and beyond, contribution-derived amenity and stall properties use **nullable booleans** (`bool?`):
- `true` = explicitly confirmed Yes;
- `false` = explicitly confirmed No;
- `null` (or omitted) = unknown / unspecified.

`false` must never mean both "No" and "Unknown". Missing or omitted fields in historical/existing documents decode as `null`. Historical documents are not silently rewritten in Phase 2. Discovery filters (e.g., `toiletPaperOnly`) match only explicit `true`.

Ownership for a restroom submission belongs in private contribution metadata keyed to the public restroom ID.

### `ratings` — public/sanitized rating content

A public rating record, if individual ratings/comments are exposed, contains only display-safe fields:

```text
id
restroomId
overall
cleanliness
supplies
accessibility
privacy
comment
createdAt
updatedAt
```

Do not include `userUid` in a publicly readable rating document.

### `verifications` — public only if individual events are needed

Prefer exposing verification aggregates/freshness on the restroom record. If individual verification events are made public, expose only sanitized fields:

```text
id
restroomId
result        // confirmed | not_found | temporarily_unavailable
createdAt
```

Contributor identity remains private.

### `reports` — private

Reports are moderation inputs and should not be publicly readable.

Suggested fields:

```text
id
restroomId
reason
notes
createdAt
status
resolvedAt
```

Contributor ownership/UID is stored in private contribution metadata or a private report ownership field because the report document itself is not publicly readable.

Suggested report reasons:

- duplicate
- permanently_closed
- wrong_location
- inaccurate_details
- inappropriate_content
- other

### `contributions` — private contribution tracking & audit log

Conceptual fields:

```text
id                 // string, deterministic 'restroom_' + resourceId for restroom contributions
contributionType   // restroom | rating | verification | report | photo
resourceId         // matches target document ID (e.g. restroomId)
restroomId         // where applicable, matches resourceId
userUid            // matches request.auth.uid
createdAt          // server timestamp
updatedAt          // server timestamp
moderationState    // 'pending' on client creation
```

This collection is strictly private (`resource.data.userUid == request.auth.uid`). Public reads and listings are denied.

For restroom contributions, the document ID is deterministic: `contributions/restroom_{restroomId}`. Security rules enforce that `restrooms/{restroomId}` and `contributions/restroom_{restroomId}` must be created simultaneously in the same atomic batch (`WriteBatch`), verifying that neither document existed prior to the write and both exist after the write with cross-referenced resource IDs.

## One rating per user per restroom

The one-active-rating rule must be enforceable, not merely a UI convention.

Use a deterministic private ownership key derived from the authenticated UID and restroom ID, or an equivalent trusted server-side write path. A conceptual key is:

```text
ratingOwnership/{restroomId}_{auth.uid}
```

The client must never be allowed to claim another user's UID. Security rules or trusted server code must derive/validate ownership against `request.auth.uid`.

Updating a rating replaces the user's existing active rating rather than creating a second ownership record. If public rating content uses a separate sanitized document, trusted logic must keep that document and its private ownership record consistent.

Do not encode the raw UID into a publicly readable document ID.

## Public versus private fields

Public facility data may include:

- restroom name
- coordinates
- building/floor directions
- amenities
- aggregate ratings
- sanitized review content, if enabled
- verification freshness

Private/internal data includes:

- contributor UID
- submission ownership
- moderation notes/state not intended for users
- abuse scores/signals
- security logs

## Location representation

Coordinates represent the public facility, not the contributor's location history.

Store on the public restroom record:

```text
latitude
longitude
geohash
```

For indoor facilities, additional text fields provide the useful final-leg directions.

## Rating aggregates

Do not compute aggregate ratings by loading every rating document whenever the marker/card is shown.

Store precomputed aggregate fields on the restroom document:

```text
averageRating
ratingCount
```

If category averages are useful later, add:

```text
averageCleanliness
averageSupplies
averageAccessibility
averagePrivacy
```

Clients must not directly write trusted aggregate values. Updates should be transaction-safe and/or performed in trusted server-side code once rating mutations are implemented.

## Duplicate detection

When submitting a new restroom:

1. Search for nearby restroom records within a small radius.
2. Compare building name, floor, and landmark metadata.
3. Warn the contributor if a likely duplicate exists.
4. Allow separate records for legitimate multiple restrooms in one building.

Do not automatically merge merely because coordinates are similar.

## Status values

Suggested restroom status values:

```text
active
unverified
flagged
temporarily_unavailable
removed
```

## Timestamps

Use server timestamps for mutation times where possible.

Store timestamps in UTC. Display dates/times in the user's locale.

## Future photo collection

When photos are introduced, use separate public metadata and private ownership/moderation data rather than embedding large arrays or contributor identity in restroom records.

Public/sanitized photo metadata may contain:

```text
id
restroomId
storagePath
createdAt
```

Private metadata may associate the photo with `userUid` and moderation/abuse-control fields. Photos should be compressed client-side and reviewed or automatically screened before becoming public.