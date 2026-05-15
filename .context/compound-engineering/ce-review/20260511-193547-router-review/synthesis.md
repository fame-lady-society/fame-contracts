# ce-review synthesis: FAME Multi-Leg Router

Mode: interactive
Plan: docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md
Run: 20260511-193547-router-review

## Scope

- Branch: feat/fame-multi-leg-router
- Base: 1f6086a8570c33d9a54a43abcbec9f0b17bd389a
- Tracked dirty files: docs/fame-release-plan.md, foundry.toml
- Explicitly included untracked files: src/FameRouter.sol, src/router/**, test/router/**, script/DeployFameRouter.s.sol, script/ValidateFameRouterBase.s.sol, docs/router/**, fixture JSON, foundry.lock

## Applied Safe Fix

- Removed the unused `route` parameter and no-op `route;` statement from `_executeLeg` in src/FameRouter.sol.

## Merged Findings

### P1

1. Current venue adapters are scaffold hooks, not constrained production venue integrations.
2. Launch validation can pass without proving JSON fixture parity, venue enablement, pool metadata, or route execution.
3. The Base fork/fixture harness does not execute launch-blocking routes or validate pools.
4. `_erc20BalanceOf` silently returns zero on failed or malformed balance reads.

### P2

1. `minAmountOutAfterFee` is checked before settlement, so fee-on-transfer or malicious final tokens can under-deliver.
2. Native ETH leftovers are always refunded to `msg.sender`, which can revert successful contract-sender routes.
3. The schema lacks canonical enum ordinals and amount-mode wire details.
4. Route-local accounting repeatedly scans snapshots on the per-leg hot path.
5. Deployment leaves venue families and targets unconfigured, and validation does not catch that.

### P3

1. `RouteExecuted` omits a route hash or version/input identity for client parity.
2. `weth` is configured but unused, making native/WETH support look more complete than it is.
3. Approval clearing policy is secure but expensive; batching/last-use clearing needs an explicit decision.
4. Unknown or future venue enum handling falls through to the Universal Router branch.
5. The ERC20 balance helper can be optimized with memory-safe assembly once fail-closed semantics are chosen.

## Requirements Completeness

- R1-R6/R34-R35: partially met. Core exact-input custody, fee, and route-local delta tests exist; typed production venue execution does not.
- R7-R12/R36-R38: not launch-ready. Fixture files are placeholders and no production route/pool executes on a pinned fork.
- R13-R18: mostly met for core fee/governance; deployment does not configure production venues.
- R19-R26/R39-R42: partially met. Core accounting/reentrancy/rescue shape exists; arbitrary wrapper target, Universal Router/V4, FAME DN404, and ERC20 edge cases remain incomplete.
- R27-R33/R43-R47: partially met. Base config and docs exist; live validation and `www` parity are not implemented.

## Verification

- `forge build`: passed with existing warnings.
- `forge test --match-path test/router/FameRouter.t.sol`: 27 passed.
- `forge test --match-path 'test/router/*.t.sol'` with network access: 30 passed.

## Verdict

Not ready. The core scaffold is promising, but production readiness is blocked on typed adapters, full fixture/fork validation, and hardening around route-local accounting and settlement edge cases.
