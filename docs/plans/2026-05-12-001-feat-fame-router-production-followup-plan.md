---
title: "feat: FAME Router Production Follow-Up"
type: feat
status: active
date: 2026-05-12
origin: docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md
review: .context/compound-engineering/ce-review/20260511-193547-router-review/synthesis.md
branch: feat/fame-multi-leg-router
---

# feat: FAME Router Production Follow-Up

## Overview

Turn the current FAME router scaffold into a production-capable Base route executor by resolving the accepted code review blockers: replace generic venue executor hooks with typed adapters, make the fixture/fork manifest an actual launch gate, harden route-local accounting, and make deployment validation prove the configured router matches the frozen `www` route universe.

This plan is a follow-up to `docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md`. The original plan remains the full feature source of truth. This document narrows the next work on `feat/fame-multi-leg-router` to the review-driven path from scaffold to launch candidate.

## Problem Frame

The router core already demonstrates the intended custody shape: exact-input route funding, route-local balance deltas, per-leg minimums, final post-fee settlement, fee governance, venue family and target allowlists, and placeholder fixture gates. The remaining risk is not the basic core shape; it is that the production boundary is still soft.

The current adapters call a generic `IRouterLegExecutor.executeLeg` hook, so a route that looks typed in the schema is not yet a route to a real Solidly, Uniswap V2, Slipstream, Universal Router V3, or Universal Router V4 venue. The current fixture manifest is also manually synchronized with placeholder JSON, so validation can become green without proving JSON parity, pool metadata, venue enablement, or route executability. These are accepted P1 blockers.

## Requirements Trace

- R1-R6, R34-R35: Preserve exact-input sequential execution and route-local custody while replacing scaffold adapter calls.
- R7-R12, R36-R38: Make every frozen v1 venue family and native ETH/WETH route shape executable on a pinned Base fork before launch.
- R13-R18: Ensure deployment configures the intended fee recipient, fee rate, owner, venue families, and venue targets.
- R19-R26, R39-R42: Harden route-local accounting, reject arbitrary external routing, constrain Universal Router/V4 semantics, and keep FAME DN404 skip-NFT behavior launch-blocking.
- R27-R33, R43-R47: Make fixture JSON, Solidity manifest, fork tests, live validation, docs, and `www` schema parity agree mechanically.

## Review Disposition Carried Forward

- Accepted: all P1 issues from the synthesis.
- Accepted: fail-closed `balanceOf` accounting, route-local accounting optimization, and deployment venue configuration checks.
- In scope with nuance: fee-on-transfer or malicious final-token under-delivery. Venue legs may account for transfer-tax behavior, but final settlement still needs either explicit fixture restrictions or delivered-output checks.
- Lower priority: native ETH leftover refund reverts for non-payable contract senders. Treat as an integration policy decision, not an early blocker.
- Needs clarification for `www`: schema wire values means enum ordinals, amount-mode ranges, rounding, and ignored fields as encoded by the Solidity ABI.
- Final cleanup: route identity events, unused WETH state, approval clearing policy, future enum fallback, and balance helper assembly.

## Scope Boundaries

- Do not add onchain route search, quoting, ranking, TWAP checks, exact-output routing, MEV protection, or fee conversion.
- Do not ship generic arbitrary calldata routing under a typed venue label.
- Do not mark the router launchable by editing manifest counts alone. Launchability must come from fixture content, pinned fork execution coverage, and live metadata validation.
- Do not move secrets into docs. Public constants belong in `config/fame-public.env`; RPC URLs, private keys, explorer keys, mnemonics, and upload keys stay in Doppler.
- Do not transfer ownership to the Base multisig until pinned fork tests, live validation, skip-NFT validation, and `www` schema parity all pass.

## Key Technical Decisions

| Decision | Rationale |
|---|---|
| Treat `IRouterLegExecutor` as test scaffolding unless explicitly promoted to a named Fame adapter contract. | The schema says `target` is a venue target, but the current code requires a custom hook. Keeping that ambiguity would let `www` build ABI-valid routes that revert or bypass intended venue constraints. |
| Make fixture JSON the source of truth, with generated or content-hash-checked Solidity constants. | Manual count synchronization can make validation pass while fixtures are empty or stale. |
| Fail closed on route asset balance reads. | Route-local accounting is the safety invariant; if the router cannot measure a route asset, execution should revert rather than silently treating the balance as zero. |
| Resolve final-token transfer semantics before broad venue rollout. | Either launch fixtures restrict final outputs to standard-transfer assets, or the router verifies delivered recipient deltas for final settlement. |
| Keep immediate approval clearing until a deliberate last-use optimization is tested. | The current policy is expensive but conservative; approval batching is final-cleanup work unless gas forces it earlier. |
| Require a nonzero pinned Base block for launchable fixtures. | A latest-head smoke test is useful during development but not a deterministic launch gate. |

## Implementation Units

- [x] **Unit 1: Schema Contract And Scaffold Boundary**

**Goal:** Make the contract/frontend route contract unambiguous before real adapters are wired in.

**Requirements:** R1-R6, R19-R22, R43-R47.

**Files:**
- Modify: `docs/router/fame-router-schema.md`
- Modify: `src/router/FameRouterTypes.sol`
- Modify: `src/router/interfaces/IRouterLegExecutor.sol`
- Modify: `test/router/mocks/MockRouter.sol`
- Modify: `test/router/FameRouter.t.sol`

**Approach:**
- Add canonical wire tables for `VenueFamily` and `AmountMode` integer ordinals.
- Document `BalanceBps` denominator, valid range, rounding direction, and `All` amount semantics.
- Define whether `target` means a real venue router or a Fame-owned adapter contract. For production v1, prefer real venue targets plus typed internal adapters unless bytecode pressure forces a separately deployed adapter design.
- Move `IRouterLegExecutor` language into test scaffolding if it remains only a mock boundary.
- Add a test or static assertion that schema constants match `FameRouterTypes`.

**Test scenarios:**
- Happy path: documented venue and amount-mode ordinals match Solidity enum values.
- Error path: `BalanceBps > 10_000` remains rejected.
- Error path: schema fixture with unknown venue ordinal is rejected or cannot be constructed.
- Integration: a JSON-like route fixture can be ABI-encoded with the documented wire values and consumed by the router tests.

**Verification:**
- A `www` implementer can build routes from `docs/router/fame-router-schema.md` without reading Solidity source to discover enum values or target semantics.

- [x] **Unit 2: Fail-Closed Accounting And Settlement Hardening**

**Goal:** Preserve route-local accounting under malformed tokens and final settlement edge cases.

**Requirements:** R19-R26, R39-R42.

**Files:**
- Modify: `src/FameRouter.sol`
- Modify: `src/router/FameRouterAccounting.sol`
- Modify: `test/router/FameRouter.t.sol`
- Create or modify: `test/router/mocks/MockERC20.sol`
- Create: `test/router/mocks/ReentrantToken.sol`

**Approach:**
- Make route asset `balanceOf` reads fail closed. If a route asset reverts, returns malformed data, or cannot be decoded, route execution reverts.
- Decide final-token transfer policy:
  - either restrict final output fixtures to standard-transfer tokens and document the restriction, or
  - measure delivered recipient deltas for final settlement and require delivered net output to satisfy `minAmountOutAfterFee`.
- Keep fee-on-transfer behavior in scope for venue legs where adapters can measure actual deltas.
- Add malicious and non-standard token tests before optimizing the balance helper with assembly.
- Treat native ETH leftover refund reverts as a policy item: document current behavior, and later decide between refund recipient, WETH wrapping, or route rejection for non-payable senders.

**Test scenarios:**
- Error path: token whose `balanceOf` reverts causes route execution to revert before success.
- Error path: token whose `balanceOf` returns short data causes route execution to revert.
- Error path: final output token that burns or taxes recipient transfer cannot satisfy `minAmountOutAfterFee` unless explicitly fixture-allowed and accounted for.
- Edge case: fee rounding on small outputs cannot underflow or overcharge.
- Error path: malicious or reentrant token callbacks are rejected by `nonReentrant` and leave no route-local balances after revert.
- Policy case: native ETH dust refund to a non-payable sender is documented and either tested as a revert or handled by the chosen refund policy.

**Verification:**
- Route-local accounting fails closed for every route asset and still passes existing standard-token custody tests.

- [x] **Unit 3: Manifest Source Of Truth And Pinned Fork Gate**

**Goal:** Make fixture content, Solidity manifest constants, and fork coverage agree mechanically.

**Requirements:** R7-R12, R27-R31, R36-R38, R43-R45.

**Files:**
- Modify: `test/router/fixtures/base-v1-pools.json`
- Modify: `test/router/fixtures/base-v1-routes.json`
- Modify: `test/router/fixtures/FameRouterFixtureManifest.sol`
- Modify: `test/router/FameRouterFixtureCoverage.t.sol`
- Modify: `test/router/FameRouterForkBase.t.sol`
- Modify: `docs/router/fame-router-validation.md`

**Approach:**
- Choose one pinned Base block for the frozen v1 fixture snapshot.
- Replace hardcoded pending counts with either generated Solidity constants or content-hash checks that make JSON drift visible.
- Require `FameRouterFixtureManifest.isLaunchable()` to include nonzero pool count, nonzero route count, zero pending launch blockers, and nonzero pinned Base block.
- Make missing `BASE_RPC` a launch-blocking failure for release validation while allowing explicit local skip behavior only outside launch checks.
- Add coverage tests that fail when a pool or route fixture is not represented in the execution/metadata coverage table.

**Test scenarios:**
- Happy path: fixture JSON hash matches the Solidity manifest hash.
- Error path: changing a fixture without regenerating or updating the manifest fails coverage.
- Error path: `isLaunchable()` is false when pinned Base block is zero.
- Error path: a route referencing an unknown pool fixture fails coverage.
- Error path: launch-blocking fixtures cannot pass with only latest-head fork smoke coverage.

**Verification:**
- A reviewer can prove from test output that fixture JSON, manifest constants, and fork coverage describe the same snapshot.

- [x] **Unit 4: Typed Base Venue Adapters**

**Goal:** Replace generic adapter shims with typed, constrained execution for the v1 venue families.

**Requirements:** R7-R12, R19-R22, R26, R35, R40-R42.

**Files:**
- Modify: `src/FameRouter.sol`
- Modify: `src/router/adapters/SolidlyRouterAdapter.sol`
- Modify: `src/router/adapters/UniswapV2Adapter.sol`
- Modify: `src/router/adapters/SlipstreamAdapter.sol`
- Modify: `src/router/adapters/UniversalRouterAdapter.sol`
- Modify: `src/router/interfaces/ISolidlyRouter.sol`
- Modify: `src/router/interfaces/IUniswapV2Router02.sol`
- Modify: `src/router/interfaces/ISlipstreamRouter.sol`
- Modify: `src/router/interfaces/IUniversalRouter.sol`
- Modify: `src/router/interfaces/IPermit2.sol`
- Modify: `src/router/interfaces/IWETH9.sol`
- Modify: `test/router/FameRouter.t.sol`
- Modify: `test/router/FameRouterForkBase.t.sol`

**Approach:**
- Solidly / Scale-Equalizer: decode route payloads into `Route[]` with `from`, `to`, `stable`, and factory identity where required; call the real router ABI with router custody as recipient.
- Uniswap V2: decode address path payloads and call the real router ABI with router custody as recipient.
- Slipstream / Slipstream 2: decode concentrated exact-input-single payloads with tick spacing and distinct router/factory metadata; do not conflate tick spacing with Uniswap V3 fee.
- Universal Router V3/V4: accept structured payloads and construct only the minimal commands internally. Reject raw command bytes, subplans, arbitrary transfers/sweeps, partial-fill allow-revert flags, unsupported position-manager commands, and external recipient/payer semantics.
- Make Uniswap V3 and Uniswap V4 explicit dispatch branches. Future unknown venue enum values must not fall through to Universal Router handling.

**Test scenarios:**
- Happy path: each v1 venue family has at least one executable fixture route on the pinned fork.
- Error path: wrong Solidly stable flag fails metadata validation or leg minimum without using ambient balance.
- Error path: Slipstream and Slipstream 2 router/config mismatches are rejected.
- Error path: Universal Router payload attempting external recipient, arbitrary sweep, subplan, or raw commands is rejected.
- Edge case: V4 PoolKey currency ordering, hooks, fee/tick spacing, and hook-data boundary are validated before execution.
- Integration: split and split-then-merge routes across venue families produce one final fee after merged output.

**Verification:**
- No production adapter path calls `IRouterLegExecutor.executeLeg`.

- [x] **Unit 5: Deployment And Live Validation**

**Goal:** Ensure a deployed router cannot pass validation unless it is configured for the frozen launch snapshot.

**Requirements:** R13-R18, R32-R33, R43-R47.

**Files:**
- Modify: `script/DeployFameRouter.s.sol`
- Modify: `script/ValidateFameRouterBase.s.sol`
- Modify: `docs/router/fame-router-validation.md`
- Modify: `docs/fame-release-plan.md`
- Modify as needed: `config/fame-public.env`

**Approach:**
- Deployment must initialize fee recipient, fee ppm, owner, native route policy, and the production venue family/target allowlist from public config or manifest-derived constants.
- Validation must check:
  - router chain ID and address,
  - fee recipient and fee ppm,
  - every fixture venue family/target enabled,
  - current Base pool metadata still matches the frozen fixture snapshot,
  - the fixture snapshot hash matches the populated pinned-fork manifest,
  - the pinned-fork matrix has launchable all-pool/all-route coverage,
  - deployed router has `Fame.getSkipNFT(router) == true`,
  - `www` schema version and fixture snapshot hash match the contract-side manifest.
- Docs must use `config/fame-public.env` for public constants and Doppler for secrets. Prefer Foundry aliases from `foundry.toml`, such as `--rpc-url base`, rather than raw RPC environment variables.

**Test scenarios:**
- Error path: validation fails when a fixture venue family is disabled.
- Error path: validation fails when a fixture target is not enabled.
- Error path: validation fails when `Fame.getSkipNFT(router) != true`.
- Error path: validation fails when fixture hash or `www` snapshot hash mismatches.
- Happy path: a fully configured local/fork deployment passes all non-secret validation checks.

**Verification:**
- Release docs and scripts cannot produce a green router launch check from fee config and manifest counts alone.

- [x] **Unit 6: Final Cleanup, Gas, And Auditability**

**Goal:** Clean up the codebase once the production adapter and validation shape is stable.

**Requirements:** R19-R26, R39-R47.

**Files:**
- Modify: `src/FameRouter.sol`
- Modify: `src/router/FameRouterAccounting.sol`
- Modify: `docs/router/fame-router-schema.md`
- Modify: `test/router/FameRouter.t.sol`
- Modify: `test/router/FameRouterForkBase.t.sol`

**Approach:**
- Add route identity to `RouteExecuted`, such as route hash plus schema version and input identity, or document why event-level route parity is intentionally omitted.
- Remove `weth` until wrap/unwrap support is implemented, or wire it into explicit native/WETH conversion paths with tests.
- Decide approval clearing policy. Keep immediate clearing if security/auditability wins; otherwise precompute last-use clearing or scoped batching and prove allowance lifecycle in tests.
- Optimize route-local accounting by assigning compact snapshot indexes for assets and per-leg token indexes, avoiding repeated linear scans.
- Replace the high-level `balanceOf` helper with memory-safe assembly only after fail-closed behavior and malformed-token tests are in place.
- Confirm bytecode size after typed adapters. If needed, split pure libraries before considering deployed adapter contracts.

**Test scenarios:**
- Happy path: event route identity can be recomputed from the submitted route.
- Error path: unknown or future venue family cannot silently dispatch to Universal Router.
- Happy path: optimized snapshot indexes preserve all ambient-balance isolation tests.
- Happy path: approval lifecycle tests prove no unexpected target keeps allowance after successful routes.
- Gas check: representative one-leg, multi-hop, and split routes have measured gas before and after optimization.

**Verification:**
- Final cleanup reduces audit noise without weakening custody, approval, or route-local accounting invariants.

## Sequencing

1. Unit 1: lock the route/schema contract and remove adapter ambiguity.
2. Unit 2: make accounting fail closed before optimizing it.
3. Unit 3: make fixtures and fork gates trustworthy.
4. Unit 4: implement typed adapters against the fixture universe.
5. Unit 5: wire deployment and live validation to the same fixture source of truth.
6. Unit 6: run final cleanup, gas, and auditability pass.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---:|---|
| Adapter bytecode grows too large | Medium | Split pure libraries first; only move to deployed adapters if custody invariants stay explicit. |
| Fixture snapshot drifts from `www` | High | Use content hashes and schema version parity in validation. |
| Universal Router command surface expands accidentally | High | Construct commands internally from structured payloads and reject all unsupported commands. |
| Transfer-tax final tokens under-deliver | Medium | Restrict fixture final outputs or measure delivered deltas at settlement. |
| Native ETH leftovers block contract senders | Low | Treat as route-builder policy or add explicit refund handling after launch blockers. |
| Secrets leak through docs or commands | High | Use `config/fame-public.env`, Doppler, and Foundry aliases from `foundry.toml`. |

## Success Metrics

- No production route path uses the generic `IRouterLegExecutor` scaffold.
- Every launch-blocking pool fixture has metadata validation.
- Every launch-blocking directional route fixture executes or simulates on the pinned Base fork.
- `FameRouterFixtureManifest.isLaunchable()` cannot return true with zero pinned block, empty fixture JSON, or mismatched fixture hash.
- Live validation fails when venue families or targets are not configured.
- Malformed `balanceOf` route assets fail closed.
- `www` can implement schema version `1` from docs without guessing enum ordinals or amount-mode semantics.
- Router tests, fork fixture tests, and validation docs all use public config plus Doppler secret handling without raw RPC URL examples.

## Sources & References

- Existing plan: `docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md`
- Review synthesis: `.context/compound-engineering/ce-review/20260511-193547-router-review/synthesis.md`
- Requirements: `docs/brainstorms/2026-05-11-fame-multi-leg-router-requirements.md`
- Schema docs: `docs/router/fame-router-schema.md`
- Validation docs: `docs/router/fame-router-validation.md`
- Workflow learning: `docs/solutions/workflow-issues/public-config-doppler-foundry-aliases-2026-05-12.md`
- Repo instructions: `AGENTS.md`
