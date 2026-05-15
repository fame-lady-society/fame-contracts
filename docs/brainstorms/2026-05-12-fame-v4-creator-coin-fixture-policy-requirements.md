---
date: 2026-05-12
topic: fame-v4-creator-coin-fixture-policy
source: docs/ideation/2026-05-12-fame-v4-hook-data-fork-route-ideation.md
status: requirements
---

# FAME V4 Creator-Coin Fixture Policy Requirements

## Problem Frame

Todo 007 was originally framed as proving a pinned Base fork route whose Uniswap V4 swap payload contains non-empty `hookData`. The current production-like ZORA creator-coin example, basedflick/ZORA, does not support that framing: it is a hook-addressed V4 pool whose ordinary swap route uses explicit empty `hookData`. A trial with arbitrary non-empty bytes reverted inside the Doppler hook, and the sibling fleet reference shows its working ZORA creator-coin swaps also use `hookData: "0x"` for normal swaps.

The useful next step is not to force invalid bytes into basedflick/ZORA. It is to define a fixture policy that describes what each fixture actually proves, then add a fleet-style creator-coin pool importer/catalog so ZORA/Doppler pool metadata can be validated before any route is promoted into solver fixtures or fork coverage.

This document refines the V4 hook-data expectations in `docs/brainstorms/2026-05-12-fame-route-solver-fork-matrix-requirements.md`: schema version `1` may support bounded non-empty V4 swap hook data, but a hook-addressed production pool with `hookData: "0x"` must not be mislabeled as non-empty hook-data coverage.

## Requirements

**Fixture Policy**

- R1. Every V4 hook-related fixture must classify the evidence it provides as one or more of: hook-address swap coverage, non-empty swap `hookData` coverage, factory/deploy hook-data research, or local hook-harness coverage.
- R2. A hook-addressed production V4 pool may be a valid route fixture with explicit empty swap `hookData`; docs, manifests, and gap matrices must describe that as hook-address coverage, not non-empty swap-hook-data coverage.
- R3. Non-empty V4 swap `hookData` may only be promoted into a fixture when it is derived from hook-specific production evidence or from a dedicated hook harness that requires and validates those bytes.
- R4. Arbitrary non-empty swap `hookData` must not be used to satisfy fixture coverage. Reverting probe results are useful evidence, but they should remain diagnostics unless they identify a valid hook payload.
- R5. Zora factory `postDeployHookData` must remain separate from Universal Router V4 `PathKey.hookData`. It can be documented as deployment-hook research, but it does not satisfy FameRouter ordinary swap-route coverage.
- R6. Existing FameRouter schema/version support for bounded non-empty V4 swap `hookData` remains in scope. This policy narrows what can be claimed as fork evidence; it does not remove the capability.

**Creator-Coin Pool Catalog**

- R7. Add a fleet-style creator-coin pool importer/catalog for known ZORA creator-coin pairings, starting with basedflick/ZORA when viable at the pinned Base block.
- R8. Catalog entries must be deterministic and reviewable, with explicit pool metadata for token identities, currency order, fee, tick spacing, hook address, native ETH versus WETH identity, and the configured swap `hookData` policy.
- R9. Catalog entries must be traceable to concrete evidence such as pool contract methods, factory logs, storage fallback, committed pool config, or pinned fork validation. The catalog must not rely on hand-copied metadata without an evidence source.
- R10. Catalog entries may feed the offchain solver as known supported pool config, but a catalog entry is not automatically a launchable route fixture. Promotion requires route artifact generation and fork execution evidence.
- R11. Additional creator-coin pairings should only be added when they meet the same metadata and evidence bar as basedflick/ZORA.

**Fork And Coverage Matrix**

- R12. Fork coverage must prove exactly the behavior it claims: hook-address production routes with empty `hookData`, non-empty swap-hook-data routes only when a valid payload exists, and local hook-harness coverage only when explicitly labeled as such.
- R13. The coverage matrix must distinguish hook-address V4 pools, non-empty swap `hookData`, V4 multi-hop `PathKey[]` routes, native ETH identity, split routes, and split-then-merge routes.
- R14. If no production non-empty swap-hook-data route is available at the pinned block, the residual non-empty proof must remain separately tracked or be satisfied by a clearly labeled local harness. basedflick/ZORA should not be forced into this role.
- R15. Any new fork command or fixture-generation workflow that needs Base RPC access must follow the repo's public-config plus Doppler convention and must not expose RPC URLs, private keys, mnemonics, or explorer API keys.
- R16. New fixture evidence must not weaken existing FameRouter custody, fee-settlement, route-hash, payload-size, venue-allowlist, or launch-manifest safety requirements.

## Evidence Policy Matrix

| Evidence type | Valid example | What it proves | What it does not prove |
| --- | --- | --- | --- |
| Hook-address swap | basedflick/ZORA with hook address and `hookData: "0x"` | FameRouter can execute a production hooked V4 pool route | Non-empty swap `hookData` is valid for that pool |
| Non-empty swap `hookData` | Hook-specific payload that quotes and executes on fork, or local hook harness requiring bytes | FameRouter forwards approved non-empty V4 swap hook data through V4 execution | Zora factory deployment hooks |
| Factory/deploy hook data | Fleet-style `postDeployHookData` for a self-snipe deployment flow | How Zora deployment hooks encode post-deploy buy instructions | Ordinary Universal Router V4 `PathKey.hookData` |
| Diagnostic probe | Revert evidence from candidate hook bytes | Which candidate payloads are invalid or require more hook knowledge | Route fixture success |

## Success Criteria

- Todo 007 is updated to target fixture-policy correctness plus a creator-coin pool catalog, while preserving non-empty swap-hook-data proof as a separate evidence target.
- basedflick/ZORA is represented as hook-address V4 coverage with explicit empty swap `hookData` if it remains viable at the pinned Base block.
- The route/fork gap matrix clearly separates hook-address coverage from non-empty swap-hook-data coverage.
- No production fixture contains fabricated non-empty V4 swap `hookData`.
- Catalog-promoted routes execute on the pinned Base fork before they are described as fork-covered fixtures.
- The residual non-empty swap-hook-data path is either proven with a valid production payload, proven with a labeled local hook harness, or kept open with evidence explaining the blocker.

## Scope Boundaries

- Do not require non-empty swap `hookData` for ZORA creator-coin pools unless the hook-specific evidence shows it is required.
- Do not treat Zora factory `postDeployHookData` as FameRouter V4 swap `hookData`.
- Do not turn the catalog into open-ended pool discovery or a price-first route finder in this step.
- Do not port fleet wholesale; use its ZORA/Doppler discovery and encoding posture as a reference.
- Do not weaken or relabel existing launchable fixtures to create artificial coverage.

## Key Decisions

- Reframe todo 007 around fixture truthfulness: the immediate gap is inaccurate evidence framing, not a missing magic byte string for basedflick/ZORA.
- Treat empty swap `hookData` as production-correct when the hooked pool uses it: a hook address alone is meaningful V4 coverage.
- Keep non-empty swap-hook-data proof alive as a separate target: it should be satisfied by valid hook behavior, not arbitrary bytes.
- Keep the creator-coin catalog separate from launch fixtures until routes are explicitly promoted and fork-tested.
- Use fleet as a behavioral reference: its working creator-coin swaps inform the policy, but this repo should keep a small FAME-specific fixture and solver surface.

## Dependencies / Assumptions

- The pinned Base block remains `45884844` unless planning finds a specific route-viability reason to revise it.
- The sibling fleet references remain useful for ZORA creator-coin pool discovery, V4 quoting, and Universal Router encoding patterns.
- FameRouter's bounded non-empty V4 hook-data support and allowlist behavior remain available for routes that legitimately require non-empty swap `hookData`.
- Public constants continue to live in `config/fame-public.env`; RPC URLs and other secrets remain in Doppler.

## Alternatives Considered

- Force arbitrary non-empty `hookData` into basedflick/ZORA: rejected because it already reverted on the pinned fork and is not grounded in hook-specific behavior.
- Use fleet `postDeployHookData` as V4 swap `hookData`: rejected because it belongs to a different lifecycle and ABI.
- Declare all hook-address V4 routes to be non-empty hook-data coverage: rejected because it would overstate the evidence.
- Remove non-empty hook-data support from the router: rejected because the router capability is useful and already unit-tested; only the production fork evidence needs better framing.

## Outstanding Questions

### Resolve Before Planning

- None.

### Deferred to Planning

- [Affects R7-R11][Technical] Decide the exact catalog artifact shape and whether it is checked in, generated on demand, or both.
- [Affects R7-R11][Needs research] Confirm which creator-coin pairings beyond basedflick/ZORA should be first-class in the initial catalog.
- [Affects R10-R13][Technical] Decide whether fleet-style V4 multi-hop `PathKey[]` support belongs in the same implementation step or remains behind the existing single-pool V4 adapter path.
- [Affects R14][Technical] Decide whether todo 007 is closed by the policy/catalog reframing with a residual follow-up, or remains open until a valid non-empty swap-hook-data fork or harness proof exists.

## Next Steps

-> `/ce:plan` for structured implementation planning.
