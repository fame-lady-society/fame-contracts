---
date: 2026-05-12
topic: fame-route-solver-fork-matrix
source: docs/ideation/2026-05-10-fame-multi-leg-router-ideation.md
status: requirements
---

# FAME Route Solver And Fork Matrix Requirements

## Problem Frame

The FAME router now has typed production adapters, route-local custody accounting, final-output fee settlement, a launchable pinned Base fixture manifest, and fork coverage for 19 directional route fixtures. That evidence proves the venue adapters and current fixture inventory, but it does not yet prove that an offchain route builder can generate exact `FameRouterTypes.Route` payloads for user-facing FAME routes or that composed, split, and split-then-merge production routes execute on the pinned Base fork.

The next capability should be a small Bun/viem TypeScript reference implementation that turns a known supported pool config into deterministic router payload artifacts for FAME<->USDC/WETH/ETH. Its first job is correctness at the integration boundary: exact ABI route shape, route hash parity, native ETH/WETH handling, typed adapter payloads, and fork-executable evidence. It should not try to become a dynamic best-price engine in this phase.

Current verified context:

- `test/router/fixtures/base-v1-pools.json` contains 19 pinned Base pool fixtures.
- `test/router/fixtures/base-v1-routes.json` contains 19 pinned directional route fixtures.
- `test/router/fixtures/FameRouterFixtureManifest.sol` marks 19 pool metadata fixtures and 19 route execution fixtures as launchable at Base block `45884844`.
- `test/router/FameRouterForkBase.t.sol` executes the current fixtures by rebuilding route structs and venue payloads in Solidity helpers.
- `package.json` includes `typescript`, `ts-node`, and `viem`, but does not yet provide a focused Bun-based route solver/test harness.
- `../fleet` contains useful Bun/viem V3/V4 quote and Universal Router references, but the solver here should only mine the relevant swap knowledge rather than porting fleet infrastructure wholesale.

The intended evidence flow:

```text
Known pool config + FAME route request
  -> Bun/viem route compiler
  -> exact route artifact + debug artifact + gap matrix entry
  -> TypeScript ABI/hash parity checks
  -> pinned Base Foundry fork execution
```

## Requirements

**Reference Route Compiler**

- R1. The reference implementation must compile routes from an explicit supported pool config, not from open-ended pool discovery.
- R2. The first supported user-facing directions must cover FAME<->USDC, FAME<->WETH, and FAME<->ETH where viable from the known Base fixture universe.
- R3. The compiler may use required intermediate assets from the supported config, including basedflick, ZORA, frxUSD, SCALE, msUSD, and msETH, but those intermediates are not independent product destinations for this phase.
- R4. The compiler must emit exact schema version `1` `FameRouterTypes.Route`-shaped artifacts, including route header fields, ordered legs, amount modes, venue family ordinals, targets, typed adapter payload bytes, `msg.value` or funding metadata, final post-fee minimums, route hash inputs, and the computed route hash.
- R5. Compiler output must be deterministic for a fixed config, amount, route request, and pinned block assumption.
- R6. The compiler must model native ETH as `address(0)` and WETH as the Base WETH ERC-20 address, with explicit funding/call-value behavior for native input routes.
- R7. The compiler must remain exact-input only for this phase.
- R8. The compiler must reject or mark unsupported any candidate route that cannot be represented by the router schema, enabled venue families, enabled venue targets, payload size limits, native asset policy, or supported V4 hook-data rules.

**Adapter And Encoding Coverage**

- R9. TypeScript route encoding must mirror the Solidity production venue families: Solidly, Uniswap V2, Slipstream, Slipstream2, Uniswap V3, and Uniswap V4.
- R10. Venue-specific TypeScript logic must hide protocol encoding details behind a small common route-building surface so the solver does not spread ABI quirks across graph code, fixture generation, and tests.
- R11. V3 and V4 encoding must be grounded in proven viem patterns from local references such as `../fleet`, while trimming out unrelated fleet behavior.
- R12. V4 route support must handle hook-address pool metadata, native ETH currency identity, and non-empty hook data when required by configured hooked pools. The prior schema version `1` restriction that rejected all non-empty hook data is void for this phase.
- R13. TypeScript ABI encoding and route hashing must be parity-tested against Solidity `abi.encode(route)` and `FameRouter.hashRoute(route)`, including enum ordinals, nested dynamic `Leg[]`, adapter `bytes data`, and native ETH.

**Tooling And TypeScript Standards**

- R14. The work must introduce a focused Bun-based TypeScript harness for route solving, fixture generation, parity checks, and fast tests.
- R15. TypeScript must be treated as production reference code: strict types, no ad hoc `any`-driven route objects, no stringly typed token identities where typed config can prevent mistakes, and no hidden runtime dependency on unstated environment variables.
- R16. Commands that require Base RPC must be separated from pure local tests and must use the repo's public-config plus Doppler convention. RPC URLs remain Doppler secrets.
- R17. The solver must produce human-reviewable debug artifacts for generated routes, including selected path, considered viable path candidates where useful, pool IDs, venue families, per-leg quote/minimums, final post-fee minimum, payload bytes, call value, test-only funding setup, and route hash.

**Production Fork Matrix**

- R18. The pinned Base fork suite must promote composed production routes to first-class fixtures rather than inferring confidence from single-leg fixtures.
- R19. The first composed route targets should include `FAME -> basedflick -> ZORA -> WETH` and, if viable at the pinned block, `FAME -> basedflick -> ZORA -> USDC`.
- R20. The fork matrix should include the reverse user-facing directions where viable, such as `USDC -> ZORA -> basedflick -> FAME`, and should explicitly mark infeasible directions instead of silently omitting them.
- R21. The fork matrix must include at least one real production split route and at least one real production split-then-merge route, using route-local balance modes where appropriate.
- R22. The fork matrix must include native ETH/WETH boundary coverage for FAME-facing routes, not only non-FAME ZORA/ETH smoke coverage.
- R23. Fork tests for generated routes must use TypeScript-generated artifacts as the source of truth. If Solidity helpers reconstruct any in-memory route structs for execution, they must prove byte/hash parity with the generated artifact so the fork test cannot silently diverge from the offchain payload.
- R24. Fork assertions must keep the existing custody bar: no route-local token or native ETH balances left in the router, final-output fee charged once, recipient receives net output, fee recipient receives the fee, and unsupported/malformed route artifacts fail closed.

**Coverage Reporting**

- R25. The work must produce a generated route gap matrix for the supported FAME<->USDC/WETH/ETH scope.
- R26. The gap matrix must distinguish supported, executable, TS-generated, fork-tested, intentionally unsupported, and blocked-by-liquidity/config routes.
- R27. The gap matrix must identify routes requiring native ETH, WETH, Permit2/Universal Router behavior, V4 hooks, split execution, or split-then-merge execution.
- R28. Existing manifest launchability must not be weakened. New fixture evidence may extend the manifest or live in a separate solver/fork evidence layer, but green tests must not come from counts alone.

## Success Criteria

- A Bun/viem reference command can generate exact router payload artifacts for the supported FAME<->USDC/WETH/ETH route set from known config.
- TypeScript route encoding and `FameRouter.hashRoute` agree for representative direct, composed, native ETH, V3/V4, split, and split-then-merge routes.
- Pinned Base fork tests execute TS-generated or parity-checked composed production routes, including a basedflick/ZORA path between FAME and WETH or USDC where viable.
- A hooked V4 route that requires non-empty hook data can be encoded by TypeScript and executed through the router on the pinned Base fork, or is explicitly blocked with evidence if the current pinned block/config cannot support it.
- At least one real split route and one real split-then-merge route execute on the pinned Base fork with a single final-output fee.
- Native ETH and WETH route identities are both covered and cannot be confused by the solver, fixture artifacts, or fork tests.
- A generated route gap matrix gives a reviewer a clear definition of what is covered, unsupported, or still blocked.
- Pure TypeScript tests run without Base RPC, while RPC-backed fork validation follows the repo's Doppler and Foundry alias conventions.

## Scope Boundaries

- No dynamic pool discovery in this phase.
- No price-first best-route engine in this phase.
- No exact-output routing.
- No frontend UI work.
- No backend signer, route authorization service, or production API surface.
- No wholesale migration of the contracts repo into a TypeScript monorepo.
- No full port of `../fleet`; only relevant viem V3/V4 quoting/encoding lessons should be reused.
- No weakening of existing router custody, fee, manifest, or launch-gate requirements.

## Key Decisions

- New focused requirements doc: This phase follows the completed contract-centered router requirements instead of modifying them in place.
- Exactness before intelligence: The solver should first prove it can produce executable router payloads and matching hashes, then later become smarter about route ranking.
- Known config first: The supported pool universe is a deliberate product and safety boundary for this phase.
- Fork execution as oracle: The reference implementation is not trustworthy until generated artifacts execute through `FameRouter` on the pinned Base fork.
- V4 hook data is in scope: Schema version `1` must support bounded, configured hook data for hooked V4 pools instead of rejecting all non-empty hook data.
- Bun as the preferred TypeScript surface: The repo's existing TypeScript tooling is incidental; a focused Bun harness is acceptable if it stays scoped to route solving and validation.
- Debug artifacts are part of the product: When composed routes fail, reviewers need to see path choice, amounts, payloads, and route hash without reconstructing the solver's reasoning from calldata.

## Dependencies / Assumptions

- The existing schema version `1` route shape in `src/router/FameRouterTypes.sol` remains the route ABI for this phase.
- The current production fixture universe starts from `test/router/fixtures/base-v1-pools.json` and `test/router/fixtures/base-v1-routes.json`.
- The pinned Base block remains `45884844` unless planning finds a specific route viability reason to revise it.
- V4 paths involving basedflick/ZORA require hook-address metadata and currently use explicit empty swap hook data. Non-empty V4 swap hook data remains in scope when a configured hook actually requires it, but basedflick/ZORA must not be forced into that role without hook-specific evidence.
- Some proposed composed or reverse routes may be economically poor or illiquid at the pinned block; the requirement is executable evidence or explicit unsupported/blocker classification, not best price.
- Public constants continue to live in `config/fame-public.env`; RPC URLs and other secrets remain in Doppler.

## Alternatives Considered

- Build a dynamic route finder first: Rejected because discovery and ranking would blur the immediate correctness target.
- Generate only new Solidity fixtures: Rejected as the primary approach because it would not prove the offchain integration boundary.
- Use TypeScript only for a gap report: Rejected as too weak; the route compiler must emit executable payload artifacts.
- Port fleet infrastructure wholesale: Rejected because this repo needs a small FAME-specific reference, not fleet coordination, account abstraction, or backend service behavior.
- Fold everything into the original router requirements: Rejected because the contract launch requirements are already a separate completed capability; this follow-on phase needs a cleaner planning target.

## Outstanding Questions

### Resolve Before Planning

- None.

### Deferred to Planning

- [Affects R2-R3, R18-R22][Needs research] Confirm which composed, reverse, split, and split-then-merge routes are executable at the pinned Base block and which require a revised pinned block or explicit unsupported classification.
- [Affects R4, R13, R23][Technical] Decide the exact artifact format that both TypeScript and Foundry will consume for parity and fork execution.
- [Affects R14-R16][Technical] Define the smallest Bun integration that meets TypeScript quality requirements without creating broad package churn.
- [Affects R17, R25-R27][Technical] Decide whether debug artifacts and the route gap matrix are checked in, generated on demand, or both.
- [Affects R23-R24][Technical] Decide how Foundry should execute TS-generated artifacts without duplicating route construction logic in Solidity helpers.
- [Affects R12, R19, R23][Technical] Apply `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md` so hook-address V4 coverage, empty swap hook data, and valid non-empty swap-hook-data proof are reported separately.

## Next Steps

-> `/ce:plan` for structured implementation planning.
