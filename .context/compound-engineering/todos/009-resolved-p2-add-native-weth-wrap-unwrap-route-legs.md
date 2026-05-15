---
status: resolved
priority: p2
issue_id: "009"
tags: [router, native-eth, weth, route-solver]
dependencies: []
---

# Add Native ETH/WETH Wrap And Unwrap Route Legs

## Problem Statement

The FAME swap solver can find useful liquidity through WETH connector routes, but the current router schema cannot express pure native ETH to WETH wrapping or WETH to native ETH unwrapping as executable route legs. Until that is first-class, the app-side solver must keep native ETH routes restricted to native-compatible swap legs and must not quote implicit ETH/WETH conversion paths.

This limits internal route coverage for native ETH trades. For example, `ETH -> WETH -> FAME` and `FAME -> WETH -> ETH` could be valid and efficient if the router could execute explicit WETH `deposit()` and `withdraw()` steps, but they are not safe to quote today.

## Findings

- `FameRouterTypes.VenueFamily` currently includes only `Solidly`, `UniswapV2`, `Slipstream`, `Slipstream2`, `UniswapV3`, and `UniswapV4`.
- `FameRouter._dispatch` has no branch for WETH `deposit()` or `withdraw()`.
- Solidly, Uniswap V2, Slipstream, and Uniswap V3 adapters reject native ETH inputs or outputs.
- Uniswap V4 can handle native ETH through Universal Router V4 currency semantics, but that is a swap path, not a pure wrap/unwrap primitive.
- The app-side solver is intentionally keeping native ETH and WETH routes distinct until wrap/unwrap is represented explicitly and proven executable.

## Proposed Solutions

### Option 1: Add A Dedicated NativeWrap Venue Family

**Approach:** Add a new route venue for explicit `ETH -> WETH` and `WETH -> ETH` transitions. The router dispatch would call `IWETH9.deposit{value: amountIn}()` for wrapping and `IWETH9.withdraw(amountIn)` for unwrapping, with the configured WETH contract as the enabled target.

**Pros:**
- Keeps ETH/WETH conversion explicit and auditable.
- Lets the solver model wrap/unwrap as zero-price-impact pseudo-edges with gas-only ranking cost.
- Avoids broad generic external call support.
- Preserves current route accounting, minimum-output, and leftover-refund invariants.

**Cons:**
- Requires a schema/ABI update and regenerated TypeScript route encoding.
- Needs deployment/configuration work to enable the WETH target.

**Effort:** 4-8 hours including tests and artifact updates.

**Risk:** Medium.

---

### Option 2: Add Dedicated Pre/Post Route Wrap Fields

**Approach:** Keep DEX route legs unchanged and add explicit route-level flags or fields for wrapping native input before the first leg and unwrapping WETH final output after the last leg.

**Pros:**
- Makes endpoint-only wrapping simple.
- Reduces chance of arbitrary mid-route wrapping.

**Cons:**
- Does not naturally support WETH as a mid-route bridge in more complex native ETH paths.
- Adds special-case route accounting separate from ordinary legs.

**Effort:** 4-8 hours.

**Risk:** Medium.

## Recommended Action

Implemented Option 1: dedicated `NativeWrap` venue family with explicit `ETH -> WETH` and `WETH -> ETH` route legs.

## Technical Details

Affected files may include:
- `src/router/FameRouterTypes.sol`
- `src/FameRouter.sol`
- `src/router/interfaces/IWETH9.sol`
- `router-ts/src/compiler/types.ts`
- `router-ts/src/artifacts/routeEncoding.ts`
- `router-ts/src/artifacts/writeArtifacts.ts`
- `test/router/FameRouter.t.sol`
- `test/router/FameRouterForkBase.t.sol`
- `test/router/fixtures/FameRouterFixtureManifest.sol`

Implementation considerations:
- Define whether wrap/unwrap consumes `Exact`, `All`, and/or `BalanceBps` amounts.
- Require `ETH -> WETH` output to be exactly the wrapped amount, subject to normal leg minimum checks.
- Require `WETH -> ETH` output to be exactly the unwrapped amount, subject to normal leg minimum checks.
- Ensure `msg.value` rules remain strict: native input routes must still provide exactly `route.amountIn`, and ERC20 input routes must not send unexpected native value.
- Keep public same-asset `ETH <-> WETH` swaps unsupported unless product scope changes; the primary target is internal route search for FAME-facing swaps.
- Update app-side solver only after contract tests prove the new venue on local and fork coverage.

## Resources

- App-side solver audit: `../www/docs/ideation/2026-05-14-fame-swap-quoter-solver-audit-ideation.md`
- Current app-side native/WETH restriction: `../www/src/features/fame-swap/solver/graph/candidates.ts`
- Current router implementation: `src/FameRouter.sol`
- WETH interface already present: `src/router/interfaces/IWETH9.sol`

## Acceptance Criteria

- [x] Router schema includes an explicit wrap/unwrap capability or venue; no generic arbitrary external call is introduced for this feature.
- [x] `ETH -> WETH` route leg executes WETH `deposit()` and accounts for produced WETH with normal per-leg minimum checks.
- [x] `WETH -> ETH` route leg executes WETH `withdraw()` and accounts for produced native ETH with normal per-leg minimum checks.
- [x] Venue/target allowlisting prevents arbitrary token targets from being used as wrap/unwrap contracts.
- [x] Unit tests cover native input wrapping, ERC20 input unwrapping, bad target rejection, bad direction rejection, `msg.value` mismatch, and leftover refunds.
- [x] Fork or integration tests prove `ETH -> WETH -> FAME` and `FAME -> WETH -> ETH` style routes once app-side route artifacts are available.
- [x] Router TypeScript encoding, manifests, and generated artifacts are updated for the new venue.
- [x] The app-side solver keeps current native ETH/WETH restrictions until this todo is implemented and proven.

## Work Log

### 2026-05-14 - Initial Discovery

**By:** Codex

**Actions:**
- Audited current app-side solver behavior around native ETH and WETH route filtering.
- Inspected `FameRouter.sol`, route types, ABI, and adapters.
- Confirmed the router supports native ETH through route `msg.value` and Uniswap V4 native currency swaps, but not pure WETH `deposit()` or `withdraw()` route legs.
- Captured the contract-side feature request and the current app-side decision to keep native ETH/WETH restrictions in place.

**Learnings:**
- The existing native ETH/WETH separation protects against quoting implicit wrap/unwrap routes that the router cannot currently execute.
- A dedicated wrap/unwrap venue is the cleanest way to make ETH/WETH conversion available to the solver without relaxing router safety boundaries.

### 2026-05-14 - Implemented

**By:** Codex

**Actions:**
- Added `FameRouterTypes.VenueFamily.NativeWrap` as schema v1 ordinal `6`.
- Added router validation for empty payloads, zero encoded `minAmountOut`, valid WETH/native directions, enabled NativeWrap targets, and all-wrap route rejection.
- Added WETH `deposit()` / `withdraw()` dispatch with no approval path and computed-spend effective minimum checks.
- Added Solidity unit tests for wrap, unwrap, `BalanceBps`, `All`, bad shape, disabled target, approval bypass, and route-local accounting.
- Updated `router-ts` encoding, capabilities, generated artifacts, parity vectors, solver manifest, and gap matrix with minimal NativeWrap proof routes.
- Updated router schema and validation docs with NativeWrap semantics and the production allowlist promotion gate.

**Verification:**
- `bun run router:verify`
- `forge test --match-path test/router/FameRouter.t.sol`
- `forge test --match-path test/router/FameRouterGeneratedArtifacts.t.sol`
- `forge test --match-path 'test/router/*.t.sol' --no-match-test test_BaseForkLaunchGateRequiresPinnedBlockAndRpc`
- `forge build --sizes src/FameRouter.sol`

**Residual note:**
- The full router suite still requires `BASE_RPC` for `test_BaseForkLaunchGateRequiresPinnedBlockAndRpc`, which is expected for the launchable pinned-fork gate.
