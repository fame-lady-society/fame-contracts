---
status: complete
priority: p3
issue_id: "005"
tags: [router, gas, accounting]
dependencies: []
---

# Optimize Router Route-Local Snapshot Indexes

## Problem Statement

`FameRouter` still computes route-local balances by scanning the per-route snapshot array for the requested asset. The route is bounded by `MAX_ROUTE_LEGS`, so this is acceptable for launch correctness, but the follow-up cleanup plan called out compact per-leg asset indexes as a gas optimization opportunity.

## Findings

- Current custody tests pass and preserve ambient-balance isolation.
- The targeted router size check passes with optimizer enabled: `FameRouter` runtime size is 15,941 bytes.
- Gas report after cleanup measured `executeRoute` at 47,352 min / 160,659 avg / 338,300 max across the router test suite.
- The optimization would touch shared custody accounting, so it should wait for fixture-derived route shapes and gas baselines rather than be mixed with launch hardening.

## Proposed Solutions

### Option 1: Precompute Per-Leg Asset Indexes

**Approach:** Build route-local asset snapshots once and store each leg's tokenIn/tokenOut snapshot indexes in a compact memory array.

**Pros:**
- Avoids repeated linear scans in `_baseline`.
- Keeps accounting centralized.

**Cons:**
- Increases implementation complexity in the most security-sensitive router path.

**Effort:** 2-4 hours

**Risk:** Medium

### Option 2: Keep Current Bounded Scan

**Approach:** Leave the simple bounded scan in place until production fixtures prove the gas pressure is material.

**Pros:**
- Lowest custody risk.
- Current route length is capped.

**Cons:**
- Leaves some gas savings on the table.

**Effort:** 0 hours

**Risk:** Low

## Recommended Action

Closed for the current router launch goal. Keep the bounded scan because it is simple, audited by the current custody tests, and not creating launch-blocking gas or bytecode pressure.

## Acceptance Criteria

- [ ] Route-local asset indexes are precomputed without changing custody semantics.
- [ ] Ambient-balance isolation tests continue to pass.
- [ ] One-leg, multi-hop, and split-route gas numbers are captured before and after the change.
- [ ] Bytecode size remains under EIP-170 for `FameRouter`.

## Work Log

### 2026-05-12 - Closure

**By:** Codex

**Actions:**
- Rechecked router bytecode size and full router-targeted test pass.
- Deferred index precomputation as an unnecessary custody-path complexity increase for this goal.

**Learnings:**
- The current bounded scan remains the safer launch tradeoff until production route gas pressure proves otherwise.

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Deferred the optimization during Unit 6 because current correctness and launch blockers were higher value.
- Captured the existing gas and bytecode baseline after optimizer configuration.

**Learnings:**
- The bounded scan is auditably simple and currently covered by custody tests.
