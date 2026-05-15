# ce-review: FAME Multi-Leg Router Autofix

Plan: `docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md`
Mode: `autofix`
Date: 2026-05-11

## Applied Safe Fixes

- Enforced leg minimums using actual router balance deltas, not venue-reported output.
- Added route validation for unsupported same-asset routes and final output consumed by later legs.
- Added router tests for `AmountMode.All`, fractional `BalanceBps`, ambient-balance isolation, native ETH output settlement, schema validation failures, disabled venue targets, final output consumption, same-asset rejection, and lying venue output.
- Updated fixture manifest pending counts to match checked-in pending pool and route fixtures.
- Updated release docs to use the Foundry `base` RPC endpoint alias under Doppler.
- Clarified that `script/ValidateFameRouterBase.s.sol` is currently a config/manifest guard and must be expanded before it satisfies full live route validation.
- Removed unused `ReentrantToken` mock from this implementation slice.

## Residual Manual Findings

- Real venue adapters are not implemented yet. Current adapter libraries use the `IRouterLegExecutor` test/scaffold boundary and are not production-ready typed Solidly, Uniswap V2, Slipstream, or Universal Router integrations.
- Universal Router V3/V4 command construction and PoolKey/hook validation remain manual future work tied to the frozen fixture snapshot.
- Deployment currently deploys the router but does not configure production venue families and targets from a manifest.
- Full live Base validation still needs pool metadata checks, route execution or simulation, deployed skip-NFT confirmation, and `www` schema/fixture parity once the snapshot is available.

## Verification

- `forge test --match-path 'test/router/*.t.sol'`: 29 passed, 1 skipped in the plain environment.
- `doppler run -- forge test --match-path test/router/FameRouterForkBase.t.sol`: 1 passed with network access.
- `forge test`: 105 passed, 16 failed, 1 skipped. Failures are in pre-existing non-router suites (`FameLauncher`, `FairReveal`, `FairPoolReveal`, `SimpleOffchainReveal`).
