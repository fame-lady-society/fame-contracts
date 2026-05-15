---
status: complete
priority: p2
issue_id: "007"
tags: [router, uniswap-v4, fork-tests, route-solver]
dependencies: []
---

# Define V4 Creator-Coin Fixture Policy And Catalog

## Problem Statement

The router schema and onchain implementation support bounded non-empty Uniswap V4 hook data through `setV4HookDataHashEnabled`, but the fixture set needs a clearer policy for what V4 hook coverage means. The current production basedflick/ZORA route is a hook-addressed pool with explicit empty swap `hookData`, so forcing arbitrary non-empty bytes into that fixture is invalid. The next step is to define and implement truthful fixture coverage for ZORA creator-coin pools, including a fleet-style pool importer/catalog, while keeping valid non-empty swap-hook-data proof as a separate evidence target.

## Findings

- Review found that hook-address pool coverage is not equivalent to non-empty hook-data coverage.
- The basedflick/ZORA Doppler pool in `test/router/fixtures/base-v1-pools.json` now carries explicit `hookData: "0x"`.
- A trial generated route using arbitrary non-empty hook data against that pool reverted in the Doppler hook at pinned Base block `45884844`.
- `../fleet` uses `hookData: "0x"` for ordinary ZORA creator-coin swaps. Its non-empty bytes are factory `postDeployHookData`, not Universal Router V4 `PathKey.hookData`.
- `test/router/FameRouter.t.sol` covers the schema behavior with mocks: allowed non-empty hook data is forwarded, and unapproved hook data reverts.

## Proposed Solutions

### Option 1: Add Fixture Policy Plus Creator-Coin Pool Catalog

**Approach:** Implement a route-fixture policy that distinguishes hook-address swaps, non-empty swap `hookData`, factory/deploy hook data, and local hook-harness coverage. Add a fleet-style creator-coin pool importer/catalog for known ZORA creator-coin pairings such as basedflick/ZORA, then only promote catalog entries into solver/fork fixtures after route artifacts and fork execution prove them.

**Pros:**
- Aligns fixtures with how production ZORA creator-coin swaps actually work.
- Prevents invalid arbitrary hook data from becoming launchable fixture evidence.
- Builds reusable pool metadata coverage for future composed FAME/ZORA routes.

**Cons:**
- Does not by itself prove a production non-empty swap-hook-data payload unless such a route is discovered.

**Effort:** 2-4 hours for the policy/catalog baseline, plus fork validation time.

**Risk:** Low to medium.

### Option 2: Add the Correct Production Hook Payload

**Approach:** Identify a real Base V4 route whose swap hook requires non-empty hook data, add the exact payload to the supported pool/route config, regenerate solver artifacts, and prove it through the pinned Base fork suite.

**Pros:**
- Proves the production path originally requested.
- Exercises the router hook-data allowlist on a real fork.

**Cons:**
- Requires the correct hook-specific payload; arbitrary bytes are not valid for the known Doppler pool.

**Effort:** 2-4 hours after the route/payload source is known.

**Risk:** Medium.

### Option 3: Add a Dedicated Local Hook Harness

**Approach:** If no production route requiring non-empty swap `hookData` is available, deploy or configure a fork-local V4 hook scenario that accepts and validates non-empty swap hook data, then execute it through FameRouter with explicit coverage labeling.

**Pros:**
- Proves the end-to-end non-empty hook-data path without misrepresenting basedflick/ZORA.

**Cons:**
- Less production-representative than a real Base hook route.

**Effort:** 4-8 hours.

**Risk:** Medium.

## Recommended Action

Implement Option 1 first. Keep Options 2 and 3 as separate residual proof paths for non-empty swap `hookData`.

## Technical Details

Affected files:
- `router-ts/src/config/base.ts`
- `router-ts/src/adapters/universalRouterV4.ts`
- `router-ts/src/artifacts/writeArtifacts.ts`
- `test/router/FameRouterForkBase.t.sol`
- `test/router/fixtures/base-v1-pools.json`
- `test/router/fixtures/base-v1-solver-routes.json`

## Resources

- `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`
- `docs/ideation/2026-05-12-fame-v4-hook-data-fork-route-ideation.md`
- `.context/compound-engineering/todos/008-complete-p2-prove-valid-non-empty-v4-swap-hook-data.md`
- `docs/plans/2026-05-12-002-feat-fame-route-solver-fork-matrix-plan.md`
- `../fleet/packages/server/src/services/v4SwapEncoder.ts`
- `../fleet/packages/server/src/services/v4Quoter.ts`
- `../fleet/packages/server/src/services/coinRoute.ts`
- `../fleet/packages/server/src/services/poolDiscovery.ts`

## Acceptance Criteria

- [x] Fixture docs, manifests, or gap matrices distinguish hook-address V4 coverage from non-empty swap-hook-data coverage.
- [x] A creator-coin pool catalog/importer validates basedflick/ZORA-style metadata from fleet-style evidence such as pool methods, factory logs, storage fallback, or committed config.
- [x] Production ZORA creator-coin fixtures use explicit empty swap `hookData` when that is the valid pool behavior, and they are not labeled as non-empty hook-data proof.
- [x] No fixture uses fabricated non-empty V4 swap `hookData`.
- [x] Catalog-promoted route fixtures execute through `FameRouter` on the pinned Base fork before they are described as fork-covered.
- [x] The residual non-empty swap-hook-data proof was separately evaluated in todo 008 and closed as not applicable for the current pool universe.

## Work Log

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Added bounded hook-data support and unit tests.
- Attempted non-empty generated hook data for basedflick/ZORA.
- Observed the real Doppler hook rejects arbitrary non-empty swap hook data at block `45884844`.
- Documented the follow-up in the route solver plan.

**Learnings:**
- Non-empty hook data cannot be fabricated for a production hook route; it must be hook-specific.

### 2026-05-12 - Reframed Around Fixture Policy

**By:** Codex

**Actions:**
- Confirmed from fleet references that ordinary ZORA creator-coin swaps use empty swap `hookData`.
- Created `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`.
- Reframed this todo around truthful fixture policy plus a creator-coin pool catalog, while preserving valid non-empty swap-hook-data proof as a residual target.

**Learnings:**
- basedflick/ZORA should prove hook-address V4 route coverage with `hookData: "0x"`, not fabricated non-empty swap-hook-data behavior.

### 2026-05-12 - Implemented Catalog And Coverage Policy

**By:** Codex

**Actions:**
- Added a deterministic `router-ts` creator-coin catalog for basedflick/ZORA.
- Generated `test/router/fixtures/base-v1-creator-coin-catalog.json` and tied it to `FameRouterSolverFixtureManifest`.
- Split route capabilities so hook-address V4 coverage and non-empty swap-hook-data coverage are reported separately.
- Verified pure TypeScript generation and Foundry generated-artifact parity.
- Opened todo 008 for the residual valid production or local-harness non-empty ordinary V4 swap-hook-data proof.

**Learnings:**
- The current production evidence now closes the policy/catalog gap. A future non-empty ordinary swap-hook-data proof should be tracked as a new, narrower follow-up if a valid production payload or local harness is identified.

### 2026-05-14 - Residual Proof Retired

**By:** Codex

**Actions:**
- Retired the residual non-empty hook-data proof path after user confirmed those hooks are not present in the pool universe currently being used.
- Renamed the file from `pending` to `complete` to match its frontmatter status and prevent future todo scans from treating this as unresolved.

**Learnings:**
- The completed fixture-policy/catalog work is sufficient for the current route universe; non-empty hook-data evidence should only return if a supported pool actually requires it.
