---
status: complete
priority: p2
issue_id: "008"
tags: [router, uniswap-v4, fork-tests, hook-data]
dependencies: []
---

# Prove Valid Non-Empty V4 Swap Hook Data

## Problem Statement

FameRouter and `router-ts` support bounded non-empty Uniswap V4 swap `hookData`, but the current production basedflick/ZORA fixture correctly uses empty ordinary swap `hookData`. The remaining proof target is narrower: find a valid production hook-specific payload or build a clearly labeled local hook harness that requires non-empty ordinary V4 swap `hookData`, then prove it through FameRouter without conflating it with Zora factory `postDeployHookData`.

## Findings

- basedflick/ZORA is hook-address V4 coverage with `hookData: "0x"`, not non-empty swap-hook-data coverage.
- Arbitrary non-empty hook bytes reverted inside the Doppler hook at pinned Base block `45884844`.
- Fleet-style ZORA creator-coin swaps use empty ordinary swap `hookData`; fleet non-empty bytes are factory `postDeployHookData` for deployment/self-snipe flows.
- `router-ts` now rejects catalog non-empty swap-hook-data proof unless a structured production or local-harness proof is provided.

## Proposed Solutions

### Option 1: Add A Valid Production Non-Empty Hook Payload

**Approach:** Identify a real Base V4 swap whose hook requires non-empty ordinary swap `hookData`, add the hook-specific payload to supported config, generate route artifacts, enable the hook-data hash, and execute the route on a pinned Base fork.

**Pros:**
- Proves the production path directly.
- Exercises the exact router allowlist behavior against live V4 control flow.

**Cons:**
- Requires a real hook-specific payload source; arbitrary bytes are invalid.

**Effort:** 2-4 hours after the route and payload source are known.

**Risk:** Medium.

### Option 2: Add A Dedicated Local Hook Harness

**Approach:** Deploy or configure a fork-local V4 hook/pool fixture that requires and validates non-empty ordinary swap `hookData`, then execute it through FameRouter with explicit local-harness labeling.

**Pros:**
- Proves end-to-end non-empty swap-hook-data plumbing without misrepresenting production ZORA creator-coin pools.

**Cons:**
- Less production-representative than a real Base hook route.

**Effort:** 4-8 hours.

**Risk:** Medium.

## Recommended Action

Closed as not applicable for the current pool universe. Do not spend implementation time on a non-empty ordinary V4 swap `hookData` proof unless the supported pool universe later adds a real hook that requires it.

## Technical Details

Affected files may include:
- `router-ts/src/catalog/creatorCoins.ts`
- `router-ts/src/adapters/universalRouterV4.ts`
- `router-ts/src/artifacts/writeArtifacts.ts`
- `test/router/FameRouterForkBase.t.sol`
- `test/router/fixtures/base-v1-pools.json`
- `test/router/fixtures/base-v1-solver-routes.json`
- `test/router/fixtures/base-v1-creator-coin-catalog.json`

## Resources

- `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`
- `docs/ideation/2026-05-12-fame-v4-hook-data-fork-route-ideation.md`
- `.context/compound-engineering/todos/007-complete-p2-prove-non-empty-v4-hook-data-fork-route.md`
- `../fleet/packages/server/src/services/v4SwapEncoder.ts`
- `../fleet/packages/server/scripts/deploy-trend-content.ts`

## Acceptance Criteria

- [x] Closed because no supported pool-universe hook requires non-empty ordinary V4 swap `hookData`.
- [x] Existing docs and fixtures keep Zora factory `postDeployHookData` separate from Universal Router V4 `PathKey.hookData`.
- [x] Existing generated route artifacts report non-empty swap-hook-data coverage only when such proof exists.

## Work Log

### 2026-05-12 - Residual Proof Split From Fixture Policy

**By:** Codex

**Actions:**
- Split this residual proof from todo 007 after implementing the fixture-policy/catalog baseline.
- Captured the valid proof bar so basedflick/ZORA is not forced to carry fabricated non-empty swap hook data.

**Learnings:**
- Hook-address production coverage and non-empty ordinary swap-hook-data coverage need separate durable tracking.

### 2026-05-14 - Closed As Not Applicable

**By:** Codex

**Actions:**
- Closed this residual proof target after user confirmed the hooks do not exist in the pool universe currently being used.
- Kept the fixture policy distinction intact: hook-address V4 routes with empty `hookData` remain valid coverage, but non-empty ordinary swap `hookData` is not a launch requirement without a real supported hook.

**Learnings:**
- Non-empty ordinary V4 swap hook-data proof should be demand-driven by the active pool universe, not maintained as generic coverage work.
