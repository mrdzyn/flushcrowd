# FlushCrowd

FlushCrowd is a global, community-powered restroom finder focused on helping people quickly locate nearby toilets/comfort rooms, see practical details, contribute new locations, rate facilities, and verify whether listings are still usable.

## Project goals

- Global coverage from day one
- Map-first discovery of nearby restrooms
- No traditional account required for normal use
- Privacy-conscious design with minimal personal data
- Community-contributed locations, ratings, amenities, and verification
- Low operating cost using Google Maps + Firebase/Google Cloud free allowances where practical
- Simple path to scale without premature infrastructure complexity

## Initial stack

- Flutter (iOS + Android)
- Google Maps SDK for map visualization
- Firebase Anonymous Authentication
- Cloud Firestore
- Firebase App Check
- Firebase Storage for photos later
- Optional Cloud Run / Cloud Functions only where server-side enforcement is required

## Brand & Visual Reference

- Icon mark: [`docs/assets/brand/flushcrowd-icon.png`](docs/assets/brand/flushcrowd-icon.png)
- Horizontal lockup: [`docs/assets/brand/flushcrowd-horizontal.png`](docs/assets/brand/flushcrowd-horizontal.png)
- Mobile UX reference: [`docs/assets/flushcrowd-mobile-ux-reference.png`](docs/assets/flushcrowd-mobile-ux-reference.png)

## Documentation

See the [`docs/`](docs/) folder for architecture, product requirements, data model, privacy/security guidance, and phased delivery planning.
