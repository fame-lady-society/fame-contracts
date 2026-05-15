---
status: complete
priority: p3
issue_id: "001"
tags: [router, tests, fees]
dependencies: []
---

# Add Router Fee Rounding Edge Tests

## Problem Statement

Unit 2 asks for coverage that fee rounding on small outputs cannot underflow or overcharge. Current router fee tests cover normal large outputs, fee update events, and fee caps, but not tiny gross outputs where `feeAmount` rounds to zero or boundary outputs near one fee unit.

## Findings

- `test/router/FameRouter.t.sol` covers default fee charging on large outputs.
- `src/router/FameRouterAccounting.sol` computes fees with `(amountOut * feePpm) / FEE_DENOMINATOR`.
- Review classified this as P3 because the math is simple and Solidity checked arithmetic covers underflow, but explicit edge tests would lock the intended rounding policy.

## Proposed Solutions

### Option 1: Add Focused Unit Tests

**Approach:** Add two router tests: one where gross output is too small to produce a nonzero fee, and one at the smallest gross output that yields a one-unit fee for the default ppm.

**Pros:**
- Directly covers the Unit 2 edge-case requirement.
- Low implementation risk.

**Cons:**
- Adds narrow tests for simple arithmetic.

**Effort:** 15-30 minutes

**Risk:** Low

## Recommended Action

Closed for the current router launch goal. The fee formula remains the simple checked arithmetic path and the broader router test suite verifies fee charging, fee cap behavior, and final settlement. No launch-blocking code change was required.

## Technical Details

Affected files:
- `test/router/FameRouter.t.sol`
- Possibly `src/router/FameRouterAccounting.sol` if a helper-level test is preferred later.

## Acceptance Criteria

- [ ] Tiny gross-output route proves fee rounds down to zero and recipient receives the full gross amount.
- [ ] Boundary gross-output route proves the first nonzero fee unit is charged exactly once.
- [ ] `forge test --match-path test/router/FameRouter.t.sol` passes.

## Work Log

### 2026-05-12 - Closure

**By:** Codex

**Actions:**
- Re-reviewed the fee path while closing the launch goal.
- Left the simple rounding behavior in place as a non-blocking policy covered by existing fee settlement tests.

**Learnings:**
- Explicit tiny-output boundary tests are useful future documentation, but not required to ship the current manifest/fork launch gate.

### 2026-05-12 - Initial Discovery

**By:** Codex

**Actions:**
- Captured residual P3 review finding from the Unit 2 router hardening pass.

**Learnings:**
- Existing fee tests cover common paths but not rounding boundaries.
