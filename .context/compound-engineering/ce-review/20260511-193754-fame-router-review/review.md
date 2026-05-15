# ce-review: FAME Multi-Leg Router

Plan: `docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md`
Mode: interactive
Scope: dirty working tree including untracked router files

## Applied Safe Fixes

- Updated `test/router/FameRouter.t.sol` so the route helper preserves the exact `minAmountOut` argument instead of collapsing every nonzero leg minimum to `1`.

## Findings

| Severity | File | Issue | Route |
|---|---|---|---|
| P1 | `src/router/adapters/SolidlyRouterAdapter.sol:17` | Venue adapters are generic `IRouterLegExecutor.executeLeg` trampolines instead of typed Solidly/V2/Slipstream/Universal Router integrations. Real Base routers will not satisfy this interface, and wrapper targets would reintroduce an arbitrary-call style custody surface. | manual -> downstream-resolver |
| P1 | `src/router/adapters/UniversalRouterAdapter.sol:19` | Universal Router/V4 protection is only a selector-prefix rejection; structured V3/V4 commands, Permit2, PoolKey, hooks, hook data, payer, recipient, wrap/unwrap, and unsupported command policy are not implemented. | manual -> downstream-resolver |
| P1 | `test/router/fixtures/base-v1-routes.json:5` | Frozen route fixtures are empty, so no supported FAME route is fork-executed, including FAME <-> ETH/WETH/USDC, long routes, split routes, or split-then-merge routes. | manual -> downstream-resolver |
| P1 | `script/ValidateFameRouterBase.s.sol:37` | Live validation checks only basic router config, skip-NFT state, and `isLaunchable`; it does not verify pool metadata, route execution/simulation, enabled target parity, or `www` schema/snapshot parity. | manual -> downstream-resolver |
| P2 | `src/FameRouter.sol:111` | If `route.recipient` or `feeRecipient` is the router itself, self-transfers remain route-local and are later refunded to `msg.sender`, bypassing the intended recipient or fee collection. | gated_auto -> downstream-resolver |
| P2 | `src/FameRouter.sol:241` | Settlement snapshots only declared route assets; undeclared refunds or hook outputs can become stranded/rescueable value unless adapters make those outputs impossible or the schema declares refund assets. | manual -> downstream-resolver |
| P2 | `test/router/FameRouterForkBase.t.sol:15` | The fork harness falls back to latest Base when the manifest block is zero, so it is a smoke test rather than pinned launch evidence. | manual -> downstream-resolver |
| P2 | `test/router/FameRouterForkBase.t.sol:16` | A failed fork creation can print the full provider URL from `BASE_RPC`; network fork tests need explicit gating/masking or a redacted validation path. | gated_auto -> downstream-resolver |
| P2 | `script/DeployFameRouter.s.sol:15` | Deployment only constructs the router; it does not assert Base chain ID, configure venue families/targets, or gate ownership transfer on validation artifacts. | gated_auto -> downstream-resolver |

## Requirements Completeness

- Unit 1: partial. Pending manifest files and Base config exist, but the manifest has zero pools/routes and no pinned launch block.
- Unit 2: partial. Core custody, fee, native ETH, route-local accounting, and mock tests exist, but recipient self-address and undeclared refund edge cases remain.
- Units 3-5: not launch-complete. Real Solidly/V2/Slipstream/Universal Router adapters are not implemented.
- Unit 6: not addressed. No all-pools/all-routes fork matrix exists.
- Unit 7: partial. Some custody/ambient-balance tests exist; reentrancy, Permit2, V4 hooks, wrong recipient/payer, rescue, skip-NFT, and failed fork-swap invariants are missing.
- Unit 8: partial. Deployment and validation stubs/docs exist, but live validation and `www` parity are not machine-enforced.

## Verification

- `forge test --match-path 'test/router/FameRouter*'`: 30 passed with network access for the Base fork smoke test.
- The same combined command failed inside the sandbox before escalation because DNS/network access was blocked; the targeted network rerun passed.

## Verdict

Not ready for release. The mock-backed core is a useful skeleton, but production venue execution, frozen fixtures, route-matrix fork coverage, live validation, and release gating remain launch blockers.
