# FAME Router Validation

## Launch Gate

The router is v1-launchable only when the frozen Base fixture snapshot is filled in and every launch-blocking pool and directional route has passing pinned-fork validation. The current manifest records a launchable snapshot:

- `test/router/fixtures/base-v1-pools.json`
- `test/router/fixtures/base-v1-routes.json`
- `test/router/fixtures/FameRouterFixtureManifest.sol`

`FameRouterFixtureManifest.isLaunchable()` returns true only when the pinned block is nonzero, both fixture files are nonempty, metadata and route-execution coverage match fixture counts, required venue targets are present, and there are zero pending launch-blocking fixtures.

## Fixture Freeze Checklist

1. Export the final `www` production route graph for the v1 FAME universe.
2. Choose one pinned Base block with executable liquidity for every fixture route.
3. Fill pool fixtures with venue family, pool/factory/router identity, token ordering, stable flags, fee or tick spacing, PoolKey fields, hook address, and hook-data boundary rules.
4. Fill route fixtures with direction, amount, funding source, expected input/output asset identity, pool fixture IDs, and post-fee minimum policy.
5. Replace pending counts in `FameRouterFixtureManifest` with deterministic manifest counts and update the JSON content hashes. Fixture coverage tests compare `base-v1-pools.json` and `base-v1-routes.json` directly against the Solidity manifest, so editing fixture JSON without updating the manifest fails locally.
6. Set the same nonzero pinned Base block in both JSON fixture files and `FameRouterFixtureManifest`. The manifest snapshot hash includes the pinned block plus both fixture file hashes.
7. Fill metadata and route-execution coverage tables in `FameRouterFixtureManifest`. `isLaunchable()` must remain false while the pinned block is zero, while either fixture file is empty, while metadata/execution coverage counts do not match fixture counts, or while any launch-blocking fixture remains pending.
8. Run pinned fork tests with `BASE_RPC` available. When the manifest is launchable, missing `BASE_RPC` is a release-blocking failure; local skip behavior is only allowed while the checked-in manifest is still pending.
9. Deploy with `script/DeployFameRouter.s.sol`. Deployment checks `BASE_CHAIN_ID` before reading the deployer key or broadcasting, reads public router settings from `config/fame-public.env`, deploys with the expected fee recipient, enables every manifest-required venue family/target, and transfers ownership to `BASE_FAME_ROUTER_OWNER` when it is set. If `BASE_FAME_ROUTER_OWNER` is unset, deployment leaves ownership with the deployer address derived from `BASE_DEPLOYER_PRIVATE_KEY`. Do not set the owner to `BASE_MULTISIG_ADDRESS` until the go/no-go checklist passes.
10. Run live predeployment validation against current Base state before deployment. `script/ValidateFameRouterBase.s.sol` checks router chain ID/address, fee recipient, fee ppm, optional owner, every manifest-required venue family/target, deployed `Fame.getSkipNFT(router)`, schema version, fixture snapshot hash, manifest launchability, and current Base pool metadata. Route execution evidence is provided by the populated pinned-fork manifest coverage gate.

## Solver Artifact Workflow

The launch manifest is the stable fixture gate for production venue allowlisting. The TypeScript solver adds a second evidence layer for composed, split, split-then-merge, NativeWrap, and Aerodrome V2 proof FAME routes without promoting every generated solver route into the launch manifest by default.

Aerodrome V2 explicit-factory support uses venue ordinal `7`. Its fixture evidence must prove the Aerodrome router target, default factory, factory-derived pool identity, pool `factory()`, token ordering, stable flag, and factory fee. It is intentionally not encoded through the three-field `Solidly` payload.

Run pure generation checks without RPC:

```sh
bun run router:verify
```

The generator reads `test/router/fixtures/base-v1-pools.json` and emits deterministic artifacts:

- `test/router/fixtures/base-v1-solver-routes.json`
- `test/router/fixtures/base-v1-route-gap-matrix.json`
- `test/router/fixtures/base-v1-route-parity-vectors.json`
- `test/router/fixtures/FameRouterSolverFixtureManifest.sol`

Generated fork tests must treat TypeScript output as the source of truth. Before executing a route, Foundry checks `keccak256(abiEncodedRoute) == routeHash` and reconstructed Solidity `abi.encode(route)` parity against the artifact. The fork helper enables only venue targets from `FameRouterSolverFixtureManifest`, then asserts every generated leg target is on that allowlist before swap execution.

The gap matrix records every required FAME<->USDC/WETH/ETH direction with separate support, artifact, fork evidence, capability flags, and blocker reasons. Native ETH, WETH, and `nativeWrap` evidence are distinct. A route artifact that uses `NativeWrap` must expose `capabilities.nativeWrap = true`; downstream schema v1 consumers should gate on that capability rather than assuming every schema v1 consumer understands venue ordinal `6`. A route artifact that uses Aerodrome V2 must encode venue ordinal `7` and a four-field `{ from, to, stable, factory }` route payload.

NativeWrap solver evidence is separate from deployment authority. `FameRouterSolverFixtureManifest` proves artifact executability and supplies the targets needed by generated fork tests. Production deployments use `FameRouterFixtureManifest`, which includes `NativeWrap/WETH` in the same launch/deployment allowlist path as the swap venues. The canonical Base WETH target is the public `BASE_WETH_ADDRESS` value in `config/fame-public.env`; it must not be replaced by a secret or a dynamically discovered wrapper.

The app-side solver must keep native ETH/WETH restrictions until this contract repo has all of the following evidence:

- Contract unit tests for NativeWrap validation, amount modes, approval bypass, route-local accounting, and native settlement failure paths.
- TypeScript encoding/parity checks for `NativeWrap = 6`, empty payloads, `minAmountOut = 0`, and deterministic route hashes.
- TypeScript encoding/parity checks for `AerodromeV2 = 7`, explicit factory route payloads, and deterministic route hashes.
- Required NativeWrap/WETH target evidence in generated artifacts.
- Pinned Base fork execution of both `ETH -> WETH -> FAME` and `FAME -> WETH -> ETH`, including canonical WETH address/code and deposit/withdraw behavior.

The v1 onchain V4 trust boundary is target-level Universal Router allowlisting plus structured payload validation. Non-empty V4 swap `hookData` is valid only for configured hook metadata and router-approved hook-data hashes. Hooked pools with empty swap `hookData`, such as the current basedflick/ZORA evidence, do not need a hook-data hash entry; pool-universe selection and whether to surface those routes remains an offchain solver policy. Raw Universal Router command payloads remain outside schema version `1`.

## RPC Handling

Use Doppler or the local secret manager to provide `BASE_RPC` without printing it:

```sh
doppler run --config prd -- sh -c 'BASE_RPC="$RPC_URL" forge test --match-path test/router/FameRouterForkBase.t.sol'
```

Do not echo RPC values, private keys, or Basescan keys in logs.

Do not commit Foundry `broadcast/` output. Curate public deployment facts, such as deployed router addresses, in config/docs instead of relying on generated transaction logs.

## Script Commands

Load public config first, then run through Doppler for secrets:

```sh
set -a
source config/fame-public.env
set +a
doppler run -- forge script --chain base script/DeployFameRouter.s.sol:DeployFameRouter --verify --broadcast --rpc-url base
doppler run -- forge script --chain base script/ValidateFameRouterBase.s.sol:ValidateFameRouterBase --rpc-url base
```

## Go / No-Go

Go requires all of the following:

- Local router unit tests pass.
- Router-targeted bytecode size check passes, e.g. `forge build --sizes src/FameRouter.sol`.
- Pinned Base fork fixture tests pass for every pool and route in the frozen manifest.
- Fresh live validation confirms current Base pool metadata still matches the frozen snapshot.
- Deployed router has `Fame.getSkipNFT(router) == true`.
- `www` submits schema-compatible routes, displays post-fee minimums from contract fee parameters, and keeps fixture parity with the contract manifest.
- NativeWrap app enablement remains blocked until the solver evidence gate above is green and live validation confirms canonical WETH is enabled for `NativeWrap`.
- Aerodrome V2 app enablement remains blocked until `www` understands venue ordinal `7`, emits the explicit factory payload, and points at the deployed router containing this venue.
- Ownership transfer to the Base multisig is performed only after contract and `www` validation both pass.
