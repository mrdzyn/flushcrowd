# LooRadar Privacy & Security Baseline

## Privacy objective

LooRadar should minimize collection of personal information while still supporting useful community contributions and abuse prevention.

## Identity model

V1 uses Firebase Anonymous Authentication.

The app should not require users to provide:

- name
- email address
- phone number
- password
- social profile

Anonymous Firebase UIDs are pseudonymous internal identifiers. They must not be displayed publicly or stored in publicly readable documents.

## Public/private identity separation

Firestore Security Rules authorize access at the document level; they are not a field-redaction mechanism. A document that is readable by the public must therefore contain only fields that are safe to disclose.

Required design:

- public restroom and sanitized contribution documents contain no contributor UID;
- ownership, moderation, and abuse-control metadata is stored in non-public documents/collections or handled in trusted server-side services;
- public document IDs must not embed raw Firebase UIDs;
- where ownership must be enforced by rules, validate against `request.auth.uid` and use deterministic private ownership records or a trusted server write path.

See `02-data-model.md` for the public/private collection model.

## Location privacy

User location is sensitive and should be handled conservatively.

### Allowed use

Device location may be used to:

- center the map
- find nearby restrooms
- prefill a new restroom location when the user intentionally contributes one

### Prohibited by default

Do not persist:

- continuous location history
- historical searches tied to a user UID
- movement trails
- background location history

The public restroom coordinates submitted by a contributor are facility data, not user-location history.

## Permissions

Request foreground location only when needed.

Do not request background location in V1.

Explain the purpose in plain language before or alongside the OS permission prompt.

## Firebase security controls

Use:

- Firebase Authentication
- Firebase App Check
- restrictive Firestore Security Rules
- server timestamps
- validation of field types and ranges
- least-privilege Storage Rules when photos are introduced

Never rely exclusively on client-side validation.

## App Check strategy

Phase 0 must distinguish development/testing from production enforcement.

- Development/emulators may use Firebase's supported debug provider/token workflow. Debug tokens are development credentials and must not be committed to the repository or exposed publicly.
- Android production should use the supported Play Integrity App Check provider unless platform requirements change.
- Apple production should prefer App Attest where supported, with DeviceCheck fallback where needed.
- Production enforcement should only be enabled after legitimate release builds are verified to obtain valid App Check tokens, to avoid locking out the app.
- Document provider configuration and rollout steps without committing provider secrets/tokens.

## Contribution controls

Required/recommended controls:

- authenticated anonymous UID required for writes
- one active rating per UID per restroom, enforced by security rules/private deterministic ownership or trusted server code
- never trust a client-supplied UID as proof of ownership
- rate limits for submissions/reports/verifications
- duplicate-location checks
- maximum text lengths
- reject invalid latitude/longitude values
- constrain enum fields to known values
- moderation state for potentially abusive content
- prevent clients from directly mutating trusted aggregate/reputation fields
- create-only public facilities in Phase 2 (`allow update, delete: if false;`); client facility updates and deletions strictly prohibited

### Production Abuse-Control Release Gate

A disabled submit button or client-side debounce is UX protection, not abuse protection.

**Phase 2 community contribution writes must not be enabled in production until enforceable per-UID rate limiting exists.**

- **Enforcement Architecture:** A private per-user write-control record `contributionRateLimits/{uid}` updated atomically via a trusted server boundary (Cloud Function or rule-backed counter).
- **Evaluated Policy:** Maximum 10 restroom submissions per UID per 24 hours; maximum burst 3 submissions per UID per 10 minutes.
- **Milestone Separation:** P2.1–P2.5 implements core models, atomic batch writes, and strict security rules. P2.6 verifies this production rate-limiting release gate before opening production contribution writes.

High-risk operations should move to trusted server-side code if Firestore Rules cannot enforce the business rule safely.

## Data minimization

Only collect information necessary for the restroom-finding service.

Avoid storing raw IP addresses, advertising identifiers, contacts, device fingerprints, or unrelated analytics unless a later requirement provides a clear justification and privacy review.

## Analytics

Analytics is not required for MVP functionality.

If analytics is introduced later:

- document it clearly
- minimize event parameters
- avoid precise-location analytics
- prefer aggregate product metrics
- review consent requirements by region

## Photos

Photos create additional privacy and moderation risks.

When introduced:

- discourage photographing people
- strip unnecessary metadata such as EXIF GPS where possible
- compress images before upload
- moderate before or shortly after publication
- support reporting/removal
- keep contributor ownership metadata private

## Public/private separation

Public UI and publicly readable documents must never expose:

- contributor UID
- private moderation metadata
- internal abuse scores
- security logs

## Secrets and client configuration

Do not commit service-account credentials, debug App Check tokens, signing credentials, or unrestricted API keys to GitHub.

Firebase mobile client configuration is not equivalent to a service-account secret, but associated services still require appropriate Firebase Security Rules, App Check, and API restrictions.

Google Maps client keys must be platform-restricted using Android package/SHA restrictions and iOS bundle restrictions. Backend credentials belong in managed secret/configuration systems.

## Privacy policy

A privacy policy is still required even without traditional accounts because the app processes location and uses third-party infrastructure.

The policy should describe at minimum:

- what data is processed
- use of location permission
- anonymous Firebase authentication
- community submissions
- Google/Firebase infrastructure
- retention and deletion approach
- user rights/contact process
- international data processing as applicable

## Default principle

When choosing between collecting data "because it may be useful later" and not collecting it, default to not collecting it.