---
status: complete
priority: p3
issue_id: "006"
tags: [router, gas, accounting]
dependencies: []
---

# Consider Memory-Safe Router BalanceOf Helper

## Problem Statement

`FameRouter` now fails closed on malformed ERC-20 `balanceOf` responses, but the helper still uses high-level `staticcall` return decoding. The follow-up cleanup plan suggested a memory-safe assembly helper after fail-closed malformed-token tests were in place.

## Findings

- `BalanceReadFailed` now covers reverted and short-return `balanceOf` calls.
- Tests cover both malformed token cases before input is pulled.
- The high-level helper is easy to audit and currently not a launch blocker.
- A memory-safe assembly replacement could reduce gas but would increase low-level implementation risk.

## Proposed Solutions

### Option 1: Replace With Memory-Safe Assembly

**Approach:** Implement `balanceOf(address)` staticcall using memory-safe assembly and require exactly one 32-byte return word.

**Pros:**
- Potentially lower gas in balance-heavy routes.
- Keeps fail-closed semantics.

**Cons:**
- Low-level code is easier to get subtly wrong.

**Effort:** 1-2 hours

**Risk:** Medium

### Option 2: Keep High-Level Helper

**Approach:** Keep the current helper until gas pressure from live fixture routes justifies the added complexity.

**Pros:**
- Clearer audit surface.
- Existing malformed-token tests already protect the behavior.

**Cons:**
- May be slightly more expensive.

**Effort:** 0 hours

**Risk:** Low

## Recommended Action

Closed for the current router launch goal. Keep the high-level fail-closed helper because it is clear, covered, and not a launch-blocking gas issue.

## Acceptance Criteria

- [ ] Reverted, short-return, and valid `balanceOf` cases remain covered.
- [ ] Any assembly implementation preserves exact fail-closed semantics.
- [ ] Gas is compared against the high-level helper baseline.

## Work Log

### 2026-05-12 - Closure

**By:** Codex

**Actions:**
- Rechecked malformed balance read coverage and router size.
- Deferred the assembly rewrite to avoid adding low-level risk without demonstrated gas pressure.

**Learnings:**
- The high-level helper is the better launch default while malformed-token coverage is already in place.

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Deferred assembly conversion after malformed-token tests passed.
- Recorded the item as lower-priority cleanup because the current helper is safer to audit.

**Learnings:**
- Correct fail-closed behavior matters more than the helper implementation style for launch readiness.
