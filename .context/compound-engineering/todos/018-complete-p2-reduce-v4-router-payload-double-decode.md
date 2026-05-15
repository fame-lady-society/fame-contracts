---
status: complete
priority: p2
issue_id: "018"
tags: [router, performance, uniswap-v4, review]
dependencies: []
---

# Reduce V4 Router Payload Double Decode

## Problem Statement

V4 route execution decodes the same Universal Router payload twice: once to derive/check hook-data policy and again inside `executeV4`. This adds gas on every V4 leg and can be cleaned up while preserving validation behavior.

## Findings

- Review finding #10 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- `src/FameRouter.sol:302` calls `UniversalRouterAdapter.v4HookDataKey(leg.data)`, which decodes the payload.
- `UniversalRouterAdapter.executeV4(...)` then decodes `leg.data` again.
- Performance review classified this as P2 because V4 routes are part of the router hot path.

## Proposed Solutions

### Option 1: Decode Once In The Adapter

**Approach:** Move hook governance and execution validation into a single adapter path so the V4 payload is decoded once.

**Pros:**
- Cleaner execution flow.
- Removes duplicate ABI decode cost.

**Cons:**
- May require passing allowlist state or callback-like validation into the adapter, which can hurt separation.

**Effort:** Medium.

**Risk:** Medium.

### Option 2: Return Decoded Payload From Validation Helper

**Approach:** Add a helper that decodes and validates the V4 payload once, returns the decoded payload and hook key, then execution consumes the decoded struct.

**Pros:**
- Keeps allowlist decision in `FameRouter`.
- Avoids duplicate decode.

**Cons:**
- More adapter API surface.

**Effort:** Medium.

**Risk:** Low to medium.

### Option 3: Leave As-Is Until Gas Measurement

**Approach:** Keep current clarity and only optimize if gas snapshots show material savings.

**Pros:**
- Avoids premature complexity.
- Current code is straightforward.

**Cons:**
- Known extra gas remains on V4 routes.

**Effort:** Small.

**Risk:** Low.

## Recommended Action

Start with Option 3's measurement gate, then apply Option 2 only if the gas savings justify the added adapter surface. Measure at least one generated V4-heavy route before and after any change. Preserve current hook-data allowlist semantics and Universal Router V4 tests.

## Technical Details

Affected files:

- `src/FameRouter.sol`
- `src/router/adapters/UniversalRouterAdapter.sol`
- `test/router/FameRouter.t.sol`
- optional gas snapshot/benchmark tests

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- Performance reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/performance.json`

## Acceptance Criteria

- [x] V4 payload decode happens once per V4 leg, or gas measurement justifies keeping the current code.
- [x] Existing V4 hook-data allowlist behavior remains covered.
- [x] Existing Universal Router V4 execution tests pass.
- [x] If optimized, before/after gas impact is measured on at least one V4-heavy route.

## Work Log

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review finding #10.

**Learnings:**
- This is a hot-path optimization, but it should be balanced against adapter/API complexity.

### 2026-05-15 - V4 Payload Decode Shared

**By:** Codex

**Actions:**
- Added a V4 decode helper that returns the decoded payload and hook-data key in one pass.
- Kept the hook-data allowlist decision in `FameRouter` and passed the decoded payload into the execution helper.

**Verification:**
- Before gas: `test_UniversalRouterAcceptsAllowedV4HookData` 378,986; `test_V4Permit2ApprovalIsClearedAfterSuccessfulUniversalRouterRoute` 339,217.
- After gas: `test_UniversalRouterAcceptsAllowedV4HookData` 376,876; `test_V4Permit2ApprovalIsClearedAfterSuccessfulUniversalRouterRoute` 337,510.
- `forge test --match-path test/router/FameRouter.t.sol`
