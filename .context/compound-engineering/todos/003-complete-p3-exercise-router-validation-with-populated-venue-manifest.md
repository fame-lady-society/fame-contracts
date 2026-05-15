---
status: complete
priority: p3
issue_id: "003"
tags: [router, deployment, validation, fixtures]
dependencies: []
---

# Exercise Router Validation With Populated Venue Manifest

## Problem Statement

Unit 5 validation now checks manifest-required venue families and targets, but the checked-in fixture manifest is still pending and has zero required venue targets. The happy-path local validation test therefore proves the helper logic compiles and passes for base config, but it cannot exercise real manifest-derived venue allowlisting until the frozen fixture snapshot is populated.

## Findings

- `FameRouterFixtureManifest.requiredVenueTargetCount()` currently returns `0`.
- `ValidateFameRouterBase.validateRequiredVenueTargets()` loops over that manifest table.
- `FameRouterFixtureManifest.isLaunchable()` now requires `requiredVenueTargetCount() != 0`, so a green launch check is blocked until this table is populated.

## Proposed Solutions

### Option 1: Populate Manifest Targets With Frozen Fixtures

**Approach:** When the frozen fixture snapshot is imported, add the required venue family/target table and extend deployment validation tests to use at least one real fixture target.

**Pros:**
- Tests the actual launch validation path.
- Keeps target enablement tied to fixture source of truth.

**Cons:**
- Blocked until production fixture data exists.

**Effort:** 1-2 hours after fixture data is available

**Risk:** Low

## Recommended Action

Completed. The fixture manifest now has required venue targets for every launch venue family, deployment configures them, and validation tests exercise the populated manifest path.

## Technical Details

Affected files:
- `test/router/fixtures/FameRouterFixtureManifest.sol`
- `test/router/FameRouterDeploymentValidation.t.sol`
- `script/DeployFameRouter.s.sol`
- `script/ValidateFameRouterBase.s.sol`

## Acceptance Criteria

- [ ] Manifest contains at least one required venue target per launch venue family.
- [ ] Deployment script enables every manifest-required family and target.
- [ ] Validation test proves a real manifest-required target passes only when enabled.
- [ ] `forge test --match-path test/router/FameRouterDeploymentValidation.t.sol` passes.

## Work Log

### 2026-05-12 - Closure

**By:** Codex

**Actions:**
- Populated `FameRouterFixtureManifest.requiredVenueTarget*`.
- Added deployment/validation tests for manifest-required venue enablement.
- Verified `forge test --match-path test/router/FameRouterDeploymentValidation.t.sol`.

**Learnings:**
- A nonzero required-target table is now part of the launchability gate.

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Captured Unit 5 review residual that happy-path venue validation is fixture-dependent.

**Learnings:**
- Launchability is blocked while `requiredVenueTargetCount()` is zero, which prevents a false green release.
