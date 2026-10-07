# FlushCrowd Technical Architecture

## Objective

Deliver a global, map-first restroom finder with minimal infrastructure cost, low operational overhead, strong privacy defaults, and a straightforward path to scale.

## Initial architecture

```text
Flutter mobile app
  |
  +-- Device location services
  |
  +-- Google Maps SDK
  |     +-- current-location visualization
  |     +-- restroom markers
  |     +-- marker clustering
  |     +-- map viewport / camera bounds
  |
  +-- Firebase Anonymous Authentication
  |
  +-- Firebase App Check
  |
  +-- Cloud Firestore
  |     +-- restroom locations
  |     +-- ratings
  |     +-- verifications
  |     +-- reports
  |
  +-- Firebase Storage (later)
  |     +-- moderated restroom photos
  |
  +-- Optional server-side services
        +-- Cloud Run or Cloud Functions
        +-- abuse controls
        +-- trusted aggregation
        +-- moderation workflows
```

## Why this stack

### Flutter

- one iOS/Android codebase
- strong Google Maps support
- suitable for map-heavy mobile experiences
- fast iteration and low development overhead

### Google Maps SDK

Used for visualization only in the initial release.

Initial use:

- interactive global map
- current position
- restroom markers
- marker clustering
- camera/viewport interaction

Avoid initially:

- Places API dependency
- route calculation
- Street View
- paid autocomplete workflows
- excessive geocoding

Navigation should hand off to Google Maps, Apple Maps, or another installed navigation app using coordinates.

### Firebase Anonymous Authentication

Users should not need to provide a name, email address, phone number, or password.

Anonymous auth provides a stable Firebase UID for:

- submission ownership
- one-rating-per-user controls
- rate limiting
- moderation history
- abuse prevention

Browsing should remain available with minimal friction.

### Firestore

Firestore stores public facility data and contribution records.

It is suitable for the MVP because:

- low operational overhead
- offline caching support
- global managed infrastructure
- direct Flutter integration
- generous free quotas for early adoption

## GIS strategy

Firestore is not a full spatial database. FlushCrowd therefore uses:

- latitude
- longitude
- geohash

for spatial indexing.

Nearby queries use geohash ranges to retrieve candidate restroom records, followed by exact distance filtering using a Haversine calculation.

### Query modes

#### Nearby mode

1. Obtain current device location.
2. Calculate geohash bounds for the selected radius.
3. Query candidate restroom records.
4. Calculate exact distance locally or in a trusted service.
5. Filter to requested radius.
6. Sort nearest first.

#### Map viewport mode

1. User pans or zooms the map.
2. Wait for camera movement to stop.
3. Debounce the query.
4. Convert visible bounds into geographic query ranges.
5. Fetch only candidate restrooms for the visible area.
6. Cluster markers client-side.

## Indoor-location model

GIS coordinates cannot precisely identify different restrooms within the same large building.

Therefore each facility may include:

- building name
- building section or wing
- floor
- unit/area
- nearest landmark
- directions note

Example:

```text
SM Megamall
Building A · 3F
Hallway beside Toy Kingdom, near the elevators
```

## Cost controls

The client must not issue a Firestore query on every map movement frame.

Required controls:

- debounce viewport queries
- cache recent query areas
- use Firestore offline persistence
- limit query radius at lower zoom levels
- cluster dense markers
- paginate reviews
- store rating aggregates on restroom documents
- use server-generated or transaction-safe aggregates where needed
- avoid storing unnecessary analytics data
- resize/compress photos before upload when photos are introduced

## Scaling path

The initial stack should not prevent later migration.

If advanced GIS becomes necessary, spatial querying can move to a dedicated backend such as PostgreSQL/PostGIS while the Flutter UI and Google Maps visualization remain unchanged.

Potential triggers for migration:

- very large dense datasets
- polygon/area searches
- spatial joins
- complex proximity ranking
- large-scale analytics
- administrative-boundary queries

Do not introduce PostGIS during MVP unless actual usage proves Firestore geo-querying inadequate.
