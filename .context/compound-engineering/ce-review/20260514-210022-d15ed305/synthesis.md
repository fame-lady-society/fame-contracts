# CE Review Synthesis

Scope: `feat/fame-multi-leg-router` against `1f6086a8570c33d9a54a43abcbec9f0b17bd389a`

Intent: add FameRouter multi-leg execution, generated route artifacts, native WETH wrap/unwrap legs, Aerodrome V2 explicit-factory support, deployment/validation scripts, and Base fixture coverage.

Mode: interactive

Reviewers: correctness, testing, maintainability, project-standards, security, API-contract, reliability, adversarial, performance, kieran-typescript, agent-native, learnings.

## Findings

### P1 -- High

| # | File | Issue | Reviewer(s) | Confidence | Route |
|---|---|---|---|---:|---|
| 1 | `router-ts/src/compiler/compileRoute.ts:35` | Generated Universal Router artifacts are bound to test executor `0x...f00d`, while production deployment uses a normal router address. Fork coverage deploys code to that address, so it proves artifact logic but not replay against `BASE_FAME_ROUTER_ADDRESS`. | correctness, agent-native | 0.98 | manual -> downstream-resolver, needs verification |
| 2 | `router-ts/src/compiler/compileRoute.ts:211` | Generated fork-evidence artifacts contain executable route objects, real Base targets, long deadlines, and one-wei minimums. Non-production evidence can be lifted into live swaps unless the artifact format or production compiler path makes that impossible. | adversarial | 0.86 | manual -> downstream-resolver, needs verification |

### P2 -- Moderate

| # | File | Issue | Reviewer(s) | Confidence | Route |
|---|---|---|---|---:|---|
| 3 | `test/router/FameRouterForkBase.t.sol:1315` | Focused launchable fork checks can skip when `BASE_RPC` is missing, so a targeted generated-route command can pass without exercising Base. | reliability, testing | 0.96 | manual -> downstream-resolver, needs verification |
| 4 | `src/FameRouter.sol:301` | V4 hook governance only checks non-empty `hookData`; nonzero hook addresses with empty hook data do not require a pool/hook key allowlist. | adversarial | 0.78 | manual -> downstream-resolver, needs verification |
| 5 | `script/DeployFameRouter.s.sol:20` | Base deploy script does not gate `block.chainid` before broadcasting. | correctness | 0.72 | manual -> downstream-resolver, needs verification |
| 6 | `src/FameRouter.sol:121` | A non-payable fee recipient would revert native-output routes when the fee is paid in ETH. | adversarial | 0.81 | manual -> downstream-resolver, needs verification |

### P3 -- Low

| # | File | Issue | Reviewer(s) | Confidence | Route |
|---|---|---|---|---:|---|
| 7 | `test/router/FameRouterDeploymentValidation.t.sol:69` | Deployment validator negative branches are under-covered for bad chain/config/pool metadata. | testing | 0.86 | manual -> downstream-resolver, needs verification |
| 8 | `router-ts/test/adapter-encoding.spec.ts:28` | Some adapter tests assert hex shape without decoding all behaviorally relevant fields. | testing | 0.84 | manual -> downstream-resolver, needs verification |
| 9 | `src/FameRouter.sol:237` | Route-local accounting repeatedly scans snapshots and rereads balances on the bounded hot path. | performance | 0.86 | manual -> downstream-resolver, needs verification |
| 10 | `src/FameRouter.sol:19` | `DEFAULT_FEE_RECIPIENT` duplicates the public config value in Solidity source. | project-standards | 0.86 | manual -> downstream-resolver |

## Advisory / Residual

- `FameRouterSolverFixtureManifest` currently has zero required V4 hook-data keys, so deploy not consuming solver hook keys is not a present deployment failure. Wire this before introducing non-empty V4 swap hook-data artifacts.
- Broadcast JSON and old CE review artifacts add branch noise, but deployment artifacts were intentionally recorded in this workflow.
- `candidateRoutes()` combines route catalog data and compiler control flow. It is manageable for the current static set, but it will become expensive if the route universe grows.
- `README.md` and validation docs should make the fork/live validation split and post-deploy validation command harder to miss.

## Learnings

- Relevant branch-local known pattern: `docs/solutions/workflow-issues/public-config-doppler-foundry-aliases-2026-05-12.md`.
- Public deployment constants belong in `config/fame-public.env`; RPC URLs, keys, mnemonics, and explorer keys stay in Doppler.
- Launchability should come from executable validation, fixture hashes, and pinned fork evidence, not manifest counts alone.

## Coverage

- Suppressed/downgraded: maintainability cleanup suggestions around protected planning artifacts and intended deployment artifacts were kept advisory rather than blockers.
- No untracked product files were excluded at scope discovery. This review created `.context/compound-engineering/ce-review/20260514-210022-d15ed305/` artifacts.
- RPC-backed fork tests were not rerun during review. Prior work reported provider timeouts followed by passing reruns for failed fork tests.
- Security and API-contract reviewers found no additional blocking issues.

## Verdict

Not ready to merge/release until P1 findings are resolved. P2 findings are not all launch blockers, but the focused-fork skip and V4 hook-boundary issue are worth fixing before relying on the generated route evidence as production proof.
