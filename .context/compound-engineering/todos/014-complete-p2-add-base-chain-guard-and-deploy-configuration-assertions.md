---
status: complete
priority: p2
issue_id: "014"
tags: [deployment, foundry, router, review]
dependencies: []
---

# Add Base Chain Guard And Deploy Configuration Assertions

## Problem Statement

`DeployFameRouter.run()` reads Base-specific environment variables and configures Base venue targets, but it does not assert the active chain id before broadcasting. The deployment validation test also does not assert that every manifest-required venue family and target is enabled on the router returned by the deploy script.

## Findings

- Review finding #4 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- Review finding #9 from the same synthesis.
- `script/DeployFameRouter.s.sol:20` starts broadcasting before checking `block.chainid` against `BASE_CHAIN_ID`.
- `test/router/FameRouterDeploymentValidation.t.sol:21` checks owner and launchability but not the configured venue targets/families, fee recipient, or fee ppm on the deployed router.

## Proposed Solutions

### Option 1: Guard `run()` Before Broadcast

**Approach:** Read `BASE_CHAIN_ID`, compare it with `block.chainid`, and revert before `vm.startBroadcast` if they differ. Extend deployment tests to assert the guard and all deploy-time configuration.

**Pros:**
- Prevents wrong-chain Base deployments.
- Small, direct change.
- Makes deployment tests prove what the script promises.

**Cons:**
- Requires careful test setup for `run()` with environment variables.

**Effort:** Small.

**Risk:** Low.

### Option 2: Split Base-Specific Deployment Into A Chain-Specific Script

**Approach:** Rename or restructure deployment scripts to make Base-only deployment impossible to confuse with other networks.

**Pros:**
- Clearer release ergonomics.

**Cons:**
- Larger change than needed for the current risk.

**Effort:** Medium.

**Risk:** Low to medium.

## Recommended Action

Implement Option 1. Add a pre-broadcast `BASE_CHAIN_ID` guard in `DeployFameRouter.run()` and extend deployment tests to assert the wrong-chain revert plus all deploy-time router configuration: owner, fee recipient, fee ppm, and every manifest-required venue family/target.

## Technical Details

Affected files:

- `script/DeployFameRouter.s.sol`
- `test/router/FameRouterDeploymentValidation.t.sol`

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- Correctness reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/correctness.json`
- Reliability reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/reliability.json`
- Testing reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/testing.json`

## Acceptance Criteria

- [x] `DeployFameRouter.run()` reverts before `vm.startBroadcast` when `block.chainid != BASE_CHAIN_ID`.
- [x] Deployment tests cover the wrong-chain case.
- [x] Deployment tests assert owner, fee recipient, fee ppm, and every required manifest venue family/target on the returned router.
- [x] Targeted Forge deployment-validation tests pass.

## Work Log

### 2026-05-15 - Deploy Guard Added

**By:** Codex

**Actions:**
- Added a `BASE_CHAIN_ID` guard at the start of `DeployFameRouter.run()`, before deployer key lookup and broadcast.
- Extended deployment validation tests to assert wrong-chain rejection and all deployed router config.

**Verification:**
- `forge test --match-path test/router/FameRouterDeploymentValidation.t.sol`

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review findings #4 and #9.

**Learnings:**
- Deployment scripts should fail before broadcast when public Base config and active RPC chain disagree.
