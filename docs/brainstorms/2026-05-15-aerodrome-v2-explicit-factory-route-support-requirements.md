---
date: 2026-05-15
topic: aerodrome-v2-explicit-factory-route-support
source_ideation: docs/ideation/2026-05-15-aerodrome-v2-migrated-slipstream-pool-support-ideation.md
---

# Aerodrome V2 Explicit-Factory Route Support

## Problem Frame

The app-side FAME swap solver has identified a high-value Base Aerodrome V2 USDC/WETH pool, but `FameRouter` cannot safely execute it today. The existing `Solidly` adapter supports the Scale/Equalizer three-field route shape `{ from, to, stable }`; Aerodrome V2 uses a Solidly-style router with an explicit factory field in each route hop. Treating both as the same venue would make route bytes ambiguous and easy to miscompile.

The first slice should unlock Aerodrome V2 execution without changing existing Scale/Equalizer behavior and without folding migrated Slipstream factory work into the same deliverable.

## Outcome / Why Now

The immediate outcome is to convert the reviewed Aerodrome V2 USDC/WETH pool from an app-side blocked diagnostic into a contract-executable FameRouter venue. This matters because USDC/WETH is core connector liquidity for the FAME route universe, and the app solver has already identified this pool as valuable but unusable until the contract can encode Aerodrome V2's explicit-factory route shape.

Success should be judged by execution evidence, not just schema support: after this slice, `www` should be able to remove the Aerodrome V2 blocked reason only when contract artifacts prove the intended router, factory, pool identity, and fork execution path. If the supported app solver still does not select or consider the pool after contract support lands, the work should remain valid as venue capability, but route-quality follow-up belongs in `www`, not in this contract slice.

## Requirements

**Aerodrome V2 Execution**

- R1. FameRouter must support Aerodrome V2 exact-input ERC-20 swap legs whose route hops include `from`, `to`, `stable`, and `factory`.
- R2. Aerodrome V2 support must be exposed as a distinct route venue from existing `Solidly` support, appended as `AerodromeV2 = 7` without changing existing venue ordinals.
- R3. Route schema version `1` remains acceptable only if Solidity, `router-ts`, docs, generated artifacts, and `www` schema consumers are updated to understand venue ordinal `7` before app unblocking.
- R4. Aerodrome V2 legs must reject native ETH input/output, zero or mismatched route paths, bad intermediate continuity, and route endpoints that do not match the leg token pair.
- R5. Planning must confirm the exact Base Aerodrome V2 router interface before implementation changes: route tuple layout/order, function selector, return type, deadline behavior, and the expected invalid-factory failure mode.
- R6. Aerodrome V2 route execution must preserve the existing router guarantees: route-local balance accounting, per-leg minimums, final post-fee settlement, target allowlisting, and no stranded route-local balances.

**Pool And Fixture Evidence**

- R7. The Base Aerodrome V2 USDC/WETH pool `0xcdac0d6c6c59727a65f871236188350531885c43` must be represented as an Aerodrome V2 fixture with its router, factory, pool address, token ordering, stable flag, and fee evidence.
- R8. Generated route artifacts must encode Aerodrome V2 legs with the explicit factory route shape and must not encode Aerodrome V2 pools through the existing three-field `Solidly` payload.
- R9. Pinned Base fork coverage must prove at least one executable Aerodrome V2 USDC/WETH hop through the intended Aerodrome V2 router and factory.
- R10. Negative coverage must prove bad factory, bad router target, wrong token endpoints, or wrong route shape fails closed before the pool can be treated as launchable evidence.
- R11. Fork validation must independently derive the pool selected by the Aerodrome V2 router/factory/token/stable metadata and assert it equals `0xcdac0d6c6c59727a65f871236188350531885c43`.
- R12. Launch validation must verify Aerodrome V2 metadata explicitly, including factory code, pool factory or factory-derived pool identity, token ordering, stable flag, and fee evidence. If the fee is not readable through a stable onchain API, the fixture must label it as offchain evidence rather than pretending live validation proved it.

**Rollout Boundary**

- R13. This slice requires deploying a new `FameRouter` binary with the appended `AerodromeV2` venue, regenerated fixture manifest hashes, updated `BASE_FAME_ROUTER_ADDRESS`, and `www` schema parity before the app removes the Aerodrome V2 blocker.
- R14. Migrated Slipstream USDC/WETH support is out of scope for this first slice except as a documented follow-up gate.
- R15. The migrated Slipstream follow-up gate must state what remains blocked after Aerodrome V2 ships and what evidence would promote it next: stable router/quoter/factory tuple, factory-keyed pool identity proof, and pinned fork execution against the migrated pool.
- R16. The app-side `www` pool blocker for Aerodrome V2 should only be removed after contract-side artifact parity, fork execution, deployment/manifest target evidence, and deployed router address update exist.
- R17. Deployment manifests must include the Aerodrome V2 router target only after the fixture and fork evidence is launchable.

## Decision Evidence / Falsification

The distinct venue choice is deliberate but not a blanket rule that every future router variant deserves a new enum. It is warranted here because Aerodrome V2 has a different calldata contract from the existing `Solidly` venue, and using one venue name for two incompatible route tuple shapes would make generated route review and app schema parity less obvious.

This decision should be revisited if planning finds that the Base Aerodrome V2 router accepts the existing three-field Scale/Equalizer route shape, or if several current supported venues need the same explicit-factory route ABI. In that case, a shared factory-route abstraction may be lower carrying cost than a dedicated venue. Reversal cost is medium because a new venue ordinal affects Solidity, `router-ts`, fixtures, docs, deployment manifests, and `www` schema consumers, so the ABI confirmation in R5 must happen before code implementation.

## Success Criteria

- Aerodrome V2 USDC/WETH route artifacts can be generated and decoded with the explicit factory route shape.
- Existing Scale/Equalizer `Solidly` routes continue to encode and execute with the three-field route shape.
- Foundry unit tests cover Aerodrome V2 happy path and fail-closed route-shape/factory cases.
- Pinned Base fork tests prove the Aerodrome V2 USDC/WETH route executes against the intended router/factory and independently derives the expected pool identity.
- Launch/deployment validation enables the Aerodrome V2 target only when the manifest evidence is synchronized.
- `www` has enough contract evidence to remove the Aerodrome V2 blocked reason without inferring support from unrelated Solidly fixtures.

## Scope Boundaries

- Do not implement migrated Slipstream factory support in this slice.
- Do not collapse `Solidly`, `AerodromeV2`, `Slipstream`, and `Slipstream2` into a generic factory-configured venue model.
- Do not add onchain route discovery or quoting; the app solver remains responsible for route selection and quote quality.
- Do not treat Aerodrome V2 as Uniswap V2-style `address[] path` routing.
- Do not change existing fee policy, custody policy, or final settlement behavior.

## Key Decisions

- Add a distinct Aerodrome V2 venue instead of overloading `Solidly`: this keeps route ABI differences visible in schema, docs, generated artifacts, and app integration, while accepting a new ordinal only after R5 confirms the ABI assumption.
- Append `AerodromeV2 = 7` under route schema version `1`: preserve existing ordinals and keep schema churn localized, but require downstream schema parity before app enablement.
- Keep migrated Slipstream separate: its blocker is factory identity evidence, not Aerodrome V2 route-shape support.
- Require explicit factory evidence in fixtures and generated payloads: the factory field is part of the Aerodrome V2 route contract and should be auditable.

## Dependencies / Assumptions

- The Aerodrome V2 router for Base USDC/WETH is `0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43`.
- The target Aerodrome V2 pool is `0xcdac0d6c6c59727a65f871236188350531885c43`.
- The current app-side pool evidence in `../www/src/features/fame-swap/artifacts/base-v1-pools.json` is accurate enough to seed contract fixtures, but planning must verify pool metadata against a pinned Base fork before launch.
- Public addresses may be committed in fixture/config files; RPC URLs, private keys, and explorer keys remain in Doppler.

## Outstanding Questions

### Resolve Before Planning

- None.

### Deferred to Planning

- [Affects R5][Technical] Capture the exact Aerodrome V2 router interface evidence in the implementation plan before code edits begin.
- [Affects R7-R12][Needs research] Verify the Aerodrome V2 factory address, stable flag, token ordering, reserves, pool identity derivation, and fee evidence at the pinned Base block.
- [Affects R9][Technical] Choose the smallest deterministic route fixture that proves Aerodrome V2 execution without requiring unrelated migrated Slipstream support.
- [Affects R17][Technical] Decide whether Aerodrome V2 router/factory public constants belong only in fixture JSON or should also be mirrored in `config/fame-public.env`.

## Next Steps

-> `/ce:plan docs/brainstorms/2026-05-15-aerodrome-v2-explicit-factory-route-support-requirements.md` for structured implementation planning.
