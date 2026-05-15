---
status: complete
priority: p2
issue_id: "011"
tags: [router-ts, schema, api-contract, review]
dependencies: []
---

# Harden router-ts JSON Route Schema Boundary

## Problem Statement

`router-ts` converts checked-in JSON route artifacts back into typed `Route` values, but the conversion currently trusts enum names and ordinal fields too much. Unknown venue or amount-mode names can slip through if the corresponding ordinal field is absent, because both sides of the current comparison can evaluate to `undefined`.

## Findings

- Review finding #1 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- `router-ts/src/artifacts/schema.ts:162` uses `VenueFamily[leg.venue] !== leg.venueOrdinal` and the equivalent amount-mode check.
- If `leg.venue` is not an own key of `VenueFamily` and `venueOrdinal` is missing, both values can be `undefined`, so the mismatch check does not reject the malformed JSON.
- API-contract and TypeScript review both flagged this as a P2 schema-boundary bug.

## Proposed Solutions

### Option 1: Validate JSON Before Conversion

**Approach:** Treat JSON as untrusted at the boundary. Require schema version, enum names, ordinal fields, numeric/string bigint fields, address fields, and hex payload fields to pass explicit runtime validation before returning a `Route`.

**Pros:**
- Closes the immediate bug.
- Keeps malformed artifacts from becoming executable route objects.
- Easy to test with negative fixtures.

**Cons:**
- Adds a small amount of validation code to a module that currently mostly serializes.

**Effort:** Small.

**Risk:** Low.

### Option 2: Parse Through a Schema Library

**Approach:** Introduce a runtime schema parser for route artifacts and use it for all JSON artifact loading.

**Pros:**
- Gives a more complete typed boundary.
- Future schema additions become easier to validate consistently.

**Cons:**
- Adds dependency and abstraction overhead.
- More than needed for the immediate bug.

**Effort:** Medium.

**Risk:** Medium.

## Recommended Action

Implement Option 1. Add explicit runtime validation at the JSON-to-Route boundary without introducing a new schema dependency. Focus on known enum names, required matching ordinal fields, route schema version, and negative tests for malformed enum names with missing ordinals.

## Technical Details

Affected files:

- `router-ts/src/artifacts/schema.ts`
- `router-ts/test/artifact-schema.spec.ts`
- `router-ts/test/materialize-route.spec.ts`

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- API-contract reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/api-contract.json`
- TypeScript reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/kieran-typescript.json`

## Acceptance Criteria

- [x] `routeFromJson` rejects unknown venue names even when `venueOrdinal` is missing.
- [x] `routeFromJson` rejects unknown amount-mode names even when `amountModeOrdinal` is missing.
- [x] Ordinal fields are required and must match the canonical enum values.
- [x] Route schema version is validated before conversion.
- [x] Negative tests cover malformed enum names and missing ordinals.

## Work Log

### 2026-05-15 - Runtime Boundary Hardened

**By:** Codex

**Actions:**
- Added schema version, legs-array, enum-name, and enum-ordinal checks before JSON artifacts become typed routes.
- Added negative Bun tests for unknown enum names, missing ordinals, and unsupported schema versions.

**Verification:**
- `bun run router:typecheck`
- `bun run router:test`
- [ ] `bun run --cwd router-ts verify` passes.

## Work Log

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review finding #1.

**Learnings:**
- TypeScript enum reverse lookup is not enough runtime validation when JSON fields can be missing.
