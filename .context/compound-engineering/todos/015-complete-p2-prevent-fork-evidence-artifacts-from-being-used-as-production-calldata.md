---
status: complete
priority: p2
issue_id: "015"
tags: [router-ts, artifacts, safety, review]
dependencies: []
---

# Prevent Fork-Evidence Artifacts From Being Used As Production Calldata

## Problem Statement

Generated solver route artifacts are marked as fork evidence, but they still include full `abiEncodedRoute`, long deterministic deadlines, and one-wei smoke-test minimums. A careless consumer could submit them directly instead of going through production materialization.

## Findings

- Review finding #6 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- `test/router/fixtures/base-v1-solver-routes.json:57` includes executable calldata even though each artifact has `productionExecutable: false`.
- Previous work added metadata and a production materialization API, but did not remove or quarantine test-only calldata.

## Proposed Solutions

### Option 1: Keep Calldata But Require Consumer Rejection

**Approach:** Keep test fixtures as-is for Foundry parity, but add parser/API tests that reject `productionExecutable: false` before exposing calldata to any production caller.

**Pros:**
- Preserves existing fork-test pipeline.
- Smallest change.
- Aligns with current metadata model.

**Cons:**
- Relies on every consumer respecting the flag.

**Effort:** Small.

**Risk:** Low to medium.

### Option 2: Move Executable Calldata Into Test-Only Fixtures

**Approach:** Split fork evidence from production-facing metadata so production-oriented artifacts never contain submit-able calldata.

**Pros:**
- Harder to misuse artifacts accidentally.
- Clearer separation of evidence and production route exports.

**Cons:**
- More fixture migration work.
- Foundry parity readers may need updates.

**Effort:** Medium.

**Risk:** Medium.

## Recommended Action

Implement Option 1. Preserve the current fork-evidence fixture pipeline, but add a production-boundary API/test that refuses to expose or submit calldata from artifacts with `productionExecutable: false` unless they have gone through explicit production materialization.

## Technical Details

Affected files:

- `router-ts/src/artifacts/schema.ts`
- `router-ts/src/artifacts/writeArtifacts.ts`
- `test/router/fixtures/base-v1-solver-routes.json`
- `test/router/FameRouterGeneratedArtifacts.t.sol`
- consumer code in `../www` if it reads these artifacts directly

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- Adversarial reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/adversarial.json`
- Reliability reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/reliability.json`

## Acceptance Criteria

- [x] Production consumers cannot submit `productionExecutable: false` artifacts without explicit materialization.
- [x] Tests prove fork-evidence artifacts are rejected or quarantined at the production boundary.
- [x] Fork artifact parity tests still pass.
- [x] Documentation explains the difference between fork evidence and production materialization.

## Work Log

### 2026-05-15 - Production Calldata Boundary Added

**By:** Codex

**Actions:**
- Added a production calldata accessor that rejects `productionExecutable: false` fork-evidence artifacts.
- Added materialization tests proving fork evidence cannot be exposed as production calldata without explicit materialization.
- Documented the fork-evidence versus production-materialization boundary.

**Verification:**
- `bun run router:test`
- `forge test --match-path test/router/FameRouterGeneratedArtifacts.t.sol`

## Work Log

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review finding #6.

**Learnings:**
- Metadata flags help, but production boundaries need executable rejection or artifact separation.
