# FlushCrowd MVP Scope

## MVP objective

Prove that users can quickly discover, evaluate, contribute, and verify restroom locations globally using a map-first experience.

## In scope

### Map discovery

- show user location
- show nearby restroom markers
- pan/zoom map
- cluster dense markers
- tap marker to open a compact restroom card
- open full restroom details
- switch to a nearby list sorted by distance

### Restroom details

Display:

- name
- distance
- building/floor/location notes
- access type
- accessibility
- baby changing
- gender availability
- bidet/tissue/soap/hand dryer indicators
- overall rating
- rating count
- last verified date/status

### Add restroom

- use current location or selected map point
- allow pin adjustment
- capture building/floor/landmark/directions
- capture amenities
- capture access type
- run duplicate warning before submission
- submit using anonymous Firebase identity

### Ratings

- overall rating
- cleanliness
- supplies
- accessibility
- privacy
- optional short comment
- one active rating per anonymous UID per restroom

### Verification

Users can indicate:

- confirmed / still here
- could not find
- temporarily unavailable

### Reporting

Users can report:

- duplicate
- wrong location
- inaccurate details
- permanently closed
- inappropriate content
- other

### Navigation

Open coordinates in an installed external navigation app rather than implementing routing in FlushCrowd.

### Privacy

- no traditional signup requirement
- anonymous Firebase identity for contribution controls
- no background location
- no stored user location history

### Support

Include an About/Support entry that can link to Buy Me a Coffee or another donation service.

## Out of scope for MVP

- built-in turn-by-turn navigation
- background location tracking
- social profiles
- follower/friend features
- messaging
- Places autocomplete dependency
- Street View
- advanced moderation dashboard
- photo uploads
- gamification
- contributor leaderboards
- municipal/B2B dashboards
- AI-generated recommendations
- PostGIS
- offline global dataset downloads

## Primary screens

1. Splash / initialization
2. Location permission explanation
3. Map/Home
4. Nearby list
5. Restroom detail
6. Add restroom
7. Rate restroom
8. Verify/report actions
9. Filters
10. Settings/About/Support

## Suggested map filters

Initial filters:

- accessible
- baby changing
- free access
- paid
- customer only
- male
- female
- all gender
- bidet
- recently verified

Do not overload the first release with dozens of filters.

## MVP acceptance criteria

The MVP is successful when a user can:

1. open the app without creating an account;
2. grant foreground location access;
3. see nearby restroom markers on a map;
4. tap a marker and understand whether the restroom is suitable;
5. open external navigation to the facility;
6. add a missing restroom;
7. rate an existing restroom;
8. verify or report an existing listing;
9. use the app without FlushCrowd persisting a history of their movements.

## Success metrics

Early product metrics should focus on utility rather than vanity metrics:

- successful nearby searches
- restroom detail views
- navigation handoffs
- new valid locations contributed
- percentage of listings verified recently
- ratings per active listing
- duplicate/report rate
- contribution rejection/abuse rate

Avoid collecting precise-location analytics to calculate these metrics.
