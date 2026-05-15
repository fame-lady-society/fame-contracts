# Review Synthesis

Scope: `feat/fame-multi-leg-router` against `origin/main` merge-base `1f6086a8570c33d9a54a43abcbec9f0b17bd389a`.

Intent: Add FAME multi-leg router support, native WETH wrap/unwrap route legs, Aerodrome V2 explicit-factory routing, router-ts artifact/materialization support, deployment/public-config hygiene, and supporting docs/artifacts.

Verdict: Not ready. No raw secrets were found in the branch, but several P2 issues should be resolved or explicitly accepted before PR merge.

## Findings

| Severity | File | Issue | Reviewers | Route |
| --- | --- | --- | --- | --- |
| P2 | `router-ts/src/artifacts/schema.ts:162` | JSON route conversion accepts unknown enum names when the ordinal is omitted because `VenueFamily[bad]` and `venueOrdinal` can both be `undefined`. | api-contract, kieran-typescript | gated_auto -> review-fixer |
| P2 | `router-ts/src/materializeRoute.ts:153` | Production materialization silently converts any non-input `Exact` leg to `All`, which can consume intermediate assets intended for later legs. | api-contract, adversarial | manual -> downstream-resolver |
| P2 | `src/FameRouter.sol:302` | V4 hook governance only applies to non-empty `hookData`; hooked pools with empty hookData bypass the hook-key allowlist once the Universal Router target is enabled. | security, security-audit | manual -> downstream-resolver |
| P2 | `script/DeployFameRouter.s.sol:20` | Base deployment can broadcast Base venue targets on the wrong chain because `run()` does not assert `block.chainid == BASE_CHAIN_ID` before `vm.startBroadcast`. | correctness, reliability | manual -> downstream-resolver |
| P2 | `src/FameRouter.sol:359` | Native ETH leftovers refund to `msg.sender`, so otherwise successful routes can revert for non-payable contract callers. | correctness, adversarial, reliability, security-audit | manual -> downstream-resolver |
| P2 | `test/router/fixtures/base-v1-solver-routes.json:57` | Fork-evidence artifacts still expose submit-able calldata with year-2100 deadlines and one-wei minimums; consumers must not treat them as production calldata. | adversarial, reliability | manual -> human |
| P2 | `script/ValidateFameRouterBase.s.sol:68` | Live validation checks pool metadata, not current executable route success, so stale routes can pass release validation. | adversarial, reliability | manual -> release |
| P2 | `broadcast/DeployFameRouter.s.sol/8453/run-latest.json:1` | Mainnet broadcast artifacts are checked in. No secrets were found, but they publish operational transaction metadata and should be intentionally retained or removed. | maintainability | manual -> release-engineering |
| P2 | `test/router/FameRouterDeploymentValidation.t.sol:21` | Deploy script test does not assert required manifest target/family configuration on the deployed router. | testing | gated_auto -> review-fixer |
| P2 | `src/FameRouter.sol:302` | V4 legs decode the Universal Router payload twice on the hot path. | performance | gated_auto -> review-fixer |

## P3 / Advisory

- `router-ts/src/materializeRoute.ts:126`: add rejection tests for expired deadlines, nonzero NativeWrap mins, and zero swap mins.
- `router-ts/src/materializeRoute.ts:195`: remove the broad payload ABI cast or add venue-specific deadline patch helpers/tests.
- `config/fame-public.env:3`: add an automated public-config secret-safety assertion.
- `README.md:54`: clarify no-secret local tests vs Doppler-backed fork gates.
- `.context/compound-engineering/ce-review/**`: decide whether historical review artifacts belong in the product branch.
- `router-ts/src/compiler/types.ts:3`: schema remains manually mirrored across Solidity, TS, docs, and fixtures.

## Secrets

Secret scan passed for changed branch content. Reviewers and local scans found no committed raw RPC URLs, private keys, API keys, mnemonics, bearer tokens, or password literals. Broadcast artifacts contain public transaction metadata only.

## Coverage

Reviewers: correctness, security, adversarial, testing, maintainability, project-standards, api-contract, reliability, performance, kieran-typescript, dedicated security audit.

No implementation fixes were applied during this review. Tests were not run as part of the review beyond read-only/static inspection; rely on the earlier verification runs or rerun targeted tests after fixes.
