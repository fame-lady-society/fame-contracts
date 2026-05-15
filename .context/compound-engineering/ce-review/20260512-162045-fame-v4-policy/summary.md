---
mode: autofix
date: 2026-05-12
scope: current checkout diff against HEAD
plan: docs/plans/2026-05-12-003-feat-fame-v4-creator-coin-fixture-policy-plan.md
---

# CE Review: FAME V4 Creator-Coin Fixture Policy

## Review Team

- correctness
- testing
- TypeScript/API contract
- maintainability/project standards
- adversarial
- agent-native/learnings
- focused post-fix verification

## Findings Applied

- Added invariant tests that derive V4 hook coverage claims from decoded generated V4 payloads.
- Added invariant tests that gap-matrix rows mirror referenced route artifact capabilities.
- Added catalog route artifact links and tests that hook-address catalog proof points at generated fork-tested route artifacts.
- Renamed catalog `poolId` to `poolConfigId` and added canonical `v4PoolId`.
- Required structured production or local-harness proof before any catalog entry can claim `non-empty-approved` swap hook data.
- Added todo 008 to track the residual valid non-empty ordinary V4 swap-hook-data proof.
- Focused post-fix subagent re-review returned no findings.

## Verification

- `bun run router:verify`: passed.
- `forge test --match-path test/router/FameRouterGeneratedArtifacts.t.sol`: passed.
- `doppler run --config prd -- sh -c 'BASE_RPC="$RPC_URL" forge test --match-path test/router/FameRouterForkBase.t.sol --match-test test_PinnedBaseForkGeneratedSolverRouteTableExecutesEveryRoute -vv'`: passed with network access enabled.

## Residual Notes

- The catalog is deterministic fixture-policy evidence sourced from committed config and pinned fork validation. It is not open-ended live pool discovery.
- Production non-empty V4 swap-hook-data proof remains intentionally separate in `.context/compound-engineering/todos/008-pending-p2-prove-valid-non-empty-v4-swap-hook-data.md`.
