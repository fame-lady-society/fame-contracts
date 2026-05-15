---
status: complete
priority: p2
issue_id: "010"
tags: [router, aerodrome, solidly, slipstream, route-solver]
dependencies: []
---

# Add Aerodrome V2 And Migrated Slipstream Pool Support

## Problem Statement

The app-side FAME swap solver has validated high-value Base USDC/WETH liquidity in Aerodrome V2 and Aerodrome migrated Slipstream pools, but the current FameRouter adapter support cannot safely execute those routes.

Until contract-side router support is added and proven, `www` keeps these pools in the reviewed pool universe as blocked diagnostics rather than executable route candidates:

- Aerodrome V2 USDC/WETH: `0xcdac0d6c6c59727a65f871236188350531885c43`
- Aerodrome migrated Slipstream USDC/WETH tick-spacing 50: `0x3fe04a59ebd38cf06080a6f60a98d124eb59392a`

## Findings

- Aerodrome V2 pool `0xcdac0d6c6c59727a65f871236188350531885c43` is a real volatile USDC/WETH pool with token0 WETH, token1 USDC, stable false, and meaningful reserves.
- Aerodrome V2 router `0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43` expects 4-field routes with an explicit factory, while current FameRouter Solidly support encodes 3-field Solidly-style routes.
- Aerodrome V2 gauge `0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025` is not the executable pool; it points back to the pool as its staking token.
- Migrated Slipstream pool `0x3fe04a59ebd38cf06080a6f60a98d124eb59392a` has token0 WETH, token1 USDC, factory `0xf8f2eB4940CFE7d13603DDDD87f123820Fc061Ef`, tickSpacing 50, and live `slot0`/`liquidity` state.
- Current Slipstream support validates and quotes through the canonical factory `0x5e7B...`; the migrated factory needs explicit router/quoter validation so it does not accidentally quote a same-pair, same-tick-spacing pool from a different factory.
- Migrated Slipstream gauge `0xA0B61fdB9f1FB9b917Fe38b49427Fd4D87472D28` is not the executable pool; its `pool()` method points back to `0x3fe04a59ebd38cf06080a6f60a98d124eb59392a`.
- `../www` has already added these pools with blocked enablement reasons in `src/features/fame-swap/artifacts/base-v1-pools.json`.

## Proposed Solutions

### Option 1: Add Aerodrome V2 Route Shape Support

**Approach:** Extend Solidly-family route encoding or add a dedicated Aerodrome V2 venue variant that includes the explicit factory field required by Aerodrome V2 router routes. Validate factory allowlisting and exact route execution through unit and fork tests.

**Pros:**
- Unlocks the large Aerodrome V2 USDC/WETH pool directly.
- Keeps factory selection explicit and auditable.
- Avoids overloading existing 3-field Solidly route semantics.

**Cons:**
- Requires route schema, ABI, router-ts, manifest, and fixture updates.
- Adds another venue shape to test and maintain.

**Effort:** 4-8 hours.

**Risk:** Medium.

---

### Option 2: Add Migrated Slipstream Factory Support

**Approach:** Extend Slipstream routing support to allow a reviewed migrated factory/router/quoter tuple for the `0xf8f2...` factory. Prove that quotes and router execution target the intended pool address, not a matching tick-spacing pool from the canonical factory.

**Pros:**
- Unlocks the migrated tick-spacing 50 USDC/WETH pool once the migration path is stable.
- Preserves current fail-closed behavior for unknown Slipstream deployments.

**Cons:**
- Requires careful factory-specific quoter validation.
- Aerodrome migration state may continue changing, so fixture evidence can go stale.

**Effort:** 4-8 hours.

**Risk:** Medium.

## Recommended Action

To be filled during triage. Initial recommendation: implement Aerodrome V2 explicit-factory routes first because the pool is not marked as migrating and the failure mode is a well-defined route-shape gap. Treat migrated Slipstream factory support as a separate acceptance path unless one implementation can support both without weakening factory allowlists.

## Technical Details

Affected areas may include:

- `src/FameRouter.sol`
- `src/router/FameRouterTypes.sol`
- Solidly/Aerodrome route adapters
- Slipstream route adapters and factory validation
- `router-ts` route encoding and artifact writers
- Manifest venue target and factory allowlists
- Fork fixtures for Base USDC/WETH routes

Pool evidence from `www`:

- `aerodrome-v2-usdc-weth` is currently blocked because Aerodrome V2 uses explicit-factory 4-field routes while current FameRouter Solidly support uses 3-field routes.
- `slipstream-usdc-weth-migrating-50` is currently blocked because it belongs to migrated factory `0xf8f2eB4940CFE7d13603DDDD87f123820Fc061Ef`, while current FameRouter Slipstream support validates the canonical `0x5e7B...` factory.

## Resources

- App-side pool universe: `../www/src/features/fame-swap/artifacts/base-v1-pools.json`
- App-side route-lab docs: `../www/docs/fame-swap-route-lab.md`
- App-side pool gating type: `../www/src/features/fame-swap/router/types.ts`

## Acceptance Criteria

- [x] Aerodrome V2 explicit-factory USDC/WETH routes can be encoded in router-ts without changing existing Solidly 3-field route behavior.
- [x] FameRouter executes an Aerodrome V2 USDC/WETH hop through the intended router and factory.
- [x] Bad Aerodrome V2 factory, bad router target, and wrong-pool route cases fail closed.
- [x] Migrated Slipstream factory support either remains explicitly blocked or is added with factory-specific route, quote, and fork execution proof.
- [x] If migrated Slipstream support is added, the route tests prove execution against pool `0x3fe04a59ebd38cf06080a6f60a98d124eb59392a`, not a canonical-factory same-pair pool.
- [x] Manifests and generated app artifacts expose the newly supported pool ids only after fork execution passes.
- [x] `../www` can remove the blocked enablement reasons for supported pools and route-lab shows them as selected or considered rather than disabled.

## Work Log

### 2026-05-14 - Initial Discovery

**By:** Codex

**Actions:**
- Probed the supplied Aerodrome V2 and migrated Slipstream USDC/WETH pools through Doppler-provided Base RPC from `../www`.
- Confirmed the supplied gauge addresses are gauges/wrappers, not pool addresses for route execution.
- Added app-side pool-universe entries with explicit blocked enablement gating until contract support is available.
- Captured the contract-side work needed to make these pools executable.

**Learnings:**
- Aerodrome V2 support is blocked by a route encoding mismatch, not by bad pool state.
- Migrated Slipstream support needs factory-aware validation to avoid quoting or executing against the wrong same-pair pool.

### 2026-05-15 - Aerodrome V2 Explicit-Factory Support Shipped

**By:** Codex

**Actions:**
- Added `AerodromeV2 = 7` as a distinct FameRouter venue with four-field `{ from, to, stable, factory }` route payloads.
- Preserved existing `Solidly` three-field route behavior and tests.
- Added router-ts Aerodrome V2 encoding, fixture parsing, deterministic generated artifacts, launch manifest target evidence, and pinned Base fork coverage.
- Verified pinned Base Aerodrome V2 evidence for router `0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43`, factory `0x420dd381b31aef6683db6b902084cb0ffece40da`, and pool `0xcdac0d6c6c59727a65f871236188350531885c43`.
- Deployed and verified new Base FameRouter `0xAdefa5860389E8936ebf2977e1Fb4a365aA39636`.
- Created app-side follow-up todo `../www/.context/compound-engineering/todos/015-ready-p1-enable-aerodrome-v2-explicit-factory-router.md`.

**Resolution:**
- Aerodrome V2 explicit-factory support is complete contract-side.
- Migrated Slipstream remains intentionally out of scope and explicitly blocked behind a separate factory/router/quoter proof gate.
