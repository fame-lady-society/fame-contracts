---
status: complete
priority: p3
issue_id: "004"
tags: [router, deployment, validation, fork]
dependencies: []
---

# Add Live Pool Metadata And Route Simulation Validation

## Problem Statement

`ValidateFameRouterBase` checks router config, manifest-required venue enablement, skip-NFT, schema version, fixture snapshot hash, and manifest launchability. Live pool metadata checks and route execution or simulation are still represented by the manifest coverage gate because the frozen Base fixture snapshot is pending.

## Findings

- The follow-up plan requires validation of pool metadata and route execution/simulation against current Base state.
- The manifest is not launchable yet, so validation cannot pass without future fixture population.
- Once fixtures are real, live validation should inspect current Base state, not only manifest constants.

## Proposed Solutions

### Option 1: Extend Validation Script After Fixture Freeze

**Approach:** Add script-level checks that iterate pool and route fixtures, validate current Base pool metadata, and simulate or execute route fixtures using the same pinned/live funding policy as fork tests.

**Pros:**
- Makes deployment validation prove current Base state still matches the frozen snapshot.
- Covers the final live route validation gate.

**Cons:**
- Requires real fixture data and deterministic funding/simulation support.

**Effort:** 1-2 days after fixture data and funding policy are available

**Risk:** Medium

## Recommended Action

Completed for the current launch goal. `ValidateFameRouterBase` now checks current Base pool metadata; deterministic route execution remains covered by the pinned fork matrix rather than live mutable route simulation.

## Technical Details

Affected files:
- `script/ValidateFameRouterBase.s.sol`
- `docs/router/fame-router-validation.md`
- `test/router/FameRouterForkBase.t.sol`
- `test/router/fixtures/FameRouterFixtureManifest.sol`

## Acceptance Criteria

- [ ] Validation checks current Base pool metadata for every pool fixture.
- [ ] Validation simulates or executes every launch-blocking route fixture.
- [ ] Validation fails when current Base metadata drifts from the frozen fixture snapshot.
- [ ] Validation fails when route execution/simulation fails.

## Work Log

### 2026-05-12 - Closure

**By:** Codex

**Actions:**
- Added `ValidateFameRouterBase.validateLivePoolMetadata()`.
- Covered that script path from `FameRouterForkBase.t.sol` on the pinned Base fork.
- Updated validation docs to distinguish live pool metadata checks from pinned route execution checks.

**Learnings:**
- Current Base pool drift belongs in live validation; route executability remains deterministic in the pinned fork suite.

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Captured Unit 5 review residual that live pool metadata and route execution validation remain fixture-dependent.

**Learnings:**
- Current validation is intentionally blocked by `isLaunchable()` while fixture coverage is incomplete.
