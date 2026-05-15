---
date: 2026-05-14
topic: native-weth-wrap-unwrap-route-legs
focus: .context/compound-engineering/todos/009-pending-p2-add-native-weth-wrap-unwrap-route-legs.md
status: brainstormed
handoff: brainstorm
---

# Ideation: Native ETH/WETH Wrap And Unwrap Route Legs

## Codebase Context

`fame-contracts` is a Foundry Solidity repo with a typed multi-leg `FameRouter` executor and a Bun/viem `router-ts` compiler that generates deterministic route artifacts, parity vectors, and gap-matrix evidence. The router already has the right safety shape for this feature: route-local asset snapshots, strict `msg.value` rules, per-leg minimum checks based on real balance deltas, final post-fee settlement, venue-family and target allowlists, structured Universal Router payloads, and no generic external-call route primitive.

The current gap is narrower than the broader router project. `FameRouterTypes.VenueFamily` has only `Solidly`, `UniswapV2`, `Slipstream`, `Slipstream2`, `UniswapV3`, and `UniswapV4`; `_dispatch` has no branch for `IWETH9.deposit()` or `IWETH9.withdraw()`. Solidly, Uniswap V2, Slipstream, and Uniswap V3 adapters intentionally reject native ETH inputs or outputs. Uniswap V4 can execute native ETH swaps, but that does not expose pure `ETH -> WETH` or `WETH -> ETH` transitions as first-class route legs.

`router-ts` keeps native ETH (`address(0)`) and Base WETH (`0x4200000000000000000000000000000000000006`) distinct, and the tests assert that distinction. The generated solver artifacts already cover native V4 routes and WETH routes separately, but cannot express a route such as `ETH -> WETH -> FAME` or `FAME -> WETH -> ETH` unless wrapping becomes an executable schema concept.

Relevant institutional learning was limited. The only matching `docs/solutions/` entry reinforces repository practice: public deployment constants belong in `config/fame-public.env`, secrets and RPCs stay in Doppler, and Foundry chain aliases should be preferred in docs and commands. The expected `docs/solutions/patterns/critical-patterns.md` file was not present.

The adjacent pending Aerodrome V2 / migrated Slipstream todo is also WETH-heavy, but it is a venue route-shape problem. Native WETH wrapping has bigger immediate leverage because it can unlock native access to every already-supported WETH connector route without relaxing the typed adapter model.

## Ranked Ideas

### 1. Dedicated `NativeWrap` Venue With Exact Delta Invariants

**Description:** Add a typed `NativeWrap` venue family whose only valid targets are allowlisted WETH contracts. A leg with `tokenIn == NATIVE_ETH` and `tokenOut == target` calls `IWETH9.deposit{value: amountIn}()`. A leg with `tokenIn == target` and `tokenOut == NATIVE_ETH` calls `IWETH9.withdraw(amountIn)`. Reject all other directions, reject non-empty payload data, skip ERC-20 approval setup for this venue, and require the produced route-local output delta to equal the spent amount.

**Rationale:** This directly matches the router's existing typed-adapter safety model. It keeps ETH/WETH conversion explicit, auditable, allowlisted, balance-checked, and usable with `Exact`, `BalanceBps`, and `All` amount modes. The exact-delta check is stronger than ordinary `minAmountOut` for a no-slippage primitive and catches misconfigured or malicious WETH targets even if allowlisting is wrong.

**Downsides:** Requires Solidity schema, dispatch, tests, TypeScript enum/artifact, manifest, and deployment updates. The implementation must avoid accidentally charging a user-facing fee for pure single-leg wrapping unless that product scope is explicitly accepted.

**Confidence:** 91%

**Complexity:** Medium

**Status:** Explored in `docs/brainstorms/2026-05-14-native-weth-wrap-unwrap-route-legs-requirements.md`

### 2. Make The Schema-Freeze Decision Explicit Before Adding An Ordinal

**Description:** Decide whether adding `NativeWrap` appends a venue ordinal under schema version `1` or bumps the route schema to version `2`. Then update Solidity enum ordinal tests, `router-ts` `VenueFamily`, artifact parity vectors, schema docs, and any app-side route builders consistently.

**Rationale:** The repo already treats schema wire values as a contract with `www`; tests currently assert that the next venue ordinal cannot be decoded. Adding a new enum member changes that semantic boundary. The project should either document that schema `1` is still pre-launch and extensible, or bump the schema so old artifacts cannot silently mean something new.

**Downsides:** A schema bump may create artifact churn if v1 is not externally deployed yet. Keeping schema `1` requires very clear docs and test updates so future work does not treat enum expansion casually.

**Confidence:** 86%

**Complexity:** Low

**Status:** Explored in `docs/brainstorms/2026-05-14-native-weth-wrap-unwrap-route-legs-requirements.md`

### 3. Model WETH Wrapping As A Route Primitive In `router-ts`, Not A Fake Pool

**Description:** Add a native wrap encoder/config path in `router-ts` that emits a `NativeWrap` leg with target WETH and empty data. Track a capability such as `nativeWrap` in route artifacts and the gap matrix. Keep the primitive separate from AMM pool metadata so pool validation does not pretend WETH deposit/withdraw is liquidity.

**Rationale:** The current compiler is pool-centric, but WETH wrapping is a deterministic connector edge, not a pool. Treating it as a primitive keeps fixture meaning clean, lets solver artifacts say exactly why native routes are executable, and prevents fake pool entries from polluting launch metadata checks.

**Downsides:** This cuts across compiler types, artifact schemas, tests, and possibly manifest generation. It is more deliberate than dropping a pseudo-pool into `base-v1-pools.json`.

**Confidence:** 84%

**Complexity:** Medium

**Status:** Explored in `docs/brainstorms/2026-05-14-native-weth-wrap-unwrap-route-legs-requirements.md`

### 4. Add Contract And Solver Gates For Pure `ETH <-> WETH` Conversion

**Description:** Keep single-leg public `ETH -> WETH` and `WETH -> ETH` conversion routes unsupported unless product scope changes. Prefer a contract-level guard against routes whose only leg is `NativeWrap`, and keep the app-side solver gating in place until contract unit tests, artifact parity, and pinned fork evidence pass.

**Rationale:** The feature is meant to unlock internal route coverage for FAME-facing swaps, not to turn `FameRouter` into a fee-taking wrapper UI. A small guard prevents accidental product drift and keeps current app restrictions truthful until the route primitive is proven end to end.

**Downsides:** It is a special-case validation rule in an otherwise generic route executor. If the product later wants public wrapping, the guard must be intentionally removed or parameterized.

**Confidence:** 76%

**Complexity:** Low

**Status:** Unexplored

### 5. Promote Base WETH Target Configuration Into The Launch Manifest

**Description:** Add the canonical Base WETH address as a public deployment/config constant where needed, include the `NativeWrap` WETH target in generated manifest requirements, and make deployment and live validation enable and verify that target alongside the existing venue families.

**Rationale:** The route artifacts are useless if the deployed router forgets to enable the WETH target. This repo already has a manifest-driven launch gate and a documented public-config/Doppler split, so WETH target enablement should become part of that same machine-checkable path.

**Downsides:** This is operational rather than novel. It adds one more fixture/manifest value to keep in sync across Solidity, TypeScript, deployment, and validation.

**Confidence:** 82%

**Complexity:** Low

**Status:** Unexplored

### 6. Prove The Two High-Value Native/WETH Route Shapes As Generated Fork Evidence

**Description:** After the primitive exists, generate and execute pinned Base fork artifacts for at least `ETH -> WETH -> FAME` and `FAME -> WETH -> ETH`, with route-hash parity, manifest target allowlisting, and gap-matrix rows that distinguish native V4 evidence from WETH-connector evidence.

**Rationale:** The app-side solver should not lift native/WETH restrictions based on unit tests alone. Fork evidence proves the route primitive composes with real WETH liquidity, existing fee accounting, route-local leftovers, and final native ETH settlement.

**Downsides:** Requires deterministic fork amounts and current route artifacts from `router-ts`. It may depend on external Base RPC access through Doppler for the full proof.

**Confidence:** 80%

**Complexity:** Medium

**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Route-level pre/post wrap fields only | Endpoint-only wrapping misses mid-route WETH connector paths and creates separate accounting outside ordinary legs. |
| 2 | Generic external-call adapter with selector allowlist | Too broad for the safety model; this feature needs only WETH deposit/withdraw, not a new arbitrary-call surface. |
| 3 | Use Universal Router `WRAP_ETH` / `UNWRAP_WETH` commands | Adds an unnecessary external dependency and reopens Universal Router command-surface concerns already avoided by structured adapters. |
| 4 | Ask users or the app to wrap before routing | Does not solve native ETH route UX or let the solver rank native routes through WETH connectors. |
| 5 | Treat ETH and WETH as the same graph asset | Contradicts existing tests and hides an execution step that must be explicit for safety. |
| 6 | Rely on native Uniswap V4 routes instead | Already supported for V4 native pools, but it cannot access existing WETH-only liquidity. |
| 7 | Add separate `executeRouteWithWrap` / `executeRouteAndUnwrap` functions | Expands the public API and still handles only endpoint wrapping rather than composable route legs. |
| 8 | Add WETH wrapping as a fake pool fixture | Duplicates the stronger route-primitive idea and would confuse pool metadata validation. |
| 9 | Support only `Exact` amount mode for wrap/unwrap | Lower leverage; `All` and `BalanceBps` are natural for split routes and can stay safe with exact-delta checks. |
| 10 | Permit public single-leg wrapping and rely on the UI to hide it | Weak product boundary; users could pay router fees for a pure conversion the todo explicitly treats as out of scope. |
| 11 | Deploy a separate WETH adapter contract | Extra deployment and trust surface without clear value over an internal typed library. |
| 12 | Defer until Aerodrome V2 support lands | The wrap primitive unlocks native access to current WETH routes and will also compose with future Aerodrome support. |

## Recommended Brainstorm Seed

Brainstorm ideas 1, 2, and 3 together:

> Define the exact `NativeWrap` route-leg schema and rollout boundary: a typed WETH primitive with no payload, strict direction validation, approval-free dispatch, exact 1:1 route-local output checks, and a deliberate schema-version decision. Then map how `router-ts` should represent it as a primitive edge rather than as fake liquidity.

## Session Log

- 2026-05-14: Initial focused ideation — 28 candidates generated, 6 survived. Key finding: the implementation should be a typed WETH primitive that composes with existing route-local accounting, but the schema-version and artifact-model decisions need to be made before coding.
- 2026-05-14: Brainstormed ideas 1, 2, and 3 into `docs/brainstorms/2026-05-14-native-weth-wrap-unwrap-route-legs-requirements.md`. Decisions: NativeWrap is an internal route leg only, schema v1 is extended rather than bumped, and wrap/unwrap output requirements derive from computed spend while route builders encode `minAmountOut = 0`.
