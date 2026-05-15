---
date: 2026-05-14
topic: native-weth-wrap-unwrap-route-legs
source: docs/ideation/2026-05-14-native-weth-wrap-unwrap-route-legs-ideation.md
status: requirements
---

# Native ETH/WETH Wrap And Unwrap Route Legs Requirements

## Problem Frame

The FAME router and `router-ts` route artifacts currently model native ETH and WETH as distinct assets, but there is no executable route leg for pure native ETH wrapping or WETH unwrapping. That forces the app-side solver to keep native ETH routes separate from WETH connector liquidity even when a route such as `ETH -> WETH -> FAME` or `FAME -> WETH -> ETH` would be useful and safe.

This work should add explicit wrap/unwrap behavior without turning `FameRouter` into a generic wrapping product or weakening the typed-adapter model. The capability exists to compose FAME-facing swap routes, not to provide standalone `ETH <-> WETH` conversion.

## Requirements

**Route Semantics**

- R1. Wrap and unwrap must be represented as their own route leg operation, not as pre-route, post-route, or swap-leg flags.
- R2. The operation must be exposed as a `NativeWrap` venue family appended to schema version `1` for low-churn integration. This is an explicit schema v1 extension, not a schema bump.
- R3. Valid `NativeWrap` directions are only `NATIVE_ETH -> WETH` and `WETH -> NATIVE_ETH`, where WETH is the enabled target for that leg.
- R4. Pure single-leg `ETH -> WETH` and `WETH -> ETH` routes must be rejected. `NativeWrap` is valid only as part of a larger route with at least one non-wrap swap leg.
- R5. `NativeWrap` legs must use empty payload data. No generic external-call payload, selector allowlist, or raw Universal Router wrap command is in scope.

**Amount And Output Behavior**

- R6. `NativeWrap` must support the existing `Exact`, `BalanceBps`, and `All` amount modes.
- R7. For `All`, route builders should encode `amount = 0`; the router computes the spend from the route-local balance of the leg input asset.
- R8. For `NativeWrap`, route builders should encode `minAmountOut = 0`. The router must derive the effective required output from the computed spend amount rather than requiring the duplicated value in calldata.
- R9. A successful `NativeWrap` leg must produce at least the computed spend amount in the output asset, measured through the same route-local balance-delta accounting used by other legs.
- R10. Top-level route input rules remain unchanged: native input routes require `msg.value == route.amountIn`, ERC-20 input routes reject nonzero `msg.value`, and `route.amountIn` must be nonzero.

**Safety And Configuration**

- R11. The WETH contract must be allowlisted as the `NativeWrap` target before any wrap or unwrap leg can execute.
- R12. `NativeWrap` must not create approvals. Wrapping consumes route-local native ETH; unwrapping consumes route-local WETH already held by the router.
- R13. Bad target, bad direction, non-empty payload, missing target allowlist, and standalone wrap/unwrap route cases must fail closed before any user funds can be stranded.
- R14. Existing route-local custody rules still apply: ambient balances cannot satisfy wrap/unwrap output, route-local leftovers are refunded after successful execution, and the final route output fee is charged once after all legs complete.

**Artifacts And Integration**

- R15. `router-ts` must model wrap/unwrap as a deterministic route primitive edge, not as a fake AMM pool.
- R16. Generated artifacts and debug output must distinguish native ETH, WETH, and `NativeWrap` capability so reviewers can see when native routes depend on WETH conversion.
- R17. The generated manifest or solver target allowlist must include the canonical Base WETH target for the `NativeWrap` venue before route artifacts using it are considered executable.
- R18. The app-side solver must keep current native ETH/WETH restrictions until contract tests, TypeScript encoding/parity checks, and fork or integration evidence prove the new primitive end to end.

## Success Criteria

- `ETH -> WETH -> FAME` can be represented as ordered route legs and execute without any implicit ETH/WETH normalization.
- `FAME -> WETH -> ETH` can be represented as ordered route legs and settle final native ETH through normal route settlement and fee accounting.
- A `NativeWrap` leg with `amountMode = All`, `amount = 0`, and `minAmountOut = 0` wraps or unwraps the full route-local input balance for that leg.
- Standalone pure wrap/unwrap routes are rejected.
- Bad target, bad direction, non-empty payload, missing allowlist, `msg.value` mismatch, and leftover-refund edge cases are covered by tests.
- TypeScript route encoding, enum ordinals, route hashing, generated artifacts, and Foundry parity tests all agree on the schema v1 `NativeWrap` extension.
- The route gap matrix or equivalent artifact makes native ETH, WETH, and NativeWrap-dependent evidence visibly distinct.

## Scope Boundaries

- No public standalone wrapping product.
- No fee-free special case for pure wrapping, because pure wrapping is out of scope.
- No generic external-call adapter.
- No raw Universal Router `WRAP_ETH` or `UNWRAP_WETH` command passthrough.
- No treatment of ETH and WETH as the same graph asset.
- No dynamic discovery of WETH-like wrappers beyond configured targets.
- No app-side lifting of native/WETH solver restrictions before contract-side proof exists.

## Key Decisions

- Own operation as route leg: A wrap/unwrap is represented by a `NativeWrap` leg so route ordering, amount modes, and custody accounting stay explicit.
- Internal-route-only: The feature unlocks FAME-facing routes through WETH liquidity; it does not make `FameRouter` a wrapping endpoint.
- Schema v1 extension: Append the new venue family to v1 to keep integration lean, while updating docs and parity tests so the new ordinal is deliberate.
- Lean output encoding: `NativeWrap` route builders encode `minAmountOut = 0`; the router derives the effective required output from the computed spend amount.
- Existing amount modes stay useful: `All` with `amount = 0` remains the natural way to wrap or unwrap the full route-local balance.

## Dependencies / Assumptions

- Native ETH remains `address(0)` and WETH remains the Base WETH ERC-20 address.
- The canonical Base WETH address is `0x4200000000000000000000000000000000000006`.
- Public deployment constants and manifest-visible addresses should follow the repo's `config/fame-public.env` convention when a new public value is needed.
- RPC-backed proof continues to use Doppler-provided secrets and Foundry chain aliases.

## Alternatives Considered

- Route-level pre/post wrap fields: Rejected because they only cover endpoints and add accounting outside ordinary legs.
- Generic external-call adapter: Rejected because the desired operation is narrow and should not open a new arbitrary-call surface.
- Universal Router wrap/unwrap commands: Rejected because this router already avoids raw command passthrough and can call WETH directly.
- User pre-wraps before routing: Rejected because it preserves the current native ETH route coverage gap.
- Fake pool fixture: Rejected because WETH wrapping is a deterministic primitive, not liquidity.
- Standalone wrapping through `FameRouter`: Rejected because it creates unnecessary product and fee semantics for a conversion users can perform directly.

## Outstanding Questions

### Resolve Before Planning

- None.

### Deferred to Planning

- [Affects R2][Technical] Choose the exact appended `NativeWrap` enum ordinal and update schema docs/tests consistently.
- [Affects R8-R9][Technical] Decide whether nonzero `minAmountOut` on `NativeWrap` should be ignored or rejected, while preserving the requirement that route builders encode `0`.
- [Affects R11, R17][Technical] Decide whether the Base WETH target lives only in generated manifests/artifacts or also in `config/fame-public.env`.
- [Affects R16-R18][Technical] Decide the smallest artifact/gap-matrix update that clearly distinguishes NativeWrap evidence without expanding unrelated route-solver scope.

## Next Steps

-> `/ce:plan docs/brainstorms/2026-05-14-native-weth-wrap-unwrap-route-legs-requirements.md` for structured implementation planning.
