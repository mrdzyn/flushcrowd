# FlushCrowd — Agent Operating Guide

This file is the shared operating contract for AI coding agents working on FlushCrowd. Read it before making changes.

## 1. Source of truth

Before implementation, read in this order:

1. `AGENTS.md` — operating rules for agents.
2. `docs/STATUS.md` — current phase, completed work, active task, blockers, and next actions.
3. `docs/README.md` — documentation index and locked project decisions.
4. The phase/scope document relevant to the task.
5. `docs/06-ui-ux-reference.md` and `docs/assets/flushcrowd-mobile-ux-reference.png` for user-facing work.
6. Architecture, data, privacy, and security documents relevant to the change.

If code, a prompt, or an agent assumption conflicts with the repository documentation, stop and surface the conflict. Do not silently redefine product requirements.

## 2. Product invariants

Unless a later approved document explicitly changes them:

- Product name is **FlushCrowd**.
- FlushCrowd is global-first and mobile-first.
- Delivery is **UI/UX first**.
- Flutter targets iOS and Android.
- Google Maps SDK provides map visualization.
- Firebase Anonymous Authentication is the V1 identity model; traditional login is not required.
- Firestore + geohashes provide MVP spatial querying.
- User movement/location history is not persisted.
- V1 requests foreground location only; no background location permission.
- Navigation is handed off to installed mapping/navigation apps rather than implementing routing.
- Privacy, accessibility, low infrastructure cost, and abuse resistance are first-class requirements.
- Photos are post-MVP unless scope is explicitly changed.

## 3. Canonical UI/UX reference

For user-facing implementation, the canonical visual reference is:

`docs/assets/flushcrowd-mobile-ux-reference.png`

The canonical brand assets are:

- `docs/assets/brand/flushcrowd-icon.png` (app icon / standalone mark)
- `docs/assets/brand/flushcrowd-horizontal.png` (horizontal logo lockup)

Do not modify or redraw these approved brand files.

Use `docs/06-ui-ux-reference.md` for interaction rules, hierarchy, accessibility expectations, and allowed interpretation of the mockup.

The mockup is directional rather than a pixel-perfect specification, but accidental UX drift is a defect. Intentional changes must be documented in the same PR.

## 4. Agent workflow

Every implementation agent should:

1. Read `docs/STATUS.md` and relevant docs before editing.
2. Confirm the requested task is within the active phase/scope.
3. Inspect the existing implementation before proposing architecture changes.
4. Make the smallest coherent change that satisfies the task.
5. Preserve established boundaries and avoid unrelated refactors.
6. Add or update tests for changed behavior where practical.
7. Run the repository's available format, static-analysis, and test commands.
8. Update documentation when behavior, architecture, security, privacy, or UX decisions change.
9. Update `docs/STATUS.md` before handing work off.
10. Report exactly what changed, what was validated, remaining risks/blockers, and the commit/PR reference.

Do not claim a command, build, test, simulator run, device test, Firebase deployment, or external configuration succeeded unless it was actually executed and observed.

## 5. Branch and PR discipline

- Do not implement directly on `main` unless explicitly instructed.
- Use one focused branch/PR per bounded phase, milestone, or fix set.
- Keep commits reviewable and messages descriptive.
- Do not merge your own PR unless explicitly instructed.
- Do not rewrite unrelated history or force-push unless explicitly authorized.
- Before handoff, ensure `docs/STATUS.md` describes the actual repository state rather than the intended state.

Recommended branch naming:

- `phase-0/foundation`
- `phase-1/map-discovery`
- `feature/<short-name>`
- `fix/<short-name>`
- `docs/<short-name>`

## 6. Architecture guardrails

Use clear replacement boundaries around Firebase, GIS, and platform services.

Preferred dependency direction:

```text
presentation
  ↓
application/state
  ↓
domain
  ↓
data repositories
  ↓
Firebase / Google Maps / platform adapters
```

Rules:

- Widgets should not scatter direct Firestore calls throughout the UI.
- Domain models should not depend on Firebase-specific types where avoidable.
- Keep geohash/query logic behind a repository/service boundary.
- Keep location permission/platform behavior behind a testable abstraction where practical.
- Prefer typed models and enums over arbitrary maps/strings.
- Avoid premature abstraction that does not protect a meaningful replacement or testing boundary.
- Do not introduce PostGIS, Places API, routing APIs, analytics, or additional infrastructure without an approved scope change.

## 7. Security and privacy guardrails

Treat `docs/03-privacy-security.md` as mandatory.

At minimum:

- Never commit secrets, service-account credentials, unrestricted API keys, signing credentials, or private configuration.
- Use platform/API restrictions for Google Maps keys.
- Require anonymous authentication for contribution writes as specified by the security model.
- Apply Firebase App Check as planned.
- Validate coordinates, controlled enums, and text lengths.
- Do not trust client-calculated aggregate/reputation fields where this creates an integrity issue.
- Do not persist location trails, background location, or search history tied to an identity.
- Do not expose contributor UIDs in public UI.
- Minimize collection of personal data and telemetry.

If a requested implementation weakens these controls, stop and flag it for review.

## 8. GIS and cost guardrails

FlushCrowd must remain inexpensive to operate during early growth.

- Do not query Firestore on every map movement frame.
- Debounce viewport queries.
- Query bounded geographic areas/radii.
- Use geohash candidate retrieval followed by exact distance filtering.
- Cache/reuse recent results where appropriate.
- Cluster dense map markers.
- Paginate potentially large child datasets such as reviews.
- Store safe aggregate fields when that avoids repeated fan-out reads.
- Avoid enabling paid Google Maps Platform APIs unless required by an approved phase.

## 9. UI/UX and accessibility guardrails

- Preserve the map-first experience.
- Core discovery must work without traditional account creation.
- Keep contribution flows short and task-focused.
- Indoor directions (building/floor/wing/landmark) are first-class UX, not optional afterthoughts.
- Build reusable design tokens/components rather than scattering visual constants.
- Include empty, loading, error, offline/degraded, and permission-denied states when applicable.
- Support appropriate touch targets, semantic labels, contrast, and text scaling.
- Validate meaningful UI changes on representative Android and iOS sizes when tooling is available.

## 10. Testing expectations

Testing depth should match risk. Prioritize tests for:

- coordinate validation;
- Haversine/distance logic;
- geospatial query boundary logic;
- model serialization/deserialization;
- controlled enum parsing;
- permission-state behavior;
- repository/service behavior;
- rating/contribution integrity rules;
- security rules when introduced;
- critical user flows as the app matures.

Do not delete or weaken tests merely to make CI pass without explaining and resolving the underlying issue.

## 11. Multi-agent handoff protocol

`docs/STATUS.md` is the coordination ledger between ChatGPT, Claude, Codex, Gemini/Antigravity, Copilot, Grok, and other agents.

Before finishing a task, update it with:

- current phase and milestone;
- branch and PR;
- latest known commit SHA when available;
- completed work;
- validation performed and results;
- open blockers/risks;
- exact next recommended task;
- any manual action required from the human owner.

Do not turn `STATUS.md` into a chronological diary. Keep it concise and current; Git history and PRs hold the detailed history.

## 12. Required handoff response

At the end of an implementation run, report:

```text
Task:
Branch:
Commit:
PR:

Implemented:
- ...

Validation:
- command/check — PASS | FAIL | NOT RUN

Docs updated:
- ...

Blockers / risks:
- ...

Next recommended action:
- ...
```

Use `NOT RUN` rather than implying success when an environment or credential is unavailable.

## 13. Human decisions

The human owner remains the final authority for:

- product/scope changes;
- UX changes that materially diverge from the canonical reference;
- architecture/platform changes;
- new paid services or material cost increases;
- privacy/data-collection expansion;
- production credentials and store configuration;
- merging milestone PRs unless explicit permission is given.

When uncertain, preserve the current documented decision and surface the question rather than guessing.