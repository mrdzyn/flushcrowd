# LooRadar Documentation

This folder is the source of truth for the LooRadar product and technical implementation.

For AI-assisted development, agents must read [`../AGENTS.md`](../AGENTS.md) first and then [`STATUS.md`](STATUS.md) for the current project state, active phase, blockers, and next action.

## Documents

1. [`STATUS.md`](STATUS.md) — current phase, completed work, active task, blockers, validation state, and cross-agent handoff.
2. [`00-product-vision.md`](00-product-vision.md) — product problem, value proposition, global positioning, and product principles.
3. [`01-architecture.md`](01-architecture.md) — Flutter/Firebase/Google Maps architecture, GIS strategy, cost controls, and scaling path.
4. [`02-data-model.md`](02-data-model.md) — Firestore collections, restroom fields, ratings, verification, reports, and duplicate-handling guidance.
5. [`03-privacy-security.md`](03-privacy-security.md) — anonymous identity model, location privacy, App Check, security rules, data minimization, and secret handling.
6. [`04-mvp-scope.md`](04-mvp-scope.md) — MVP features, exclusions, primary screens, acceptance criteria, and initial success measures.
7. [`05-phase-0-plan.md`](05-phase-0-plan.md) — Phase 0 implementation requirements and definition of done.
8. [`06-ui-ux-reference.md`](06-ui-ux-reference.md) — UI/UX-first build rules, screen flows, design direction, validation gates, and the canonical mobile mockup.
9. [`07-environment-setup.md`](07-environment-setup.md) — environment variables, restricted API keys, App Check strategy, signing safeguards, and budget alert procedures.
10. [`08-phase-1-map-discovery.md`](08-phase-1-map-discovery.md) — active Phase 1 GIS/query contract, map orchestration, markers/clustering, preview/list/filter requirements, cost controls, testing, and definition of done.

## Canonical visual reference

![LooRadar mobile UX reference](assets/looradar-mobile-ux-reference.png)

`assets/looradar-mobile-ux-reference.png` is the canonical visual reference for user-facing implementation. The SVG remains a secondary lightweight reference only.

User-facing implementation should follow the PNG's hierarchy, interaction model, and overall visual direction unless an intentional design change is documented in the same pull request.

## Current architectural decisions

- Product name: **LooRadar**
- Global-first mobile application
- UI/UX-first delivery approach
- Flutter for iOS and Android
- Google Maps SDK for map visualization
- Firebase Anonymous Authentication rather than mandatory user registration
- Firestore + geohash strategy for MVP GIS queries
- Exact distance/bounds post-filtering after geohash candidate retrieval
- No stored user movement/location history
- No background location permission in V1
- External navigation handoff instead of implementing routing
- Photos deferred until after the core map/contribution workflow is proven
- Optional donation/support model rather than mandatory monetization in V1

## Development sequence

```text
Phase 0 — Foundation + UI shell/design system        [MERGED]
   ↓
Phase 1 — Map Discovery                              [ACTIVE]
   ↓
Phase 2 — Add Restroom
   ↓
Phase 3 — Ratings + Verification + Reporting
   ↓
Phase 4 — Moderation / Trust / Production Hardening
   ↓
Phase 5 — Photos, broader data integrations, growth features
```

Any implementation decision that materially changes these documents or the approved interaction model should update the documentation in the same pull request.
