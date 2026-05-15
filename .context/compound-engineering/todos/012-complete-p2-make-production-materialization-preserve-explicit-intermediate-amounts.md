---
status: complete
priority: p2
issue_id: "012"
tags: [router-ts, materialization, solver, review]
dependencies: []
---

# Make Production Materialization Preserve Explicit Intermediate Amounts

## Problem Statement

Production route materialization currently infers dynamic-input legs from `leg.amountMode === "Exact"` and `leg.tokenIn !== route.tokenIn`. That silently rewrites exact intermediate legs to `All`, which can consume assets that were intentionally reserved for a later leg in split or merge routes.

## Findings

- Review finding #2 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- `router-ts/src/materializeRoute.ts:153` computes `usesDynamicInput` from token identity rather than an explicit route-artifact property.
- API-contract and adversarial review both flagged this as a P2 because it can change route semantics during production materialization.
- The issue is distinct from native wrap behavior and should not be solved by treating all non-input legs as dynamic.

## Proposed Solutions

### Option 1: Make Dynamic Input Explicit

**Approach:** Add an explicit materialization flag or route-leg policy indicating that a leg should spend its full available balance in production. Preserve `Exact` by default.

**Pros:**
- Prevents materialization from changing explicit amounts by inference.
- Makes route intent visible in artifacts.
- Scales to split and split-then-merge routes.

**Cons:**
- Requires schema/test updates and regenerated artifacts.

**Effort:** Medium.

**Risk:** Medium.

### Option 2: Only Rewrite Known Generated All-Leg Patterns

**Approach:** Keep current schema, but narrow the rewrite to known generated patterns that are already represented as dynamic in the artifact.

**Pros:**
- Smaller change.
- Avoids a schema extension.

**Cons:**
- Still relies on implicit pattern matching.
- Easier to regress as solver coverage expands.

**Effort:** Small.

**Risk:** Medium.

## Recommended Action

Implement Option 1. Add an explicit dynamic-input policy to the route artifact/schema and preserve `Exact` intermediate leg amounts by default. Update materialization tests with a split or merge route that partially spends and later reuses an intermediate asset.

## Technical Details

Affected files:

- `router-ts/src/materializeRoute.ts`
- `router-ts/src/artifacts/schema.ts`
- `router-ts/src/compiler/compileRoute.ts`
- `router-ts/test/materialize-route.spec.ts`
- generated solver artifacts and manifest hashes if schema or materialized route behavior changes

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- API-contract reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/api-contract.json`
- Adversarial reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/adversarial.json`

## Acceptance Criteria

- [x] Production materialization preserves explicit intermediate `Exact` amounts unless a route artifact explicitly marks the leg as dynamic.
- [x] Tests cover a split or merge route where an intermediate token amount is partially spent and later reused.
- [x] Existing generated production-materialization behavior remains covered for intended `All` legs.

## Work Log

### 2026-05-15 - Exact Intermediate Amounts Preserved

**By:** Codex

**Actions:**
- Removed token-identity inference that rewrote intermediate `Exact` legs to `All` during production materialization.
- Kept `AmountMode.All` as the explicit dynamic-input marker, preserving current low-calldata route semantics.
- Added a split/merge materialization regression test that keeps an explicit intermediate exact amount intact.

**Verification:**
- `bun run router:typecheck`
- `bun run router:test`
- `bun run router:generate:check`
- [ ] `bun run --cwd router-ts verify` passes.

## Work Log

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review finding #2.

**Learnings:**
- Production materialization must not infer route semantics from token identity alone.
