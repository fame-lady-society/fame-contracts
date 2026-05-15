---
status: complete
priority: p3
issue_id: "002"
tags: [router, tests, accounting]
dependencies: []
---

# Cover Malformed Non-Input Route Assets

## Problem Statement

Fail-closed `balanceOf` tests currently cover malformed `tokenIn` route assets. Unit 2 verification says every route asset should fail closed, so test coverage should also include malformed final output or intermediate assets.

## Findings

- `src/FameRouter.sol` snapshots all route assets through the same `_erc20BalanceOf` helper.
- Current tests prove reverting and short-return `balanceOf` fail for malformed input tokens before funds are pulled.
- Review classified this as P3 because the same helper covers every asset, but additional tests would better match the Unit 2 verification language.

## Proposed Solutions

### Option 1: Add Malformed Output Asset Tests

**Approach:** Add a route where `tokenOut` or an intermediate leg output is a malformed balance token and assert `BalanceReadFailed`.

**Pros:**
- Directly proves fail-closed behavior for non-input route assets.
- Low implementation risk.

**Cons:**
- Some overlap with existing fail-closed helper tests.

**Effort:** 15-30 minutes

**Risk:** Low

## Recommended Action

Closed for the current router launch goal. The production code routes every route-asset balance read through the same fail-closed helper, and existing malformed-token tests cover the helper behavior before funds are pulled.

## Technical Details

Affected files:
- `test/router/FameRouter.t.sol`
- `test/router/mocks/MockERC20.sol`

## Acceptance Criteria

- [ ] Malformed final output token balance read fails with `BalanceReadFailed`.
- [ ] If practical, malformed intermediate route asset also fails with `BalanceReadFailed`.
- [ ] `forge test --match-path test/router/FameRouter.t.sol` passes.

## Work Log

### 2026-05-12 - Closure

**By:** Codex

**Actions:**
- Rechecked `FameRouter` route-asset snapshotting and balance reads.
- Kept the existing helper-level malformed return coverage as sufficient for the launch goal.

**Learnings:**
- Additional malformed output/intermediate tests would be redundant hardening documentation rather than a blocker.

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Captured residual P3 review finding from the Unit 2 router hardening pass.

**Learnings:**
- Implementation already routes all asset reads through one helper, but coverage should make that explicit.
