# Learnings Research

Base: `1f6086a8570c33d9a54a43abcbec9f0b17bd389a`

Scope reviewed: public config + Doppler, Foundry aliases, deployment validation, generated artifacts, router/fork testing.

## Search Summary

- Searched `docs/solutions/` for `public-config`, `doppler`, `foundry`, `rpc-aliases`, `deploy`, `deployment`, `validation`, `artifact`, `generated`, `router`, `fork`, `fixture`, and `broadcast`.
- Relevant solution match: [docs/solutions/workflow-issues/public-config-doppler-foundry-aliases-2026-05-12.md](/home/user/Development/fame-contracts/docs/solutions/workflow-issues/public-config-doppler-foundry-aliases-2026-05-12.md:1).
- `docs/solutions/patterns/critical-patterns.md` is not present in this repo.
- `docs/solutions/` has no files at the base commit, so the available solution note is branch-local rather than older base history.

## Known-Pattern Notes

1. Public config and Doppler split
   - Pattern: keep public chain IDs and contract addresses in [config/fame-public.env](/home/user/Development/fame-contracts/config/fame-public.env:1); keep RPC URLs, explorer keys, private keys, mnemonics, upload keys, and snipe keys in Doppler.
   - Branch relevance: the branch adds public router constants including `BASE_FAME_ROUTER_FEE_RECIPIENT`, `BASE_FAME_ROUTER_FEE_PPM`, fixture hash, and router address in [config/fame-public.env](/home/user/Development/fame-contracts/config/fame-public.env:38). Deployment scripts read secrets and public env separately, e.g. `BASE_DEPLOYER_PRIVATE_KEY` plus public router config in [script/DeployFameRouter.s.sol](/home/user/Development/fame-contracts/script/DeployFameRouter.s.sol:14).
   - Review implication: verify all new deployment docs and committed artifacts avoid raw RPC URLs, private keys, mnemonics, and explorer keys.

2. Foundry aliases for fork/deploy commands
   - Pattern: prefer Foundry aliases from [foundry.toml](/home/user/Development/fame-contracts/foundry.toml:20) over raw RPC URLs; run secret-bearing commands through Doppler.
   - Branch relevance: README examples now document `--rpc-url base` and Doppler execution in [README.md](/home/user/Development/fame-contracts/README.md:24), with deploy command at [README.md](/home/user/Development/fame-contracts/README.md:86).
   - Review implication: any remaining docs that still export `$RPC` or pass raw URLs should be treated as legacy surfaces unless intentionally preserved.

3. Deployment validation should be executable, not only documented
   - Pattern from the solution note: command examples are copied directly into terminals, so validation gates should be explicit, reproducible, and tied to public config plus Doppler.
   - Branch relevance: [script/ValidateFameRouterBase.s.sol](/home/user/Development/fame-contracts/script/ValidateFameRouterBase.s.sol:57) checks configured router address, chain ID, fee recipient, fee ppm, optional owner, required venue targets, fixture parity, skip-NFT status, manifest launchability, and live Base pool metadata.
   - Review implication: deployment approval should require this validator after sourcing `config/fame-public.env` and running through Doppler with `--rpc-url base`.

4. Generated router artifacts need reproducibility guards
   - No prior `docs/solutions/` entry was found for generated router artifacts specifically.
   - Branch-local pattern: generated JSON and Solidity manifest files are produced by [router-ts/src/artifacts/writeArtifacts.ts](/home/user/Development/fame-contracts/router-ts/src/artifacts/writeArtifacts.ts:213), checked with `--check` at [router-ts/src/artifacts/writeArtifacts.ts](/home/user/Development/fame-contracts/router-ts/src/artifacts/writeArtifacts.ts:216), and exposed through root scripts in [package.json](/home/user/Development/fame-contracts/package.json:13).
   - Branch-local guards: Solidity tests hash checked-in fixture JSON and verify ABI route parity in [test/router/FameRouterGeneratedArtifacts.t.sol](/home/user/Development/fame-contracts/test/router/FameRouterGeneratedArtifacts.t.sol:15) and [test/router/FameRouterFixtureCoverage.t.sol](/home/user/Development/fame-contracts/test/router/FameRouterFixtureCoverage.t.sol:39).
   - Review implication: require `router:generate:check` or equivalent before accepting changes to `test/router/fixtures/*.json` or `FameRouterSolverFixtureManifest.sol`. Also scrutinize committed [broadcast/DeployFameRouter.s.sol/8453/run-latest.json](/home/user/Development/fame-contracts/broadcast/DeployFameRouter.s.sol/8453/run-latest.json:1) and prior `.context` review artifacts as intentional generated outputs, not accidental churn.

5. Router fork tests should pin chain state and degrade clearly without secrets
   - No older `docs/solutions/` match was found for router/fork testing beyond the Doppler + Foundry alias guidance.
   - Branch-local pattern: launchable fork coverage pins Base block `45_884_844` in [test/router/fixtures/FameRouterFixtureManifest.sol](/home/user/Development/fame-contracts/test/router/fixtures/FameRouterFixtureManifest.sol:7), hard-fails the launch gate when `BASE_RPC` is absent in [test/router/FameRouterForkBase.t.sol](/home/user/Development/fame-contracts/test/router/FameRouterForkBase.t.sol:77), and skips non-gate fork tests without `BASE_RPC` in [test/router/FameRouterForkBase.t.sol](/home/user/Development/fame-contracts/test/router/FameRouterForkBase.t.sol:1314).
   - Branch-local guard: [foundry.toml](/home/user/Development/fame-contracts/foundry.toml:6) limits filesystem reads to `./test/router/fixtures`, matching the fixture-driven tests and validation script.
   - Review implication: preserve the distinction between launch gates that must fail without `BASE_RPC` and ordinary fork tests that can skip in local/no-secret environments.

