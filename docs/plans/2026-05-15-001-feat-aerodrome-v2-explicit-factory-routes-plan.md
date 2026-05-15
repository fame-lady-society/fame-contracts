---
title: "feat: Add Aerodrome V2 Explicit-Factory Routes"
type: feat
status: implemented
date: 2026-05-15
origin: docs/brainstorms/2026-05-15-aerodrome-v2-explicit-factory-route-support-requirements.md
---

# feat: Add Aerodrome V2 Explicit-Factory Routes

## Overview

Add a distinct `AerodromeV2` route venue to `FameRouter` for Base Aerodrome V2 ERC-20 exact-input swaps whose route hops encode `{ from, to, stable, factory }`. This keeps existing `Solidly` three-field route payloads unchanged, appends venue ordinal `7` under schema version `1`, and promotes the app-discovered Aerodrome V2 USDC/WETH pool only after contract artifacts, fork proof, manifest evidence, deployment config, and `www` schema parity all agree.

The first slice is intentionally narrow. It unlocks Aerodrome V2 explicit-factory routes; it does not implement migrated Slipstream support, generic factory-keyed venue modeling, or route discovery/quoting.

## Problem Frame

The app solver has identified the Base Aerodrome V2 USDC/WETH pool `0xcdac0d6c6c59727a65f871236188350531885c43` behind router `0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43`, but the current contract venue named `Solidly` only supports the Scale/Equalizer three-field route shape. Reusing that venue for Aerodrome V2 would make route bytes ambiguous and would allow `router-ts` or `www` to silently compile the wrong payload shape.

The contract repo should make the explicit-factory ABI visible in the schema, adapters, fixtures, docs, and launch manifests. The app repo can then remove its Aerodrome V2 blocker only after the new deployed router address and schema support are present.

## Requirements Trace

- R1-R4. Add an Aerodrome V2 exact-input ERC-20 venue with four-field route hops, distinct ordinal `7`, schema v1 parity across Solidity/TypeScript/docs/app consumers, and fail-closed route-shape validation.
- R5. Confirm the Aerodrome V2 router ABI before code edits: tuple order, selector surface, return type, deadline argument, and bad-factory behavior.
- R6. Preserve route-local accounting, target allowlisting, per-leg minimums, final fee settlement, and no-stranded-balance invariants.
- R7-R12. Add fixture and validation evidence for the Base Aerodrome V2 USDC/WETH pool, including router, factory, pool address, tokens, stable flag, fee evidence, factory-derived pool identity, and negative fork coverage.
- R13, R16-R17. Deploy a new router binary with regenerated manifest hashes and enable the Aerodrome V2 target only when launch evidence is synchronized; update `BASE_FAME_ROUTER_ADDRESS` and app schema parity before app unblock.
- R14-R15. Keep migrated Slipstream out of scope, with a clear follow-up gate for router/quoter/factory tuple proof, factory-keyed pool identity, and pinned fork execution.

## Scope Boundaries

- Do not change existing `Solidly` payload encoding or execution behavior.
- Do not treat Aerodrome V2 as Uniswap V2-style `address[] path` routing.
- Do not add onchain route discovery or quoting.
- Do not collapse Solidly, Aerodrome V2, Slipstream, and Slipstream2 into a generic factory-configured venue model.
- Do not implement migrated Slipstream factory support in this slice.
- Do not remove the app-side Aerodrome V2 blocker until contract deployment and schema parity exist.

### Deferred to Separate Tasks

- `www` integration: add `AerodromeV2 = 7`, encode four-field payloads, update route builder/schema tests, remove the blocked reason, and consume the new deployed `BASE_FAME_ROUTER_ADDRESS` after contract proof lands.
- Migrated Slipstream: prove stable router/quoter/factory tuple, factory-keyed pool identity, and pinned fork execution for the migrated pool before promotion.
- Rich route selection: keep the app solver as the source of general-purpose route discovery and quality decisions.

## Context & Research

### Relevant Code and Patterns

- `src/router/FameRouterTypes.sol` defines schema version `1` and currently ends `VenueFamily` at `NativeWrap = 6`.
- `src/FameRouter.sol` performs venue family/target allowlist checks before dispatch, skips approvals only for `NativeWrap`, uses Permit2 only for V3/V4, and dispatches typed adapters through `_dispatch`.
- `src/router/adapters/SolidlyRouterAdapter.sol` decodes `Payload(ISolidlyRouter.Route[] routes, uint256 deadline)`, where each route has `from`, `to`, and `stable`; it rejects native ETH and route endpoint/continuity mismatches.
- `src/router/adapters/SlipstreamAdapter.sol` is the local pattern for carrying explicit router/factory metadata in payloads and verifying the live target factory before execution.
- `router-ts/src/compiler/types.ts`, `router-ts/src/adapters/solidly.ts`, `router-ts/src/config/base.ts`, `router-ts/src/artifacts/schema.ts`, `router-ts/src/artifacts/routeEncoding.ts`, and `router-ts/src/artifacts/writeArtifacts.ts` mirror the Solidity schema and generate deterministic artifacts/manifests.
- `test/router/FameRouter.t.sol` owns enum ordinal tests and typed adapter unit tests. The next invalid raw venue ordinal currently needs to move from `7` to `8`.
- `test/router/FameRouterForkBase.t.sol` owns pinned Base fixture execution and pool metadata checks.
- `script/ValidateFameRouterBase.s.sol` verifies deployed router allowlists, fixture hashes, and pool metadata; it already has venue-specific paths for Solidly stable flags and Slipstream/Uniswap tick-spacing or fee metadata.
- `script/DeployFameRouter.s.sol` enables deployment targets from `FameRouterFixtureManifest`, so Aerodrome V2 should flow through the launch manifest rather than a manual post-deploy owner call.
- `docs/router/fame-router-schema.md` and `docs/router/fame-router-validation.md` are the integration references that must document the new wire ordinal, payload shape, fixture evidence, and app unblock gate.

### App-Side Seed Evidence

- The sibling app repo's FAME swap pool artifact currently has `aerodrome-v2-usdc-weth` marked as `venue: "solidly"` but blocked because the Aerodrome V2 router uses four-field routes and the current router target is not enabled.
- The app-side seed records router `0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43`, pool `0xcdac0d6c6c59727a65f871236188350531885c43`, WETH/USDC token ordering, `stable: false`, and `feeBps: 30`. It does not include the factory address, so implementation must verify and add that from onchain evidence before promotion.

### External References

- Aerodrome's primary `IRouter` interface defines `swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, Route[] calldata routes, address to, uint256 deadline) external returns (uint256[] memory amounts)`, and the swap route type includes `from`, `to`, `stable`, and `factory`: https://github.com/aerodrome-finance/contracts/blob/main/contracts/interfaces/IRouter.sol

### Institutional Constraints

- Public addresses and deployed router constants belong in `config/fame-public.env`.
- RPC URLs, deployer keys, explorer keys, and other secrets remain in Doppler.
- Deployment and validation docs should use Foundry chain aliases such as `base` instead of raw RPC URLs.

## Key Technical Decisions

- Append `AerodromeV2` as `VenueFamily` ordinal `7` under schema version `1`. Existing ordinals stay stable; app/schema parity is required before enablement.
- Add a dedicated Aerodrome V2 interface and adapter instead of mutating `ISolidlyRouter` or overloading `SolidlyRouterAdapter`. The ABI difference is part of the venue contract.
- Keep Aerodrome V2 approval behavior in the direct-approval family. It is an ERC-20 router adapter like Solidly/UniswapV2/Slipstream, not a Permit2/Universal Router path and not approval-free like NativeWrap.
- Require payload-local factory evidence for every Aerodrome V2 route hop. Reject zero factories, zero tokens, bad endpoints, and broken continuity before external execution.
- Validate pool identity independently from route execution. Fixture validation must derive the selected pool from Aerodrome factory/router/token/stable metadata and assert the expected USDC/WETH pool address.
- Treat fee evidence explicitly. If the Aerodrome V2 pair exposes no stable onchain fee API, fixtures should label `feeBps` as offchain/static evidence and validation should not pretend it proved a live fee.
- Enable the Aerodrome V2 router target through `FameRouterFixtureManifest` only after fixture and fork evidence are launchable.

## Open Questions

### Resolved During Planning

- Aerodrome V2 route ABI: primary Aerodrome source confirms four route fields in this order: `from`, `to`, `stable`, `factory`.
- Aerodrome V2 swap selector shape: use `swapExactTokensForTokens(amountIn, amountOutMin, routes, to, deadline)` with `Route[] calldata` and `uint256[] memory amounts` return, matching the Solidly-style execution shape with a different route tuple.
- Schema strategy: append `AerodromeV2 = 7` under schema v1 rather than bumping schema version.
- Venue split: keep existing `Solidly` three-field routes separate from Aerodrome V2 explicit-factory routes.

### Deferred to Implementation

- Exact factory address for the target pool, verified against the pinned Base block.
- Exact factory method used for pool identity derivation, such as `getPool(tokenA, tokenB, stable)` or the Aerodrome-pair equivalent available on the deployed factory.
- Exact invalid-factory revert surface. The adapter should reject zero/structurally bad factories itself; fork tests can assert that a wrong nonzero factory fails closed without depending on a brittle revert selector.
- Exact launch route fixture shape. Prefer the smallest deterministic FAME route that includes the Aerodrome V2 USDC/WETH hop and already-supported downstream liquidity; add the reverse direction only if the fixture policy or app unblock needs it.

## High-Level Technical Design

> This is directional planning context, not implementation code.

```text
Route leg venue AerodromeV2
  -> FameRouter allowlist and direct ERC-20 approval path
  -> AerodromeV2RouterAdapter.execute(...)
  -> decode Payload(Route[] routes, uint256 deadline)
  -> validate token endpoints, continuity, nonzero factories, ERC-20 only
  -> IAerodromeV2Router(target).swapExactTokensForTokens(
       amountIn,
       leg.minAmountOut,
       routes,
       recipient,
       payload.deadline
     )
  -> return amounts[last]
  -> FameRouter route-local output delta enforces leg/final invariants
```

Suggested payload shape:

```text
AerodromeV2RouterAdapter.Payload:
  Route[] routes
    address from
    address to
    bool stable
    address factory
  uint256 deadline
```

## Implementation Units

- [x] **Unit 1: Solidity Schema And Aerodrome V2 Adapter**

**Goal:** Add an explicit Solidity venue and adapter for Aerodrome V2 four-field route execution while preserving existing Solidly behavior.

**Requirements:** R1-R6, R10

**Dependencies:** None

**Files:**
- Modify: `src/router/FameRouterTypes.sol`
- Modify: `src/FameRouter.sol`
- Create: `src/router/interfaces/IAerodromeV2Router.sol`
- Create: `src/router/adapters/AerodromeV2RouterAdapter.sol`
- Test: `test/router/FameRouter.t.sol`
- Modify: `docs/router/fame-router-schema.md`

**Approach:**
- Append `AerodromeV2` after `NativeWrap`.
- Import and dispatch `AerodromeV2RouterAdapter` from `FameRouter._dispatch`.
- Keep Aerodrome V2 out of `_usesPermit2` and out of NativeWrap approval bypasses.
- Add an interface with the exact Aerodrome route tuple and swap method confirmed from the primary source.
- Validate ERC-20-only legs, nonempty route arrays, first/last endpoints, route continuity, nonzero `from`/`to`, and nonzero per-hop `factory`.
- Return the last value from the router's `amounts` array and rely on existing route-local balance deltas for actual output enforcement.
- Update enum ordinal tests: `NativeWrap == 6`, `AerodromeV2 == 7`, and the next invalid raw enum decode test uses `8`.
- Keep all existing Solidly tests unchanged except for ordinal expectations.

**Test scenarios:**
- Happy path: Aerodrome V2 mock router receives a four-field route payload and returns final output.
- Regression: existing Solidly three-field route payload still encodes and executes.
- Error path: raw venue ordinal `8` fails ABI enum decoding.
- Error path: native ETH input or output on Aerodrome V2 reverts.
- Error path: empty route array, bad first endpoint, bad last endpoint, bad intermediate continuity, zero token, or zero factory reverts before external swap.
- Error path: disabled Aerodrome V2 family or target fails through the existing allowlist path.
- Invariant: successful Aerodrome V2 leg clears direct ERC-20 allowance after execution, matching direct venue policy.

**Verification:**
- `forge test --match-path test/router/FameRouter.t.sol`

- [x] **Unit 2: TypeScript Schema, Config, And Payload Encoding**

**Goal:** Teach `router-ts` to represent and encode Aerodrome V2 as its own venue with explicit factory route hops.

**Requirements:** R2-R4, R7-R8, R13, R16

**Dependencies:** Unit 1 schema decision

**Files:**
- Modify: `router-ts/src/compiler/types.ts`
- Modify: `router-ts/src/config/base.ts`
- Modify: `router-ts/src/compiler/compileRoute.ts`
- Create: `router-ts/src/adapters/aerodromeV2.ts`
- Modify: `router-ts/src/artifacts/schema.ts`
- Modify: `router-ts/src/artifacts/routeEncoding.ts`
- Modify: `router-ts/src/artifacts/writeArtifacts.ts`
- Test: `router-ts/test/artifact-schema.spec.ts`
- Add test as needed: `router-ts/test/aerodrome-v2-adapter.spec.ts`

**Approach:**
- Add `AerodromeV2: 7` to the TypeScript `VenueFamily` map.
- Add an `AerodromeV2PoolConfig` type with `venue: "aerodrome-v2"`, `router`, `factory`, `pool`, `token0`, `token1`, `stable`, and fee evidence fields.
- Parse `aerodrome-v2` fixture pools distinctly from `solidly`.
- Encode Aerodrome V2 payloads with `(Route[] routes, uint256 deadline)` where each route has four fields.
- Ensure Solidly encoder remains three-field only.
- Expose Aerodrome V2 in artifact schema/debug output so generated routes, parity vectors, and gap matrices do not infer support from `solidly`.

**Test scenarios:**
- Happy path: Aerodrome V2 encoder produces the expected four-field ABI payload.
- Regression: Solidly encoder still produces a three-field payload.
- Error path: Aerodrome V2 pool fixture without a factory fails config parsing.
- Error path: `solidly` fixture with an unexpected factory does not silently become Aerodrome V2.
- Parity: route encoding and schema artifacts record venue ordinal `7` for Aerodrome V2 legs.

**Verification:**
- `bun x vitest router-ts/test/artifact-schema.spec.ts router-ts/test/aerodrome-v2-adapter.spec.ts`
- Existing router artifact generation command used by the repo after TypeScript changes.

- [x] **Unit 3: Fixture Pool, Route Artifacts, And Manifest Promotion**

**Goal:** Add launchable fixture evidence for at least one FAME route containing the Aerodrome V2 USDC/WETH hop and promote the Aerodrome V2 router target through generated manifests.

**Requirements:** R7-R9, R13, R16-R17

**Dependencies:** Units 1-2

**Files:**
- Modify: `test/router/fixtures/base-v1-pools.json`
- Modify: `test/router/fixtures/base-v1-routes.json`
- Regenerate: `test/router/fixtures/base-v1-solver-routes.json`
- Regenerate: `test/router/fixtures/base-v1-route-parity-vectors.json`
- Regenerate: `test/router/fixtures/base-v1-route-gap-matrix.json`
- Modify/regenerate: `test/router/fixtures/FameRouterFixtureManifest.sol`
- Modify/regenerate as needed: `test/router/fixtures/FameRouterSolverFixtureManifest.sol`
- Test: `test/router/FameRouterFixtureCoverage.t.sol`
- Test: `test/router/FameRouterGeneratedArtifacts.t.sol`

**Approach:**
- Add the target pool as `venue: "aerodrome-v2"` with verified factory, router, pool, token order, `stable: false`, and fee evidence.
- Choose the smallest deterministic executable route that includes the Aerodrome V2 USDC/WETH hop and reaches a FAME-facing asset using already-supported liquidity.
- Regenerate deterministic route artifacts and Solidity manifests from the fixture source of truth.
- Add `AerodromeV2` router target evidence to `FameRouterFixtureManifest` only once the fixture route is launchable.
- Keep any migrated Slipstream pool blocked or out of launchable fixture evidence.

**Test scenarios:**
- Manifest count parity includes the added Aerodrome V2 fixture pool and route.
- Required target list includes `(AerodromeV2, 0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43)` after launch promotion.
- Generated route parity vectors decode Aerodrome V2 legs as venue `7` with four-field payloads.
- Gap matrix distinguishes Aerodrome V2 support from Solidly and migrated Slipstream blockers.
- Existing NativeWrap, Solidly, UniswapV2, Slipstream, Slipstream2, V3, and V4 route artifacts remain decodable.

**Verification:**
- Artifact generation command used by the repo.
- `forge test --match-path test/router/FameRouterFixtureCoverage.t.sol`
- `forge test --match-path test/router/FameRouterGeneratedArtifacts.t.sol`

- [x] **Unit 4: Pinned Base Fork And Launch Validation**

**Goal:** Prove the Aerodrome V2 pool metadata and route execution on the pinned Base fork, including factory-derived identity and fail-closed negative cases.

**Requirements:** R7-R12, R17

**Dependencies:** Units 1-3

**Files:**
- Modify: `test/router/FameRouterForkBase.t.sol`
- Modify: `script/ValidateFameRouterBase.s.sol`
- Add interfaces as needed under: `src/router/interfaces/`
- Test: `test/router/FameRouterForkBase.t.sol`
- Test: `test/router/FameRouterDeploymentValidation.t.sol`

**Approach:**
- Add Aerodrome V2 fixture execution alongside existing Solidly and Slipstream execution helpers.
- Add metadata validation that checks factory code, token ordering, stable flag, and factory-derived pool identity against `0xcdac0d6c6c59727a65f871236188350531885c43`.
- If the pair exposes `factory()`, assert it matches fixture factory; otherwise derive identity from the factory and document why pair-side factory validation is unavailable.
- Keep fee validation honest: read a live fee only if Aerodrome V2 exposes a stable API for this pool; otherwise assert the fixture marks the fee as static/offchain evidence.
- Add a negative fork case for a wrong nonzero factory, wrong stable flag, or wrong router target, depending on which gives the clearest fail-closed signal without relying on a brittle downstream revert selector.
- Extend deployment validation to check Aerodrome V2 family/target allowlist entries from the manifest.

**Test scenarios:**
- Happy path: pinned Base fork executes a route containing the Aerodrome V2 USDC/WETH hop through the intended router and factory.
- Metadata: derived pool identity equals `0xcdac0d6c6c59727a65f871236188350531885c43`.
- Metadata: token0/token1 and `stable: false` match fixture evidence.
- Metadata: factory code exists and factory evidence is not zero.
- Fee: live fee is validated if readable; otherwise static/offchain fee evidence is explicitly accepted by policy.
- Error path: wrong factory or wrong stable flag cannot be promoted as launchable evidence.
- Error path: enabled family but missing target fails deployment validation.

**Verification:**
- `forge test --match-path test/router/FameRouterForkBase.t.sol --fork-url base`
- `forge test --match-path test/router/FameRouterDeploymentValidation.t.sol`
- `forge script script/ValidateFameRouterBase.s.sol --rpc-url base`

- [x] **Unit 5: Docs, Public Config, Deployment, And App Handoff**

**Goal:** Make the new venue operationally clear and deployable, then hand `www` enough evidence to remove the app blocker in a separate app change.

**Requirements:** R3, R13-R17

**Dependencies:** Units 1-4

**Files:**
- Modify: `docs/router/fame-router-schema.md`
- Modify: `docs/router/fame-router-validation.md`
- Modify: `config/fame-public.env` after deployment address changes
- Update as needed: `docs/brainstorms/2026-05-15-aerodrome-v2-explicit-factory-route-support-requirements.md`
- Update as needed: `docs/ideation/2026-05-15-aerodrome-v2-migrated-slipstream-pool-support-ideation.md`

**Approach:**
- Document `AerodromeV2 = 7`, its ERC-20-only behavior, payload ABI, factory field, and target allowlist requirements.
- Document the app unblock gate: schema parity, fixture/fork execution, manifest target evidence, deployed router address, and `www` payload builder support.
- Add any public Aerodrome V2 router/factory constants only if they are needed beyond fixtures; secrets remain in Doppler.
- Deploy a new `FameRouter` binary only after launch validation is green.
- Update `BASE_FAME_ROUTER_ADDRESS` with the deployed address after validation.
- Create or update an app-repo todo after contract deployment, including the deployed address and exact app-side expectations. This is a handoff artifact, not part of this contract implementation plan's file set.

**Test scenarios:**
- Docs and schema table agree with Solidity/TypeScript ordinals.
- Validation docs describe Aerodrome V2 launch evidence and migrated Slipstream as separate gates.
- Deployment validation confirms the Aerodrome V2 target is enabled from manifest evidence on the deployed router.
- App handoff includes the deployed router address and does not instruct `www` to treat Aerodrome V2 as `solidly`.

**Verification:**
- `forge script script/ValidateFameRouterBase.s.sol --rpc-url base`
- Deployment transaction verification command used by the repo.
- Manual review of docs against generated artifacts and deployed address.

## Sequencing

1. Implement the Solidity schema, adapter, and unit tests first so the wire contract is fixed.
2. Update `router-ts` types and encoders to produce the same wire contract.
3. Add the Aerodrome V2 fixture pool/route and regenerate artifacts/manifests.
4. Prove metadata and route execution on the pinned Base fork; add negative factory/stable coverage.
5. Update docs/config, deploy the new router, validate the deployed allowlist, and create the `www` handoff todo with the deployed address.

## Risks And Mitigations

- **ABI drift:** Mitigate by basing the adapter interface on Aerodrome's primary `IRouter` source and fork-testing the exact Base router.
- **Wrong factory evidence:** Mitigate by deriving pool identity from verified factory metadata at the pinned Base block before manifest promotion.
- **Schema consumer mismatch:** Mitigate by requiring app-side schema parity before removing the blocker, even though Solidity keeps schema version `1`.
- **False launchability:** Mitigate by keeping `FameRouterFixtureManifest.isLaunchable()` as the deployment gate and adding Aerodrome V2 only after fork execution and metadata coverage are synchronized.
- **Scope creep into migrated Slipstream:** Mitigate by leaving migrated Slipstream blocked until its router/quoter/factory identity proof is planned separately.

## Completion Criteria

- Solidity, `router-ts`, docs, and generated artifacts agree on `AerodromeV2 = 7`.
- Existing Solidly three-field route behavior is unchanged and covered.
- Aerodrome V2 payloads encode four-field routes with explicit factories.
- The target Base Aerodrome V2 USDC/WETH pool has verified fixture metadata and factory-derived pool identity.
- Pinned Base fork tests execute at least one route containing the Aerodrome V2 USDC/WETH hop through the intended router/factory.
- Deployment manifests include the Aerodrome V2 router target only after launch evidence is green.
- A new `FameRouter` is deployed and `BASE_FAME_ROUTER_ADDRESS` is updated.
- `www` receives a todo/handoff containing the deployed router address and app-side schema/payload changes required to remove the blocker.

## Confidence Check

Manual confidence review passed for planning scope. The main execution-time unknowns are the exact Aerodrome V2 factory address/method and fee-read API. They are intentionally isolated in Units 3-4 because they require pinned fork verification, not more product planning.

## Implementation Notes

- Deployed and verified Base router: `0xAdefa5860389E8936ebf2977e1Fb4a365aA39636`.
- Verified Aerodrome V2 factory evidence at pinned Base block `45_884_844`: router default factory `0x420DD381b31aEf6683db6B902084cB0FFECe40Da`, factory `getPool(USDC,WETH,false)` derives `0xcDAC0d6c6C59727a65F871236188350531885C43`, and factory `getFee(pool,false)` returns `30`.
- Full validation script attempts against the live RPC hit provider storage-read timeouts. Direct post-deploy checks passed for router code, fee recipient, fee ppm, owner, `AerodromeV2` family/target enablement, `NativeWrap` WETH target enablement, and Fame `getSkipNFT(router)`.
