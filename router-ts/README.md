# FAME Router TypeScript Reference

`router-ts` is a small Bun/viem reference implementation for compiling known Base pool config into exact `FameRouterTypes.Route` artifacts. It is intentionally deterministic: it does not discover pools, rank prices, or call RPC during pure tests.

## Commands

Run from the repository root:

```sh
bun run router:verify
bun run router:generate
bun run router:generate:check
```

`router:verify` typechecks the compiler, runs pure Bun tests, and verifies checked-in generated artifacts are current. Pure tests must not require `BASE_RPC`.

## Generated Artifacts

The generator reads `test/router/fixtures/base-v1-pools.json` and writes:

- `test/router/fixtures/base-v1-solver-routes.json`
- `test/router/fixtures/base-v1-route-gap-matrix.json`
- `test/router/fixtures/base-v1-route-parity-vectors.json`
- `test/router/fixtures/base-v1-creator-coin-catalog.json`
- `test/router/fixtures/FameRouterSolverFixtureManifest.sol`

Every generated route includes the exact route object, `abiEncodedRoute`, `routeHash`, funding metadata, and compact debug metadata. Foundry reconstructs the Solidity route from JSON, checks `keccak256(abiEncodedRoute) == routeHash`, checks reconstructed ABI/hash parity, and only then executes the route on a pinned Base fork.

Generated route artifacts are fork evidence, not production calldata. Consumers that need executable calldata must reject `productionExecutable: false` artifacts at the production boundary and run explicit materialization to set current recipient, deadline, minimums, and router-bound Universal Router recipients.

The creator-coin catalog is fixture-policy evidence, not launch evidence by itself. It records known ZORA creator-coin V4 pools such as basedflick/ZORA with their PoolKey metadata, hook address, explicit swap `hookData`, and evidence classification. basedflick/ZORA is currently hook-address V4 coverage with `hookData: "0x"`; it is not non-empty swap-hook-data proof.

## Scope

Supported output is limited to FAME-facing USDC, WETH, and ETH evidence over the known pool config. Unsupported or intentionally deferred directions stay visible in `base-v1-route-gap-matrix.json` with blocker reasons.

Native ETH routes use `address(0)` and remain distinct from WETH. Structured V4 payloads may encode `amountIn: 0` for router-computed dynamic amount modes such as `All`; the Solidity adapter substitutes the route-local amount selected by the router while still validating token endpoints, PoolKey metadata, minimums, recipient, payer mode, and hook data policy.

V4 hook data is supported only through the structured router payload and the router's hook-data allowlist. The contract allowlists the Universal Router target, not individual V4 pools; hooked pools with empty swap `hookData` rely on structured payload checks and the offchain pool universe. Raw Universal Router command payloads are still outside this schema.

Coverage flags separate related V4 concepts:

- `v4Hooks`: route uses V4 hook-aware metadata or execution policy.
- `v4HookAddress`: route proves a nonzero hook-address V4 pool.
- `v4NonEmptyHookData`: route proves non-empty ordinary V4 swap `hookData`.
- `v4MultiHopPathKeys`: route proves fleet-style V4 `PathKey[]` multi-hop encoding.

Do not treat Zora factory `postDeployHookData` as ordinary Universal Router V4 swap `hookData`.

## Fork Validation

Fork tests require a Base RPC secret and must not print it:

```sh
doppler run --config prd -- sh -c 'BASE_RPC="$RPC_URL" forge test --match-path test/router/FameRouterForkBase.t.sol --match-test test_PinnedBaseForkGeneratedSolverRouteTableExecutesEveryRoute'
```
