# LooRadar Phase 1 — Map Discovery

## Goal

Implement production-quality restroom discovery on the map using bounded, cost-conscious Firestore spatial queries while preserving the Phase 0 privacy, security, architecture, and UI/UX contracts.

Phase 1 turns the Phase 0 map shell and repository abstractions into a real discovery experience. It does **not** add restroom creation, ratings submission, verification/reporting flows, photos, routing, Places search, or other later-phase features.

## Phase 1 outcomes

By the end of Phase 1, a user should be able to:

- open LooRadar and see nearby restroom markers when location permission is available;
- manually pan/zoom the map and request/receive restroom results for the visible area;
- see accurate nearby results even when facilities lie across geohash cell boundaries;
- tap a marker and inspect a restroom preview with distance, rating, indoor-location context, access type, and key amenities;
- open a nearby-results list from the map;
- filter results using the Phase 1 filter set;
- continue manual map exploration when location permission is denied;
- experience loading, empty, error, offline/degraded, and stale-result states without the map becoming unusable.

## Locked Phase 1 principles

- Keep the product map-first and mobile-first.
- Preserve anonymous/no-account-friction discovery.
- Use Firestore + geohash candidate retrieval for MVP spatial discovery.
- Perform exact Haversine filtering after geohash candidate retrieval.
- Never query on every camera frame.
- Never issue country-scale or global facility queries.
- Keep location history unpersisted.
- Do not add background location.
- Keep Firestore and GIS behavior behind repository/service boundaries.
- Keep infrastructure costs bounded and observable.
- Preserve the canonical UI direction in `docs/assets/looradar-mobile-ux-reference.png` and `docs/06-ui-ux-reference.md`.

## Scope

### P1.1 — Production GIS and Firestore discovery engine

Implement the production spatial-query behavior behind the existing repository interfaces.

Required behavior:

- geohash precision selection based on bounded query radius/viewport scale;
- center geohash plus neighboring cells required to avoid boundary misses;
- candidate prefix/range generation with deterministic deduplication;
- Firestore queries limited to bounded candidate ranges;
- exact Haversine post-filtering for radius searches;
- exact geographic-bound filtering for viewport searches;
- deduplicate documents returned by overlapping ranges;
- filter out statuses that must not appear in public discovery;
- deterministic distance sorting for nearby results;
- explicit maximum radius/viewport-query bounds;
- explicit maximum document reads/results per discovery operation;
- cancellation/stale-result protection when newer map queries supersede older ones;
- repository-level error mapping rather than exposing raw Firebase errors to presentation code.

The implementation must be testable without production Firebase credentials. Use emulator/fakes/test doubles where appropriate.

### Geohash correctness requirements

The Phase 0 single-center-prefix helper is insufficient for production nearby discovery.

Phase 1 must:

1. derive the center cell at the selected precision;
2. derive all neighboring cells required to cover the search area, including edge/corner cases;
3. handle longitude wraparound near the antimeridian;
4. handle valid behavior near the poles without generating invalid coordinates;
5. remove duplicate candidate prefixes/ranges;
6. post-filter candidates with exact Haversine distance or viewport bounds.

Do not rely on a single geohash prefix for production radius queries.

Tests must include points near cell boundaries where the nearest restroom falls in an adjacent cell.

### Radius limits

Initial product defaults:

- default nearby radius: 1.5 km;
- allow application-level expansion only through documented bounded values;
- hard maximum nearby radius for Phase 1: 10 km unless an implementation review demonstrates a lower-cost alternative;
- reject or clamp invalid/unbounded radius inputs before querying Firestore.

These are application safety limits, not user-visible promises. Adjustments require a documented cost/correctness rationale.

### Viewport-query limits

Viewport discovery must be bounded.

Required behavior:

- do not query at world/country-scale zoom levels;
- introduce a minimum zoom threshold for facility-level viewport querying;
- when below that threshold, retain existing results or show an intentional "zoom in to see restrooms" state rather than querying enormous areas;
- bound the number of geohash ranges and per-range result limits;
- cap total candidate documents processed per viewport operation;
- surface partial/degraded state if a safety cap is reached rather than silently implying completeness.

The implementation agent must document the chosen initial zoom threshold, range caps, and result caps in code/config and tests.

## P1.2 — Map query orchestration

### Camera lifecycle

Map camera movement must not directly trigger Firestore reads on every update.

Required flow:

```text
camera starts moving
  ↓
mark viewport dirty
  ↓
camera becomes idle
  ↓
debounce 300–500 ms
  ↓
validate zoom/viewport bounds
  ↓
query repository
  ↓
ignore stale superseded response
  ↓
render markers/results
```

Use a single clearly owned debounce/cancellation mechanism.

### Query reuse

Avoid redundant queries when the camera change is insignificant.

At minimum:

- do not re-query an effectively identical viewport;
- avoid immediate duplicate queries caused by programmatic recentering plus map-idle callbacks;
- keep the last successful viewport/query descriptor in application state;
- allow explicit refresh/retry when appropriate.

Do not persist user movement trails or historical viewport data beyond ephemeral runtime state needed for query orchestration.

## P1.3 — Markers and clustering

Implement restroom markers driven by discovered data.

Required:

- stable marker identity based on restroom ID;
- selected/unselected visual state;
- marker tap selects the restroom and exposes its preview;
- marker lifecycle must not leak stale results after a newer query;
- clustering for dense result sets;
- cluster tap behavior should zoom/expand rather than select an arbitrary restroom;
- current-location marker remains platform-controlled or clearly differentiated from facility markers.

Choose a clustering approach compatible with the existing Flutter/Google Maps stack and document any added package/dependency.

Do not introduce a paid mapping service for clustering.

## P1.4 — Restroom preview and nearby list

The marker-preview interaction should follow the canonical mobile UX direction.

Preview card/bottom sheet should prioritize:

- restroom name;
- distance when user location is available;
- building/floor/wing/landmark context;
- rating and rating count;
- verification freshness when available;
- access type (free/paid/customer-only/key-required as supported by the domain model);
- high-value amenity indicators such as PWD accessibility, baby changing, bidet, toilet paper, and soap.

The preview must not expose contributor identity or private moderation metadata.

Nearby list:

- uses the same current discovery result set rather than issuing a second fan-out query solely to populate the list;
- sorts sensibly for nearby mode, normally by exact distance;
- preserves map selection when practical;
- provides empty/error states.

Full restroom-detail/navigation flows may remain lightweight if they belong to a later milestone, but the Phase 1 preview must be useful enough to choose among nearby facilities.

## P1.5 — Filters

Initial Phase 1 filters:

- PWD accessible;
- baby changing;
- free;
- paid;
- customer-only;
- male;
- female;
- all-gender;
- bidet;
- recently verified.

Implementation guidance:

- prefer client-side filtering of the already-bounded discovery result set when that avoids unnecessary composite indexes and extra reads;
- only move filters server-side when there is a clear correctness/scale reason;
- filters must not cause a new Firestore request for every tap unless explicitly justified;
- reset/clear behavior must be deterministic;
- selected filters must be visible and accessible.

## P1.6 — State and failure handling

Map discovery application state should distinguish at least:

- initial;
- loading first results;
- refreshing existing results;
- loaded;
- empty;
- zoom-too-low / query-suppressed;
- offline/degraded;
- error.

Do not blank an already useful map just because a refresh fails. Prefer retaining the last successful result set with a non-blocking degraded/error indication.

When Firebase is not configured in a development environment, the existing in-memory/demo path must remain usable.

## Security and privacy requirements

Phase 1 must preserve all Phase 0 controls.

Specifically:

- discovery reads only public sanitized restroom documents;
- no contributor UID is exposed;
- no location history is persisted;
- no background location is introduced;
- do not write user coordinates to Firestore for discovery;
- do not add analytics containing precise location;
- maintain App Check compatibility;
- do not weaken Firestore rules to simplify spatial reads.

Any required Firestore index changes must be committed to `firestore.indexes.json` and validated/documented.

## Cost controls

Every production discovery path must be designed to bound Firestore reads.

Required controls:

- debounce map-idle queries;
- zoom/radius bounds;
- per-range query limits;
- total candidate/result caps;
- no duplicate identical queries;
- reuse current result set for preview/list/filtering;
- avoid rating/review fan-out reads by relying on restroom aggregate fields;
- use Firestore offline persistence/default cache behavior appropriately without claiming it as a correctness mechanism;
- log/debug-count query ranges and candidate/result counts in development where useful, without logging precise user location to production telemetry.

Before Phase 1 completion, document the expected worst-case number of Firestore range queries and bounded candidate reads for a single nearby and viewport operation under the chosen algorithm.

## Accessibility and UX requirements

- maintain usable touch targets;
- provide semantic labels for map overlay controls where practical;
- selected filter state must not rely on color alone;
- bottom sheets/cards must support text scaling reasonably;
- loading/error banners must not permanently obstruct map interaction;
- location-denied users must still be able to pan/zoom manually;
- "zoom in" suppression state must explain why facilities are not being queried.

## Testing requirements

### Unit tests

At minimum cover:

- geohash neighbor generation;
- geohash boundary cases;
- antimeridian behavior;
- radius-to-precision selection;
- radius clamping/rejection;
- Haversine exact filtering;
- viewport bound filtering;
- candidate deduplication;
- result deduplication;
- status filtering;
- deterministic nearby distance ordering;
- filter logic;
- stale/superseded query rejection;
- equivalent-viewport/query reuse logic;
- zoom-threshold suppression.

### Repository / Firestore tests

Use emulator/fake infrastructure to prove representative production query behavior without production credentials.

At minimum:

- adjacent-cell restroom is discovered;
- out-of-radius candidate is removed by exact filtering;
- overlapping geohash ranges do not duplicate a restroom;
- hidden/removed facility statuses are excluded;
- query/result caps behave as designed;
- Firestore codec behavior remains correct.

### Widget/state tests

At minimum:

- location denied still permits manual map experience;
- first-load loading state;
- loaded markers/preview state;
- empty result state;
- refresh failure retains prior successful results;
- zoom-too-low state;
- filter apply/reset behavior;
- marker selection updates preview.

### Existing security regression

All existing Firestore Rules emulator tests must remain green.

## Manual QA requirements

Before Phase 1 merge, manually validate representative Android and iOS targets where tooling/credentials are available.

QA scenarios:

1. grant location and recenter;
2. deny location and manually explore;
3. pan repeatedly and confirm queries occur only after idle/debounce;
4. zoom below threshold and confirm Firestore query suppression;
5. cross a known geohash boundary and confirm adjacent results appear;
6. select marker and inspect preview;
7. open nearby list;
8. apply/reset filters;
9. simulate no-results area;
10. simulate network/query failure and confirm prior map results remain usable;
11. verify no background-location permission is requested;
12. verify no UID/private moderation data appears in UI/log output.

If Google Maps/Firebase credentials are unavailable, mark live-device scenarios `NOT RUN` and identify the exact owner action required.

## Non-goals

Do not implement in Phase 1:

- add-restroom submission workflow;
- duplicate-submission detection UI;
- rating/review submission;
- verification/report submission;
- photo upload;
- built-in routing;
- Google Places search/autocomplete;
- Street View;
- Directions/Routes APIs;
- social/community profiles;
- background location;
- analytics containing precise location;
- PostGIS migration;
- AI functionality;
- donations/monetization work.

## Implementation milestones

### P1.0 — Specification and task contract

This document. Review/audit before broad implementation if material GIS decisions are changed.

### P1.1 — GIS + Firestore discovery engine

Production neighbor expansion, bounded nearby/viewport queries, exact filtering, dedupe, safety caps, repository tests.

### P1.2 — Query orchestration + map markers/clustering

Camera-idle debounce, stale-query handling, markers, clustering, refresh/error states.

### P1.3 — Preview/list/filters

Canonical card/bottom-sheet experience, nearby list, Phase 1 filters, accessibility states.

### P1.4 — Hardening and manual QA

Cost/read review, Android/iOS live validation where possible, regression suite, documentation/status handoff, independent exact-head audit.

## Definition of done

Phase 1 is complete when:

1. Production nearby discovery covers relevant neighboring geohash cells and passes boundary tests.
2. Nearby results are exact-distance filtered, deduplicated, status-filtered, and deterministically sorted.
3. Production viewport discovery is bounded by zoom/range/result caps and does not query at global/country scale.
4. Map camera queries are idle-triggered and debounced rather than fired continuously.
5. Stale/superseded responses cannot overwrite newer discovery state.
6. Dense markers are clustered and marker selection drives the canonical preview interaction.
7. Nearby list and Phase 1 filters work from the bounded result set without unnecessary fan-out reads.
8. Location-denied/manual-map discovery remains usable.
9. Loading, empty, zoom-suppressed, refresh-error, and offline/degraded states are handled without unnecessarily blanking useful existing results.
10. Firestore read/query safety caps are explicit, tested, and documented.
11. Existing Phase 0 privacy/security rules and tests remain green.
12. No new background location, Places/Routes/Street View, precise-location analytics, or unrelated paid API dependency is introduced.
13. `dart format`, `flutter analyze`, `flutter test`, Firestore Rules tests, and targeted Phase 1 repository tests pass.
14. Android/iOS manual QA is completed where credentials/tooling permit, with unavailable scenarios honestly recorded as `NOT RUN`.
15. `docs/STATUS.md` accurately records the implemented Phase 1 state, validation evidence, remaining owner actions, and exact next phase.

## Next phase

After Phase 1 passes independent audit and is merged, proceed to **Phase 2 — Add Restroom**.