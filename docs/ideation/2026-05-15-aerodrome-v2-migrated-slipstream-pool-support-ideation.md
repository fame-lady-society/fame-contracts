---
date: 2026-05-15
topic: aerodrome-v2-migrated-slipstream-pool-support
focus: .context/compound-engineering/todos/010-pending-p2-add-aerodrome-v2-and-migrated-slipstream-pools.md
status: brainstormed
handoff: brainstorm
---

# Ideation: Aerodrome V2 And Migrated Slipstream Pool Support

## Codebase Context

`fame-contracts` is a Foundry Solidity repo with a typed `FameRouter` executor and Bun/viem `router-ts` artifact compiler. The router executes offchain-selected routes through venue-specific adapters, checks route-local balance deltas, applies one final fee, and gates execution through owner-enabled venue families and venue targets. Production deploys are driven by launch manifests and pinned Base fork fixtures, not by app-side route discovery alone.

The current blocker is two-part:

- Aerodrome V2 USDC/WETH is a real reviewed pool, but its router expects Solidly-style routes with an explicit factory field. The current `SolidlyRouterAdapter` only supports the Scale/Equalizer three-field route shape `{ from, to, stable }`.
- The migrated Slipstream USDC/WETH tick-spacing 50 pool is a real pool from factory `0xf8f2eB4940CFE7d13603DDDD87f123820Fc061Ef`, but current Slipstream evidence is factory-sensitive. A same-pair/same-tick pool from a different factory must not be quoted or executed by accident.

Relevant current boundaries:

- `FameRouterTypes.VenueFamily` has `Solidly = 0`, `UniswapV2 = 1`, `Slipstream = 2`, `Slipstream2 = 3`, `UniswapV3 = 4`, `UniswapV4 = 5`, and `NativeWrap = 6`.
- `SolidlyRouterAdapter.Payload` decodes `ISolidlyRouter.Route[]` with three fields and calls `swapExactTokensForTokens` on the target.
- `SlipstreamAdapter.Payload` already includes `router`, `factory`, `tokenIn`, `tokenOut`, `tickSpacing`, `sqrtPriceLimitX96`, and `deadline`; it rejects paths where `payload.router != target` or `ISlipstreamRouter(target).factory() != payload.factory`.
- `router-ts` loads fixture pools from `test/router/fixtures/base-v1-pools.json`, emits generated route artifacts, and keeps Solidity parity/fork tests aligned with the pinned manifest.
- `../www` already has the Aerodrome V2 and migrated Slipstream pools in its reviewed universe, but marks them blocked until contract-side execution support is proven.

Prior learnings reinforce that public deployment constants belong in `config/fame-public.env`, secrets and RPCs stay in Doppler, and Foundry chain aliases should be used for Base validation. There are no dedicated `docs/solutions/` entries for this adapter gap; the strongest institutional knowledge is in the existing router schema docs, fixture manifests, fork tests, and May 10 multi-leg-router ideation.

## Ranked Ideas

### 1. Dedicated `AerodromeV2` Venue And Explicit-Factory Adapter

**Description:** Add a new `AerodromeV2` venue family after `NativeWrap`, with a narrow adapter/interface for Aerodrome V2's four-field route shape `{ from, to, stable, factory }`. Keep existing `Solidly` three-field Scale/Equalizer behavior unchanged. `router-ts` should encode Aerodrome V2 payloads only for pools whose fixture venue is explicitly Aerodrome V2.

**Rationale:** This directly addresses the known blocker without hidden payload polymorphism. The route ABI mismatch is real, and a dedicated venue makes schema docs, enum tests, deployment target allowlisting, generated artifacts, and app integration clearer. It also prevents a route builder from treating all Solidly-like venues as ABI-compatible.

**Downsides:** Adds one venue ordinal, one adapter, one interface, docs, tests, manifest targets, and regenerated artifacts. It is more explicit than reusing `Solidly`, but that explicitness is the point.

**Confidence:** 90%

**Complexity:** Medium

**Status:** Explored in `docs/brainstorms/2026-05-15-aerodrome-v2-explicit-factory-route-support-requirements.md`

### 2. Split The Work: Aerodrome V2 Now, Migrated Slipstream As A Separate Promotion Gate

**Description:** Treat todo `010` as two deliverables. First implement Aerodrome V2 explicit-factory route execution because the gap is well-defined and the pool is not described as migrating. Then evaluate the migrated Slipstream pool independently: either promote it with factory/router/quoter/fork evidence or keep it blocked with a crisp reason.

**Rationale:** Aerodrome V2 should not wait on the more ambiguous migrated Slipstream path. The migrated Slipstream pool may be executable with the existing adapter if its router ABI and `factory()` behavior match expectations, but it needs separate evidence that the route targets the migrated factory pool rather than a canonical same-pair pool.

**Downsides:** Leaves some `www` blocked liquidity in place after the first implementation slice. Requires disciplined follow-up so the migrated pool does not become vague backlog.

**Confidence:** 86%

**Complexity:** Low

**Status:** Unexplored

### 3. Factory-Aware Fixture And Payload Compatibility Gate

**Description:** Add tests and artifact checks that decode generated leg payloads and assert the expected ABI shape per pool venue. Aerodrome V2 fixtures must decode as four-field factory routes; Scale/Equalizer fixtures must decode as three-field Solidly routes; Slipstream fixtures must include the expected factory and tick spacing.

**Rationale:** This catches the exact class of failure before fork execution: a route artifact can be syntactically valid but compiled for the wrong router ABI. The repo already treats generated artifacts and parity vectors as launch gates, so payload-shape assertions belong in that safety layer.

**Downsides:** Adds more test surface around generated data. If overdone, it can duplicate fork coverage rather than complement it.

**Confidence:** 84%

**Complexity:** Medium

**Status:** Unexplored

### 4. Factory-Keyed Migrated Slipstream Identity

**Description:** Represent migrated Slipstream pools by `(factory, router, token0, token1, tickSpacing, pool)` rather than by token pair and tick spacing alone. Add a negative or diagnostic path proving a canonical-factory same-pair/tick route cannot satisfy migrated-pool evidence.

**Rationale:** The highest-risk migrated Slipstream failure is not a missing function selector; it is accidentally treating a same-pair pool from the wrong factory as equivalent. The current adapter already validates `target.factory() == payload.factory`, so the idea is to make the artifact and fork evidence just as factory-keyed as the adapter.

**Downsides:** Requires careful fixture data and likely live/pinned fork checks. It may still leave the migrated pool blocked if the available quoter/router tuple cannot prove the intended pool.

**Confidence:** 80%

**Complexity:** Medium

**Status:** Unexplored

### 5. Contract-To-`www` Enablement Receipt

**Description:** Emit a compact artifact for app integration that lists newly executable pool ids, venue family, router target, factory proof when relevant, route execution coverage, snapshot hash, and any remaining blocker reason. `www` can consume this to remove blocked enablement reasons only when contract evidence exists.

**Rationale:** The app already has a broader solver and reviewed pool universe. The contract repo should not become a second solver, but it can produce a small proof artifact that tells `www` which reviewed pools are now executable through FameRouter.

**Downsides:** This is integration infrastructure, not the core adapter fix. It should stay compact and generated from existing artifacts rather than becoming another manually edited source of truth.

**Confidence:** 76%

**Complexity:** Medium

**Status:** Unexplored

### 6. Pool Promotion Diff Ledger

**Description:** Generate a deterministic fixture diff ledger whenever pool fixtures are changed, focused on semantic fields: venue, router, factory, pool, token ordering, stable flag, tick spacing, fee, route coverage ids, and launch-blocking status.

**Rationale:** Aerodrome migrations and factory changes create noisy JSON/hash diffs. A semantic ledger would make future reviews faster and reduce the chance that a wrong factory or gauge address slips through because reviewers are staring at regenerated hashes.

**Downsides:** It is tooling around the change rather than the change itself. It should follow the first adapter implementation if time is tight.

**Confidence:** 68%

**Complexity:** Medium

**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Reuse `Solidly` with a payload-version byte | Hidden polymorphism makes route review harder than a dedicated Aerodrome V2 venue and still needs a new function selector. |
| 2 | Add `requiresExplicitFactory` flag only | Data flag alone does not solve the Solidity adapter/interface split. |
| 3 | Collapse `Slipstream2` into one factory-keyed Slipstream venue | Interesting long-term cleanup, but too much schema churn for this todo. |
| 4 | Store expected factory identities in onchain router config | More storage/config surface than needed; payload and fixture validation already cover the immediate risk. |
| 5 | Omit factory from calldata and infer from target | Saves calldata but weakens route self-description and would require new onchain config semantics. |
| 6 | Execution-only migrated Slipstream proof without app parity | Too easy for `www` and contract evidence to drift; useful only as a narrow diagnostic. |
| 7 | One-command pool promotion workflow | Valuable but too broad for this first Aerodrome V2 adapter slice. |
| 8 | Operator-facing failure-label taxonomy | Helpful UX, but lower leverage than preventing wrong payload/factory artifacts. |
| 9 | Include blocked pools as full contract artifacts | Duplicates `www` reviewed-pool state unless kept to a compact enablement receipt. |
| 10 | Componentized snapshot hashes | Useful for review ergonomics, but not needed to prove these two pools. |
| 11 | Factory-aware route fixtures for every venue | Overgeneralizes; Uniswap V3/V4 and NativeWrap do not need the same factory model. |
| 12 | Add migrated Slipstream before Aerodrome V2 | The migrated path has more uncertainty and should not block the clearer explicit-factory route support. |
| 13 | Treat Aerodrome V2 as Uniswap V2-like | Not grounded; Aerodrome V2 uses Solidly-style route structs, not `address[] path`. |
| 14 | Add multi-hop Slipstream support now | Out of scope; the current blocker is a single migrated USDC/WETH pool and factory identity. |

## Session Log

- 2026-05-15: Initial ideation -- 40 raw ideas generated across four frames, deduped into 20 candidate directions, 6 survived filtering.
- 2026-05-15: Selected idea 1 for brainstorming -- dedicated `AerodromeV2` venue and explicit-factory adapter.
