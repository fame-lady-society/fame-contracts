---
title: "feat: FAME V4 Creator-Coin Fixture Policy"
type: feat
status: implemented
date: 2026-05-12
origin: docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md
---

# feat: FAME V4 Creator-Coin Fixture Policy

## Overview

Add a deterministic fixture policy and creator-coin pool catalog around the existing route solver so V4 hook coverage says exactly what it proves. basedflick/ZORA should be represented as production hook-address V4 coverage with explicit empty swap `hookData`, while valid non-empty V4 swap-hook-data proof remains a separate evidence target.

## Problem Frame

The current route solver can generate executable composed routes through basedflick/ZORA, but the remaining todo originally pushed toward proving non-empty V4 swap `hookData`. The local fleet reference shows ordinary ZORA creator-coin swaps use `hookData: "0x"`, and an arbitrary non-empty basedflick/ZORA trial reverted at Base block `45884844`. The implementation should therefore make fixture evidence truthful: catalog ZORA creator-coin pool metadata, classify hook coverage explicitly, and prevent docs or matrices from implying basedflick/ZORA proves non-empty swap hook data (see origin: `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`).

## Requirements Trace

- R1-R6. Classify V4 hook-related evidence, allow hook-address production swaps with empty `hookData`, reject fabricated non-empty swap `hookData` claims, and keep factory `postDeployHookData` separate from ordinary V4 swap hook data.
- R7-R11. Add a deterministic, reviewable creator-coin pool importer/catalog for known ZORA creator-coin pairings, starting with basedflick/ZORA, with traceable evidence and no automatic launch promotion.
- R12-R16. Update fork/gap coverage reporting so hook-address routes, non-empty swap hook data, V4 multi-hop paths, native ETH, split, and split-then-merge coverage are distinct, while preserving existing router safety and Doppler secret-handling rules.

## Scope Boundaries

- No open-ended onchain discovery or price ranking.
- No fabricated non-empty V4 swap `hookData`.
- No use of Zora factory `postDeployHookData` as ordinary Universal Router V4 `PathKey.hookData`.
- No raw Universal Router multi-hop `PathKey[]` schema expansion in this step.
- No weakening of existing route hash, fee, custody, venue allowlist, payload-size, or launch-manifest tests.

### Deferred to Separate Tasks

- Production non-empty swap-hook-data proof: separate follow-up if a valid hook-specific payload is found.
- Local V4 hook harness for non-empty swap `hookData`: separate follow-up if no production route exists.
- Fleet-style V4 multi-hop `PathKey[]` adapter support: separate schema/adapter expansion.

## Context & Research

### Relevant Code and Patterns

- `router-ts/src/config/base.ts` loads the checked-in pool fixture and already requires explicit `hookData` for hooked V4 pools.
- `router-ts/src/compiler/types.ts` defines route capabilities that currently include only coarse `v4Hooks`.
- `router-ts/src/compiler/compileRoute.ts` marks basedflick/ZORA composed routes with `v4Hooks: true`.
- `router-ts/src/matrix/generateGapMatrix.ts` writes the user-facing route gap matrix from generated solver routes.
- `router-ts/src/artifacts/writeArtifacts.ts` writes deterministic JSON artifacts and the Solidity solver manifest.
- `test/router/FameRouterGeneratedArtifacts.t.sol` verifies generated hashes and route artifact parity.
- `test/router/FameRouterForkBase.t.sol` executes generated solver routes on the pinned Base fork.
- `test/router/fixtures/base-v1-pools.json` contains `uniswap-v4-basedflick-zora` with a hook address and `hookData: "0x"`.
- `router-ts/README.md` documents pure TypeScript verification and fork validation commands.

### Institutional Learnings

- `docs/solutions/workflow-issues/public-config-doppler-foundry-aliases-2026-05-12.md` requires RPC URLs and other secrets to stay in Doppler, with public config loaded separately.

### External References

- No web research needed. The relevant behavior comes from local repo fixtures and the sibling fleet reference already captured in the origin ideation doc.

## Key Technical Decisions

- **Catalog from known config first:** Build the creator-coin catalog from explicit configured pool IDs, not open-ended RPC discovery. This satisfies the evidence goal without expanding solver scope.
- **Classify coverage in data, not prose only:** Add structured capability/coverage fields to generated artifacts and gap matrix rows so review tooling can distinguish hook-address coverage from non-empty swap-hook-data coverage.
- **Keep catalog evidence separate from launchability:** A catalog entry proves pool metadata provenance and policy. A route is fork-covered only when the generated route artifact executes through `FameRouter`.
- **Preserve `v4Hooks` compatibility:** Keep the existing coarse flag for current consumers, and add narrower flags for hook-address and non-empty swap-hook-data evidence.
- **Manifest the catalog hash:** Include the creator-coin catalog in generated artifact checks so stale catalog data is caught mechanically.

## Open Questions

### Resolved During Planning

- **Initial catalog scope:** Start with basedflick/ZORA because it is the known production creator-coin pairing already present in the pool fixture and generated route set.
- **Evidence source:** Use committed pool config plus existing pinned fork pool metadata validation as the initial catalog evidence. Do not add RPC-dependent import behavior to pure tests.
- **Todo 007 disposition:** Reframe it to policy/catalog work now, with residual non-empty swap-hook-data proof explicitly tracked instead of forced into basedflick/ZORA.
- **Residual proof tracking:** Create todo 008 for valid production or local-harness non-empty ordinary V4 swap-hook-data proof so closing todo 007 does not erase the narrower remaining target.

### Deferred to Implementation

- Exact field names for catalog entries and matrix coverage: choose names that fit current TypeScript types and JSON style while preserving the requirements.
- Whether to add a separate generated catalog Solidity test or extend `FameRouterGeneratedArtifacts.t.sol`: choose the least duplicated option while keeping hash coverage.

## Output Structure

```text
router-ts/src/catalog/
  creatorCoins.ts
router-ts/test/
  creator-coin-catalog.spec.ts
test/router/fixtures/
  base-v1-creator-coin-catalog.json
```

## Implementation Units

- [x] **Unit 1: Add V4 Fixture Evidence Types And Catalog Builder**

**Goal:** Add typed policy classifications and a deterministic creator-coin catalog builder for basedflick/ZORA.

**Requirements:** R1-R11

**Dependencies:** None

**Files:**
- Create: `router-ts/src/catalog/creatorCoins.ts`
- Modify: `router-ts/src/compiler/types.ts`
- Test: `router-ts/test/creator-coin-catalog.spec.ts`

**Approach:**
- Define narrow evidence and hook-data policy types for hook-address swaps, non-empty swap hook data, factory/deploy hook data, local hook harnesses, and diagnostics.
- Build catalog entries from a configured list of creator-coin pool IDs against `loadSupportedBasePools()`.
- Validate that basedflick/ZORA is a V4 pool, has a nonzero hook address, has explicit empty swap `hookData`, and carries expected token/currency identities.
- Include source evidence references to the pool fixture, existing fork metadata validation, and fleet-style discovery posture captured in the ideation doc.

**Execution note:** Implement tests first for the catalog classification because this unit is primarily data-contract behavior.

**Patterns to follow:**
- `router-ts/src/config/base.ts`
- `router-ts/src/artifacts/schema.ts`
- `router-ts/test/config.spec.ts`

**Test scenarios:**
- Happy path: catalog contains basedflick/ZORA with hook-address swap coverage and empty swap `hookData`.
- Edge case: catalog keeps creator coin, base currency, currency0, and currency1 identities distinct and deterministic.
- Error path: catalog builder rejects a configured non-V4 pool or a hooked V4 pool with missing/invalid hook-data policy.
- Error path: catalog builder rejects arbitrary non-empty swap `hookData` unless explicitly classified as valid non-empty evidence.

**Verification:**
- Pure Bun tests prove the catalog data contract without requiring Base RPC.

- [x] **Unit 2: Generate And Check Creator-Coin Catalog Artifact**

**Goal:** Check in the deterministic catalog artifact and make generated-output verification catch drift.

**Requirements:** R7-R11, R15-R16

**Dependencies:** Unit 1

**Files:**
- Modify: `router-ts/src/artifacts/writeArtifacts.ts`
- Modify: `test/router/fixtures/FameRouterSolverFixtureManifest.sol`
- Create: `test/router/fixtures/base-v1-creator-coin-catalog.json`
- Modify: `test/router/FameRouterGeneratedArtifacts.t.sol`
- Test: `router-ts/test/artifact-schema.spec.ts`
- Test: `test/router/FameRouterGeneratedArtifacts.t.sol`

**Approach:**
- Extend `generateOutputs()` to emit stable catalog JSON.
- Add catalog hash and entry count to the solver fixture manifest.
- Extend generated artifact checks to assert the catalog file hash and basedflick/ZORA catalog entry count.
- Keep the catalog separate from `base-v1-pools.json` launch fixture counts.

**Patterns to follow:**
- `router-ts/src/artifacts/writeArtifacts.ts`
- `test/router/fixtures/FameRouterSolverFixtureManifest.sol`
- `test/router/FameRouterGeneratedArtifacts.t.sol`

**Test scenarios:**
- Happy path: `router:generate:check` fails if the checked-in catalog differs from generated output.
- Integration: Foundry generated-artifacts test verifies the catalog hash through `FameRouterSolverFixtureManifest`.
- Scope boundary: launchable pool and route counts remain tied to the existing launch manifest, not the new catalog.

**Verification:**
- Generated catalog JSON is stable and included in TypeScript and Foundry artifact checks.

- [x] **Unit 3: Split Hook Coverage In Route Artifacts And Gap Matrix**

**Goal:** Make generated route artifacts and gap matrix rows explicitly distinguish hook-address coverage from non-empty swap-hook-data coverage.

**Requirements:** R1-R6, R12-R16

**Dependencies:** Unit 1

**Files:**
- Modify: `router-ts/src/compiler/types.ts`
- Modify: `router-ts/src/compiler/compileRoute.ts`
- Modify: `router-ts/src/matrix/types.ts`
- Modify: `router-ts/src/matrix/generateGapMatrix.ts`
- Modify: `router-ts/src/artifacts/schema.ts`
- Modify: `test/router/fixtures/base-v1-route-gap-matrix.json`
- Modify: `test/router/fixtures/base-v1-solver-routes.json`
- Test: `router-ts/test/artifact-schema.spec.ts`
- Test: `test/router/FameRouterGeneratedArtifacts.t.sol`

**Approach:**
- Preserve `v4Hooks` as the coarse existing flag.
- Add narrower capability flags for V4 hook-address coverage, non-empty V4 swap `hookData`, and V4 multi-hop `PathKey[]` coverage.
- Populate basedflick/ZORA generated routes as hook-address coverage with `nonEmptyV4SwapHookData: false`.
- Update blocked native ETH rows and route rows so capability fields remain complete and deterministic.

**Patterns to follow:**
- `router-ts/src/compiler/compileRoute.ts`
- `router-ts/src/matrix/generateGapMatrix.ts`
- `router-ts/test/artifact-schema.spec.ts`

**Test scenarios:**
- Happy path: basedflick/ZORA generated routes have hook-address coverage true and non-empty swap-hook-data coverage false.
- Edge case: split routes without V4 legs keep all V4-specific coverage flags false.
- Error path: no generated production route artifact reports non-empty swap-hook-data coverage unless a V4 payload contains non-empty hook data.
- Integration: gap matrix rows expose the same distinction as route artifacts.

**Verification:**
- The generated route and matrix artifacts no longer require prose to explain the hook-data distinction.

- [x] **Unit 4: Refresh Docs And Todo Handoff**

**Goal:** Update user-facing docs and todo status so the next implementer sees the correct fixture policy.

**Requirements:** R1-R6, R12-R16

**Dependencies:** Units 1-3

**Files:**
- Modify: `router-ts/README.md`
- Modify: `.context/compound-engineering/todos/007-pending-p2-prove-non-empty-v4-hook-data-fork-route.md`
- Create: `.context/compound-engineering/todos/008-pending-p2-prove-valid-non-empty-v4-swap-hook-data.md`
- Modify: `docs/plans/2026-05-12-003-feat-fame-v4-creator-coin-fixture-policy-plan.md`

**Approach:**
- Document the catalog artifact and the difference between hook-address coverage and non-empty swap-hook-data proof.
- Mark implemented plan units as complete as they land.
- Leave residual non-empty swap-hook-data proof visible if no valid production payload or local harness is added.

**Patterns to follow:**
- `router-ts/README.md`
- Existing `.context/compound-engineering/todos/` lifecycle notes.

**Test scenarios:**
- Test expectation: none for prose-only doc edits; verification is review against the origin requirements and generated artifacts.

**Verification:**
- Docs and todo wording match the generated catalog/matrix behavior.

## System-Wide Impact

- **Interaction graph:** TypeScript generator outputs feed Foundry artifact parity tests and pinned fork execution. The new catalog should add artifact evidence without changing router execution.
- **Error propagation:** Pure catalog validation errors should fail `router:verify` before any fork test is attempted.
- **State lifecycle risks:** No persistent runtime state is introduced; only deterministic checked-in artifacts are added.
- **API surface parity:** JSON artifacts gain new coverage fields. Solidity route execution reads route fields only, so execution should remain backward-compatible.
- **Integration coverage:** TypeScript generated checks and Foundry artifact hash tests must both include the catalog.
- **Unchanged invariants:** Existing launch manifest counts, route hashes, final-output fee settlement, and route-local balance assertions remain unchanged.

## Risks & Dependencies

| Risk | Mitigation |
| --- | --- |
| Catalog looks like fork execution proof by itself | Keep catalog artifact separate from route artifacts and document that promotion requires route generation plus fork execution |
| Capability field churn breaks old tests | Preserve existing `v4Hooks` and add narrower fields rather than replacing it |
| Non-empty hook-data proof gets accidentally erased | Keep residual proof explicitly tracked in todo 007 and docs |
| RPC secrets leak during validation | Keep catalog generation pure; use Doppler convention only for optional fork tests |

## Documentation / Operational Notes

- `router-ts/README.md` should name the new catalog and its policy labels.
- Fork validation command remains the existing Doppler-backed command; no RPC value should appear in docs or logs.

## Sources & References

- **Origin document:** `docs/brainstorms/2026-05-12-fame-v4-creator-coin-fixture-policy-requirements.md`
- Related requirements: `docs/brainstorms/2026-05-12-fame-route-solver-fork-matrix-requirements.md`
- Related todo: `.context/compound-engineering/todos/007-pending-p2-prove-non-empty-v4-hook-data-fork-route.md`
- Local reference: `docs/ideation/2026-05-12-fame-v4-hook-data-fork-route-ideation.md`
- Generated fixture config: `test/router/fixtures/base-v1-pools.json`
