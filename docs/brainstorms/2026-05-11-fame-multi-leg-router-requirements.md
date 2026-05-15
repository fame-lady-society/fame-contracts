---
date: 2026-05-11
topic: fame-multi-leg-router
source: docs/ideation/2026-05-10-fame-multi-leg-router-ideation.md
status: requirements
---

# FAME Multi-Leg Router Requirements

## Problem Frame

The FAME swap experience needs one Base execution surface for routes selected offchain by `www`. Today, the route universe spans multiple protocol families with separate routers, approval flows, and ETH/WETH handling. A user should be able to submit a validated route and either receive the expected post-fee output or have the transaction revert without stranded funds.

The contract should be a settlement and custody layer, not an onchain route finder. Its job is to pull route input, execute the submitted legs, enforce slippage and balance invariants, charge the FAME community fee exactly once, and return all route-produced assets to the intended recipients.

## Requirements

**Route Execution**

- R1. The router must execute exact-input routes selected offchain, including direct swaps, multi-hop swaps, split routes, and split-then-merge routes.
- R2. Each route must declare `tokenIn`, `tokenOut`, `amountIn`, `minAmountOutAfterFee`, `recipient`, `deadline`, and one or more typed legs.
- R3. Each leg must declare its consumed asset, produced asset, supported venue family, amount mode, leg slippage floor, and venue-specific route data.
- R4. Amount modes must support exact amounts, route-local balance basis points, and consuming all route-local available balance for a token.
- R5. Route execution must revert if the deadline has expired, a leg fails, a leg produces less than its declared minimum, the final post-fee output is below `minAmountOutAfterFee`, or any route token/leg continuity check fails.
- R6. The router must not perform route discovery, route ranking, quote quality checks, or best-price selection onchain.
- R34. V1 route input must be funded by `msg.sender`. The route `recipient` must never authorize token pulls, and delegated or signed third-party payer routes are out of scope for v1.
- R35. Every executable leg must direct produced assets back into router custody until final settlement. Fee transfers, net output transfers, and explicit leftover refunds are the only route output transfers to external recipients.

**Full-Venue V1 Launch Bar**

- R7. V1 is not launchable until contract-level Base fork validation passes for every production venue family in the frozen v1 FAME route universe: Scale/Equalizer V2, Uniswap V2, Aerodrome Slipstream, Aerodrome Slipstream 2 / Gauge Caps, Uniswap V3, and Uniswap V4.
- R8. Scale/Equalizer V2 support must handle Solidly-style `Route[]` paths with per-hop stable flags, including direct and multi-hop FAME routes.
- R9. Aerodrome Slipstream support must handle standard Slipstream and Slipstream 2 / Gauge Caps as distinct router/quoter configurations selected by venue family metadata.
- R10. Uniswap V3 and Uniswap V4 support must execute through the appropriate Universal Router flows and account for their different path encodings.
- R11. V1 must include executable native ETH route mode rather than treating all ETH liquidity as WETH-only. Routes may start, settle, or intermediate through native ETH when required by a venue such as the ZORA/ETH Uniswap V4 pool.
- R12. The router must account for leftover native ETH and wrapped ETH explicitly so route settlement cannot strand value in the contract or confuse WETH-facing and ETH-facing route legs.
- R36. The v1 launch bar is frozen to the venue families and production route fixture snapshot captured for this requirements effort. Later `www` route graph additions do not automatically expand the v1 launch bar unless they are explicitly promoted into the v1 snapshot.
- R37. Each launch-blocking venue family must have active `www` route generation, validated Base venue metadata, and at least one deterministic buy and sell fixture before launch. If a listed venue cannot meet that evidence bar, launch remains blocked until the fixture is repaired or the v1 snapshot is revised by an explicit product decision.
- R38. Native ETH must have an explicit route asset identity distinct from WETH. Routes starting with native ETH must require `msg.value == amountIn`; routes not starting with native ETH must reject nonzero `msg.value`. Any later native ETH leg must be funded only by route-local assets produced by earlier legs.

**Fee And Governance**

- R13. The default community fee must be `0.2222%`, represented as `2222 ppm` against a `1_000_000` denominator.
- R14. The fee must be charged exactly once on final route output, after all route legs have completed and before net settlement to the recipient.
- R15. The fee recipient at deployment must be `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`.
- R16. The router must be ownable. The deployer initially owns it, then ownership transfers to the community Base multisig after contract validation and `www` integration validation.
- R17. The owner must be able to update the fee recipient, update the fee rate within a hard maximum of `10_000 ppm`, and enable or disable coarse venue families.
- R18. Owner controls must not require routine multisig updates for ordinary route graph changes in `www`.

**Custody And Safety**

- R19. The router must measure route-local token and native ETH balances before and after each leg so ambient balances, donations, or rescue leftovers cannot satisfy user slippage checks or be consumed by split amount modes.
- R20. The router must transfer the final fee amount to the fee recipient and the final net amount to the route recipient in the intended output asset.
- R21. The router must prevent arbitrary external-call routing disguised as adapter payloads. Each executable leg must be constrained to a supported venue family and expected target.
- R22. Failed execution must revert atomically, including fee transfer and user settlement.
- R23. The router must include a rescue path for non-route dust that does not weaken route-local accounting or let owner-controlled assets satisfy user routes.
- R24. The router must use reentrancy protection around execution and settlement.
- R25. The router must explicitly handle FAME DN404 behavior. It must not mint or retain mirror NFTs during transient FAME custody, and deployed router addresses must have `getSkipNFT(router) == true`.
- R26. The router must not rely on FAME giving Permit2 default infinite allowance; FAME's current `DN404` implementation returns false for default Permit2 allowance.
- R39. Successful execution must leave no positive route-local balances in the router. Final output is split between fee recipient and route recipient, while route-local non-output leftovers, including input or intermediate-token dust, must be returned to `msg.sender`.
- R40. Venue approvals needed after funds enter router custody are the router's responsibility. `www` should only request user approvals or native ETH value needed to transfer the route input into the router.
- R41. Uniswap V3/V4 adapters must accept structured swap data or validate a strict Universal Router command allowlist. Raw arbitrary Universal Router command bytes must be rejected, and allowed commands must constrain payer, recipient, sweep, unwrap/wrap, and Permit2 semantics to preserve router custody and final fee accounting.
- R42. Uniswap V4 leg validation must cover PoolKey currency data, fee or tick spacing, hook address, and hook data boundaries. Validation may rely on the frozen v1 fixture metadata or an explicit venue metadata policy, but must not treat the Universal Router address alone as sufficient.

**Validation And Integration**

- R27. Foundry tests must cover fee math, ownership updates, venue enablement, deadline/slippage reverts, unsupported venue reverts, malformed route reverts, and exact fee-on-final-output accounting.
- R28. Base fork tests must be pinned and must validate executable buy and sell routes for each v1 venue family before launch.
- R29. Fork tests must include at least one split route and one multi-hop route where the fee is charged once after the merged final output.
- R30. Fork tests must include native ETH route execution and settlement for a V4 ETH-backed path.
- R31. Fork tests must demonstrate failed swaps revert without leaving route-local user funds in the router.
- R32. The repo must add Base RPC and Basescan configuration needed to run and verify the router workflow, matching the existing project style in `foundry.toml` and deployment docs.
- R33. `www` integration is required before ownership transfer. The frontend must submit routes matching the contract schema, show net post-fee output, request the correct approvals, and model native ETH separately from WETH where a route requires it.
- R43. Predeployment validation must refresh current production venue metadata and executable route fixtures against live Base state, in addition to running pinned fork regression tests.
- R44. Launch validation must prove the final deployed router address has `getSkipNFT(router) == true` before any FAME route family is enabled.
- R45. `www` integration must enforce route schema/version compatibility, calculate and display post-fee minimums from the same fee parameters as the contract, keep venue metadata in sync with the v1 fixture snapshot, and maintain fixture parity between generated routes and contract fork tests.
- R46. `www` must label native ETH and WETH distinctly anywhere both can affect a route, including quote review, approval or signing, execution, settlement, and failure states. Native ETH input routes must show that no ERC-20 approval is required and that ETH is sent as transaction value.
- R47. `www` validation must cover the happy path and core edge states: quote review, required approval or native ETH transaction path, pending approval, approval rejection or failure, pending execution, success receipt, expired or stale route refresh, disabled or unsupported venue, and reverted execution with no fee paid.

## Success Criteria

- A user can execute a FAME buy or sell through any supported venue family from the frozen v1 route universe and receive at least the displayed post-fee minimum.
- Split routes charge the `0.2222%` fee once, not once per leg or once per venue.
- A failed leg, expired route, insufficient output, unsupported venue, or malformed payload reverts without fee payment or stranded route-local funds.
- Pinned Base fork tests provide regression proof for all v1 venue families, and fresh predeployment validation confirms the frozen fixture snapshot still matches executable production Base state.
- The community multisig only needs to govern durable controls: fee parameters, fee recipient, ownership, and coarse venue-family enablement.
- Representative eligible routes in `www` produce competitive net post-fee quotes and reduce fragmented approval or execution flows compared with sending users to separate public routers.

## Scope Boundaries

- The router will not search for the best route onchain.
- The router will not quote routes or decide route quality for users.
- The router will not support arbitrary calldata execution.
- The router will not require multisig approval for every individual pool or frontend route graph update.
- The router will not be considered v1-launchable with only a partial venue set.
- New route families or pools discovered after the frozen v1 snapshot are out of scope for v1 unless explicitly promoted into the launch bar.
- Cross-chain routing, limit orders, exact-output swaps, TWAP protection, MEV protection, and automated fee conversion are out of scope for v1.
- Delegated or signed third-party payer execution is out of scope for v1.

## Key Decisions

- Full-venue v1 with a frozen snapshot: V1 launch requires Scale/Equalizer V2, Uniswap V2, Aerodrome Slipstream, Aerodrome Slipstream 2 / Gauge Caps, Uniswap V3, and Uniswap V4 contract execution validation from a frozen fixture set. Partial venue support would undercut the product promise of one FAME execution surface, but implementation can still be sequenced internally.
- Explicit native ETH mode: Native ETH is a first-class route asset for v1, instead of forcing all ETH-backed liquidity through WETH-normalized behavior. `www` should keep WETH as the ERC-20 mental model and expose native ETH distinctly only when a route actually uses native ETH.
- Final-output fee: The community fee is charged once on the final route output so split and multi-hop routes stay explainable.
- Offchain intelligence, onchain settlement: `www` owns route discovery and route quality; the contract owns custody, execution, slippage, fee, and settlement invariants.
- Coarse governance: The multisig controls durable risk levers, while routine route graph changes remain offchain.

## Dependencies / Assumptions

- `docs/ideation/2026-05-10-fame-multi-leg-router-ideation.md` is the source of the current Base venue metadata, protocol encoding notes, and validation facts.
- `www` can continue producing validated route candidates and will be updated for the correct Slipstream 2 / Gauge Caps router and quoter addresses before production integration.
- `www` route graph changes after the frozen v1 fixture snapshot are assumed to be post-v1 candidates unless explicitly promoted into the launch bar.
- The existing repo has FAME and launch/liquidity contracts but no implemented multi-leg router yet. This was verified by scanning `src`, `test`, `script`, `docs`, and `foundry.toml`.
- `foundry.toml` currently configures Sepolia RPC and Etherscan settings, but not Base RPC or Basescan settings.
- `Fame` exposes skip-NFT management through `setSkipNftForAccount`, and `DN404.getSkipNFT` defaults contract addresses to skip NFTs unless explicitly changed.

## Outstanding Questions

### Resolve Before Planning

- None.

### Deferred to Planning

- [Affects R3-R12][Technical] Define the exact route and leg encoding that keeps calldata compact while preserving clear validation errors.
- [Affects R9][Needs research] Confirm final Slipstream 2 / Gauge Caps route fixtures after the `www` simulator patch lands.
- [Affects R10-R12, R41-R42][Technical] Decide whether Universal Router interactions should be wrapped in internal adapter logic or isolated adapter contracts, and define the exact command allowlist and V4 hook metadata policy.
- [Affects R23, R39][Technical] Define non-route dust rescue rules that are safe for ERC-20s, native ETH, and FAME DN404 behavior without touching successful route leftovers.
- [Affects R28-R30][Needs research] Choose pinned Base fork blocks and deterministic funded accounts for each production route fixture.
- [Affects R27-R31, R43][Technical] Define the fresh predeployment validation command or checklist that refreshes current Base metadata after pinned fork regression tests pass.
- [Affects R47][Product / Design] Decide whether the existing `www` swap form can absorb native ETH/WETH and multi-approval states, or whether a dedicated route review step is needed.
- [Affects R1-R5][Technical] Set maximum leg, path, and calldata bounds so full-venue split routes remain predictable on Base.

## Next Steps

-> `/ce:plan` for structured implementation planning.
