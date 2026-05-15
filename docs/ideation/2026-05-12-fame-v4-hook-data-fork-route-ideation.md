---
date: 2026-05-12
topic: fame-v4-hook-data-fork-route
focus: .context/compound-engineering/todos/007-pending-p2-prove-non-empty-v4-hook-data-fork-route.md using ../fleet ZORA creator-coin swap references
status: brainstormed
handoff: brainstorm
---

# Ideation: FAME V4 Hook-Data Fork Route

## Codebase Context

`fame-contracts` now has a strict `router-ts` Bun/viem compiler that emits deterministic `FameRouterTypes.Route` artifacts, Solidity parity vectors, a solver fixture manifest, and a pinned Base fork matrix. `FameRouter` supports bounded non-empty V4 hook data through `setV4HookDataHashEnabled`, and unit tests prove allowed non-empty hook data is forwarded while unapproved data reverts.

The remaining todo is narrower: prove a real fork route whose V4 swap payload includes non-empty hook data. The current production basedflick/ZORA pool is hook-addressed but explicitly uses swap `hookData: "0x"`. A trial with arbitrary non-empty data reverted inside the Doppler hook at pinned block `45884844`, so a valid production fixture must be hook-specific rather than fabricated.

`../fleet` confirms this distinction. Its working ZORA creator-coin routes discover pool params from `getPoolKey()`, storage slots, or `CoinCreatedV4` logs, but they consistently set ordinary swap `hookData: "0x"` for ZORA/Doppler hops. Fleet's non-empty bytes appear in factory `postDeployHookData` self-snipe flows, encoding `{ buyRecipient, v3Route, v4Route, inputCurrency, inputAmount, minAmountOut }`; that is not Uniswap V4 `PathKey.hookData` for a normal Universal Router swap.

Relevant fleet references:

- `../fleet/packages/server/src/services/coinRoute.ts`: resolves ZORA coin ancestry and returns `hookData: "0x"` for `getPoolKey()` and storage-derived creator-coin pools.
- `../fleet/packages/server/src/services/poolDiscovery.ts`: reads `CoinCreatedV4` pool keys and storage fallback, also returning `hookData: "0x"`.
- `../fleet/packages/server/src/services/v4Quoter.ts`: uses `quoteExactInputSingle` with full `PoolKey` and defaults hook data to `0x`; falls back to single-hop quotes because Doppler hooks reject some multi-hop quoting.
- `../fleet/packages/server/src/services/v4SwapEncoder.ts` and `docs/uniswap-v4-swap-reference.md`: encode Universal Router `V4_SWAP` with `SWAP_EXACT_IN`, `SETTLE_ALL`, and `TAKE_ALL` over `PathKey[]`.
- `../fleet/packages/server/scripts/deploy-trend-content.ts` and related scripts: encode non-empty `postDeployHookData`, but for Zora factory deployment hooks, not ordinary swap hook data.

## Ranked Ideas

### 1. Reframe the Todo Around "Hook-Address Production" vs "Non-Empty Swap HookData"

**Description:** Update the todo acceptance criteria and docs so production ZORA/Doppler coverage is allowed to prove hook-address V4 swaps with explicit empty swap `hookData`, while non-empty swap `hookData` remains a separate evidence target that requires a known hook-specific payload.

**Rationale:** Fleet shows working ZORA creator-coin pairings like basedflick/ZORA are hook-address routes with `hookData: "0x"`. Treating non-empty swap bytes as mandatory for those pools creates a false target and encourages invalid arbitrary payloads.

**Downsides:** It partially walks back the original wording of todo 007. We should preserve the non-empty path as a future capability proof rather than erase it.

**Confidence:** 92%

**Complexity:** Low

**Status:** Explored in `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`

### 2. Add a Fleet-Style ZORA Creator-Coin Route Importer to `router-ts`

**Description:** Add a pure/fork-backed route discovery helper that reads `currency()`, `getPoolKey()`, and optionally factory logs for a configured set of ZORA creator coins. Emit a checked fixture catalog for basedflick/ZORA-like pools, including `currency0`, `currency1`, `fee`, `tickSpacing`, `hooks`, and explicit `hookData`.

**Rationale:** This uses the exact fleet discovery posture instead of hand-maintaining only one ZORA creator-coin pool. It would make future non-FAME ZORA creator pairings easy to compare and reduce mistakes around hook address, currency order, and native ETH identity.

**Downsides:** It expands `router-ts` from a compiler into a small discovery tool. The generated catalog should stay separate from launch-critical fixtures unless promoted deliberately.

**Confidence:** 84%

**Complexity:** Medium

**Status:** Explored in `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`

### 3. Add a V4 Multi-Hop Structured Payload Adapter Path

**Description:** Extend the router's Universal Router adapter schema with a second structured V4 payload for fleet-style `SWAP_EXACT_IN` over `PathKey[]`, while preserving the existing single-pool `SWAP_EXACT_IN_SINGLE` path. Generate a fork route such as ETH/ZORA -> ZORA/creator-coin or FAME-composed -> ZORA/creator-coin using the fleet encoding shape.

**Rationale:** Fleet's production swap encoder is multi-hop V4 `PathKey[]`, not this repo's current single-pool V4 action. Supporting both shapes would make the reference implementation closer to real ZORA route construction and future nested creator-coin paths.

**Downsides:** This is a schema/adapter expansion and needs careful validation so it does not become raw Universal Router command execution. It may still use empty `hookData`, so it does not alone satisfy the non-empty acceptance criterion.

**Confidence:** 78%

**Complexity:** High

**Status:** Unexplored

### 4. Build a HookData Candidate Probe Before Adding More Fixtures

**Description:** Add a diagnostic script that, for a pool key and amount, tests a small set of hook-data candidates through V4 Quoter `quoteExactInputSingle` and the Universal Router on a pinned fork, recording revert selectors and decoded errors without committing the candidate as a route fixture.

**Rationale:** The previous arbitrary `0x01` trial failed inside the Doppler hook. A probe turns that into repeatable evidence and prevents accidental promotion of invalid hook data into deterministic fixtures.

**Downsides:** It is investigative tooling, not production route coverage. It can waste time unless the candidate set is grounded in hook ABI/source knowledge.

**Confidence:** 75%

**Complexity:** Medium

**Status:** Unexplored

### 5. Mine Zora Factory `postDeployHookData` Separately From Swap HookData

**Description:** Add a short research artifact or script that decodes fleet-style factory `postDeployHookData` from known deployment scripts/transactions and explicitly maps which fields become self-snipe route instructions. Keep it out of `FameRouterTypes.Route` unless the router later needs deployment-hook support.

**Rationale:** This is where fleet actually uses non-empty bytes. Understanding it prevents conflating Zora factory hooks with V4 swap `PathKey.hookData`.

**Downsides:** It does not directly advance a FameRouter swap fixture. It is valuable mainly as a boundary-setting artifact.

**Confidence:** 82%

**Complexity:** Low

**Status:** Unexplored

### 6. Add a Dedicated Local Hook Harness for Non-Empty Swap HookData

**Description:** If production ZORA/Doppler swaps truly do not need non-empty `PathKey.hookData`, create a dedicated fork-local V4 hook/pool test that requires and validates non-empty swap hook data, then execute it through `FameRouter`.

**Rationale:** This would prove the router's end-to-end non-empty hook-data allowlist against real V4 control flow without misrepresenting current ZORA production routes.

**Downsides:** It is less production-representative than basedflick/ZORA. The setup cost may be high if a realistic V4 pool/hook harness is not already in the repo.

**Confidence:** 67%

**Complexity:** High

**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Force non-empty `hookData` into basedflick/ZORA fixture | Already tried with arbitrary bytes and the pinned fork reverted inside the Doppler hook; not grounded in valid hook behavior. |
| 2 | Use fleet `postDeployHookData` directly as V4 swap hook data | Different ABI and lifecycle; factory deployment hook data is not Universal Router `PathKey.hookData`. |
| 3 | Mark all hook-address V4 pools as requiring non-empty hook data | Fleet's working creator-coin swaps contradict this; hook-address pools commonly use `0x` swap hook data. |
| 4 | Search only for a magic byte payload | Too vague without hook ABI/source evidence and likely to produce more invalid fixtures. |
| 5 | Remove hook-data allowlist support | The router unit tests prove useful bounded support; the gap is production evidence, not schema capability. |
| 6 | Treat a mock-only non-empty test as satisfying todo 007 | Already covered in `FameRouter.t.sol`; todo asks for fork evidence. |
| 7 | Move this into frontend route ranking | The issue is fixture correctness and fork proof, not route scoring. |

## Recommended Brainstorm Seed

Brainstorm idea 1 combined with idea 2:

> Define a precise route-fixture policy for ZORA creator-coin V4 pools: production hook-address swaps may use explicit empty `hookData`, while non-empty swap `hookData` requires a proven hook-specific payload. Add a fleet-style creator-coin pool importer/catalog so basedflick/ZORA and similar pairings are validated from `getPoolKey()`/factory evidence before becoming solver fixtures.

## Session Log

- 2026-05-12: Initial focused ideation — 13 candidates generated, 6 survived. Key finding: fleet uses `hookData: "0x"` for ordinary ZORA creator-coin swaps; non-empty bytes in fleet are post-deploy hook data, not V4 swap hook data.
- 2026-05-12: Brainstormed ideas 1 and 2 into `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`, reframing todo 007 around truthful fixture policy plus a creator-coin pool catalog.
