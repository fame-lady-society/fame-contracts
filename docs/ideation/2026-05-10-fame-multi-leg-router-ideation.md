---
date: 2026-05-10
topic: fame-multi-leg-router
focus: multi-leg router for fame
status: draft
handoff: contracts review
---

# Ideation: Multi-Leg Router for FAME

## Codebase Context

The `fame-contracts` repo is a Foundry Solidity project with Solady ownership and transfer helpers already used across core contracts. It vendors OpenZeppelin 4/5, Solady, Uniswap V2 core, Uniswap V3 core/periphery, and swap-router interfaces. Existing tests are Foundry-native, with prior fork-test usage documented around Sepolia/Base deployment flows.

The `www` repo now has a live FAME quote and simulation layer that proved direct Uniswap V2 and Scale/Equalizer V2 execution on Base. It also has a live advanced-path validator for Aerodrome Slipstream, Uniswap V3, and Uniswap V4 paths. The route graph can generate candidate multi-hop and split routes, but the public routers are protocol-family scoped: Universal Router can handle Uniswap V3/V4 paths, Scale/Equalizer handles Scale paths, Aerodrome V2 handles Aerodrome V2 paths, and Aerodrome Slipstream uses its own router/quoter. No single public router gives us one FAME-specific, fee-taking, balance-checked execution surface across all of these pools.

The new contract should therefore be treated as a settlement/executor layer for routes selected offchain. It should not try to rediscover best routes onchain or reproduce the frontend's full route-quality checks. The route search remains in `www`; the contract proves the onchain invariants that matter for custody and settlement: the submitted route either executes or reverts, slippage constraints hold, the FAME community fee is charged exactly once, and no user funds are stranded.

Fixed product constraints from the request:

- Goal: `multi-leg router for fame`.
- Chain target: Base.
- Default fee: `0.2222%`.
- Initial fee recipient: `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`.
- Contract is ownable.
- Owner can update fee rate and fee recipient.
- Deployer initially owns the router, then transfers ownership to the community Base multisig after validation and `www` deployment.
- The router should be comprehensive enough to cover the FAME route universe without requiring frequent community multisig updates.
- Multisig-managed configuration should be limited to durable governance controls such as fee parameters, fee recipient, ownership, and coarse venue-family enablement.

## Resolved Routing Facts - 2026-05-10

The latest `www` simulator adds `yarn fame-swap:simulate --validate-all-paths`, which validates quote calls and execution calldata for all configured advanced edges. These are frontend/offchain validation facts, not proof that `fame-contracts` already has executor interfaces, fixtures, or fork tests for every venue. Before the Slipstream 2 discovery below, the live result was `22/26` advanced directions quote and build calldata. The remaining `4/26` were known Slipstream 2 factory pools, not generic unknowns. Follow-up online and on-chain research found the correct Gauge Caps quoter/router pair, so the contract design should include these pools rather than exclude them. The `www` simulator still needs a follow-up patch to use those addresses. With `FAME_SWAP_VALIDATE_EXECUTION=1`, no-broadcast swap calls classify standard Slipstream failures as allowance setup (`STF`) and list the required approval target. Universal Router ERC-20 directions still need Permit2 setup for a full eth_call swap, while the native ETH-backed V4 WETH->ZORA validation succeeds via `msg.value`.

For contract planning, "validated" should be used narrowly:

- Frontend route validation means `www` can quote, build calldata, and simulate candidate routes.
- Contract execution validation means the `fame-contracts` executor can run the same route on a pinned Base fork and enforce custody, fee, and slippage invariants.
- Production execution should revert when any leg swap fails. Optional preview/read helpers can decode a route and report expected adapters, approval targets, and likely failure points, but the frontend remains responsible for route construction and quote quality.

Corrected token and venue metadata:

- ZORA token on Base is `0x1111111111166b7FE7bd91427724B487980aFc69`. The earlier `0x0fe633...3628` value is a Uniswap V4 pool id/hash, not an ERC-20 address.
- Uniswap Universal Router on Base: `0x6ff5693b99212da76ad316178a184ab56d299b43`.
- Permit2: `0x000000000022D473030F116dDEE9F6B43aC78BA3`.
- Uniswap V3 QuoterV2 on Base: `0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a`.
- Uniswap V4 Quoter on Base: `0x0d5e0f971ed27fbff6c2837bf31316121532048d`.
- Uniswap V4 PoolManager on Base: `0x498581ff718922c3f8e6a244956af099b2652b2b`.
- Scale/Equalizer Router v2 on Base: `0x2F87Bf58D5A9b2eFadE55Cdbd46153a0902be6FA`.
- Scale/Equalizer PairFactory on Base: `0xEd8db60aCc29e14bC867a497D94ca6e3CeB5eC04`.
- Aerodrome Slipstream SwapRouter on Base: `0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5`.
- Aerodrome Slipstream QuoterV2 on Base: `0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0`.
- Aerodrome Slipstream factory: `0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A`.
- Aerodrome Slipstream 2 / Gauge Caps factory observed on two msUSD pools: `0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a`.
- Aerodrome Slipstream 2 SwapRouter on Base: `0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D`.
- Aerodrome Slipstream 2 QuoterV2 on Base: `0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C`.

Protocol encoding facts:

- Scale/Equalizer on Base is a Solidly-style AMM, not a Uniswap V2 clone. Pairs expose `token0()`, `token1()`, `stable()`, and `getReserves()`. The router uses `Route[]` hops with `struct Route { address from; address to; bool stable; }` instead of Uniswap V2 `address[] path`. Quote path is `Router.getAmountsOut(uint256 amountIn, Route[] routes) -> uint256[]`. Execution path is `Router.swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, Route[] routes, address to, uint256 deadline) -> uint256[]`. The `stable` flag must match the concrete pair being used; `USDC/frxUSD` is stable, while the FAME, WETH, SCALE routes currently modeled are volatile. Equalizer's docs explicitly describe SCALE as the Base deployment and list Router v2 `0x2F87...e6FA` and PairFactory `0xEd8d...eC04`.
- Aerodrome Slipstream quote path is `QuoterV2.quoteExactInputSingle((tokenIn, tokenOut, amountIn, tickSpacing, sqrtPriceLimitX96))`. Execution path is `SwapRouter.exactInputSingle((tokenIn, tokenOut, tickSpacing, recipient, deadline, amountIn, amountOutMinimum, sqrtPriceLimitX96))`. Multi-hop uses packed paths with `int24 tickSpacing` between token addresses, not Uniswap V3 `uint24 fee`.
- Aerodrome Slipstream 2 uses the same tuple-style `QuoterV2` interface shape as the standard Slipstream V2 quoter, but it must target the Gauge Caps quoter/router pair above. The older non-tuple selector `quoteExactInputSingle(address,address,int24,uint256,uint160)` is not implemented by the Slipstream 2 quoter. The verified function selector is tuple-style `quoteExactInputSingle((address,address,uint256,int24,uint160))`.
- Uniswap V3 quote path is QuoterV2 `quoteExactInputSingle((tokenIn, tokenOut, amountIn, fee, sqrtPriceLimitX96))`. Execution through Universal Router uses command `0x00` (`V3_SWAP_EXACT_IN`) with packed path `tokenIn + uint24 fee + tokenOut`, and ERC-20 input requires token approval to Permit2 plus Permit2 approval to Universal Router.
- Uniswap V4 quote path is V4 Quoter `quoteExactInputSingle((PoolKey, zeroForOne, exactAmount, hookData))`. Execution through Universal Router uses command `0x10` (`V4_SWAP`) and action sequence `0x07 0x0c 0x0f` (`SWAP_EXACT_IN`, `SETTLE_ALL`, `TAKE_ALL`) with `PathKey[]`, not packed V3 bytes.
- The Uniswap V4 ZORA/ETH pool id `0xd694bd...f3a` is native ETH/ZORA, not WETH/ZORA. A WETH-facing UI or executor must unwrap WETH to native ETH or use an executor flow that handles wrapping/unwrapping.
- The Uniswap V4 basedflick/ZORA pool key was read from `basedflick.getPoolKey()`: currency0 ZORA, currency1 basedflick, fee `30000`, tickSpacing `200`, hooks `0xd61A675F8a0c67A73DC3B54FB7318B4D91409040`.

Advanced path validation status:

| Edge group | Status | Contract implication |
|---|---|---|
| Scale/Equalizer Router v2 `0x2F87...e6FA` pools | Quote and execution validated for direct and multi-hop FAME routes. Live `getAmountsOut` confirms `Route[]` encoding for direct `WETH/FAME`, `USDC/frxUSD/FAME`, and `USDC/SCALE/FAME` paths. | Add a Solidly-style adapter using `Route[]` with per-hop `stable`. This is required in v1 because Scale/Equalizer is the preferred pool family. |
| Aerodrome Slipstream factory `0x5e7B...809A` pools | Quote and execution calldata validated for basedflick/FAME, SPX/WETH 0.25%, USDC/frxUSD, msUSD/USDC A, WETH/msETH, ZORA/USDC, and ZORA/WETH | Add a Slipstream adapter using router/quoter above and per-pool `tickSpacing`. |
| Aerodrome Slipstream 2 / Gauge Caps factory `0xaDe65...716a` pools | Quote and execution path validated using QuoterV2 `0x3d4C...1c6C` and SwapRouter `0xcbBb...Ce0D` for `msUSD/msETH` and `msUSD/USDC C`; direct router eth_call reaches token payment and reverts `STF` without approvals | Add a second Slipstream adapter configuration using the Gauge Caps router/quoter pair. No direct-pool callback adapter is required for these pools. |
| Uniswap V3 ZORA/USDC and ZORA/WETH | Quote and Universal Router calldata validated both directions | Add Universal Router V3 adapter; remember Permit2. |
| Uniswap V4 basedflick/ZORA and ZORA/ETH | Quote and Universal Router calldata validated both directions | Add Universal Router V4 adapter; include hook-aware pool key and native ETH handling. |

Approval requirements for simulation and production execution:

- Aerodrome Slipstream factory `0x5e7B...809A`: input ERC-20 must approve `0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5`.
- Aerodrome Slipstream 2 / Gauge Caps factory `0xaDe65...716a`: input ERC-20 must approve `0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D`.
- Scale/Equalizer V2: input ERC-20 must approve Router v2 `0x2F87Bf58D5A9b2eFadE55Cdbd46153a0902be6FA`.
- Uniswap V3/V4 through Universal Router: input ERC-20 must approve Permit2 `0x000000000022D473030F116dDEE9F6B43aC78BA3`, then Permit2 must approve Universal Router `0x6ff5693b99212da76ad316178a184ab56d299b43`.
- Native ETH-backed V4 routes: the Universal Router path can be validated with `msg.value`. If the UI presents WETH, the owned executor must unwrap WETH before V4 execution or explicitly model an ETH input mode.

## Ranked Ideas

### 1. Balance-Checked Adapter Executor

**Description:** Build a FAME route executor contract that accepts an offchain-computed exact-input route, pulls `amountIn` from the caller, executes a sequence of typed adapter legs, checks route-local per-leg and final balance deltas, charges a single final-output fee, and sends the remainder to `recipient`.

The core surface would look roughly like:

```solidity
function executeExactInput(Route calldata route)
    external
    payable
    nonReentrant
    returns (uint256 amountOutAfterFee);
```

Where `Route` includes:

- `tokenIn`, `tokenOut`, `amountIn`, `minAmountOutAfterFee`, `recipient`, `deadline`.
- `Leg[] legs`.
- Optional `unwrapWeth` for output ETH later, not required for the first pass.

Each `Leg` includes:

- `adapterId`.
- `tokenIn`, `tokenOut`.
- `amountMode`, such as exact amount or balance-bps.
- `amount`, where bps modes allow split routes and "use remaining balance" behavior.
- `minAmountOut`.
- `venue` or router/pool target.
- Adapter-specific encoded payload.

Adapters are hard-coded internal execution paths or separately deployed adapter contracts selected by `adapterId`. The first supported adapters should be:

- `SCALE_EQUALIZER_V2_ROUTER`.
- `UNISWAP_V2_ROUTER02`.

Then add:

- `AERODROME_V2_ROUTER`.
- `UNISWAP_V3_SWAP_ROUTER` or Universal Router for V3/V4 where appropriate.
- `AERODROME_CL` using router/quoter configuration keyed by factory. Standard Slipstream and Slipstream 2 / Gauge Caps use different periphery addresses.

The executor should snapshot relevant token balances before execution, measure balances before and after every leg, and require route-local `deltaOut >= leg.minAmountOut`. Final checks should compare the final `tokenOut` balance against the pre-route baseline so ambient router dust, donations, or rescue leftovers cannot satisfy a user's `minAmountOutAfterFee` or be consumed by `BALANCE_BPS` / `ALL` amount modes. It should compute the fee only from the route-produced final output, transfer fee to the multisig, then transfer the net amount to the user.

**Rationale:** This fits the current reality: route intelligence belongs offchain, while the onchain contract enforces slippage, fee accounting, execution failure, and custody cleanup. Balance-delta checks reduce trust in router return values and make adapters more uniform across V2, Solidly, V3, CL, and future paths.

**Downsides:** More engineering and audit surface than calling one public router. Adapter payloads must be designed carefully so the contract does not become a disguised arbitrary-call router.

**Confidence:** 88%

**Complexity:** High

**Status:** Unexplored

### 2. Charge the 0.2222% Fee on Final Output

**Description:** Represent the fee as parts-per-million, with `FEE_DENOMINATOR = 1_000_000` and `defaultFeePpm = 2222`. This exactly encodes `0.2222%`. Charge the fee once on the final route output:

```solidity
feeAmount = finalAmountOut * feePpm / 1_000_000;
amountOutAfterFee = finalAmountOut - feeAmount;
```

For a buy, the multisig receives FAME. For a sell, it receives the output token such as WETH or USDC. The quote engine should display and enforce `minAmountOutAfterFee`, not pre-fee output.

Owner controls:

- `setFeePpm(uint256 newFeePpm)`.
- `setFeeRecipient(address newFeeRecipient)`.

Required guardrails:

- Nonzero fee recipient.
- Hard maximum fee, for example `10_000 ppm` (`1%`) unless governance explicitly wants a different cap.
- Events for all fee updates and fee payments.
- Constructor sets fee recipient directly to `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D`.

**Rationale:** Final-output fees are easier to explain and avoid changing route execution amounts mid-route. They also avoid charging multiple times for split routes or multi-hop routes. The fee is paid in whichever token the user intended to receive, which keeps contract accounting simple and predictable.

**Downsides:** The multisig receives mixed assets. The frontend must quote net output clearly because final displayed output is after the fee.

**Confidence:** 90%

**Complexity:** Low

**Status:** Unexplored

### 3. Split-Route Command Model

**Description:** Model each route as a sequence of executable commands where each command consumes some balance of `tokenIn` held by the router and produces `tokenOut`. Amount modes should support:

- `EXACT`: consume exactly `amount`.
- `BALANCE_BPS`: consume the route-local available balance of `tokenIn` times `amount / 10_000`.
- `ALL`: consume the full route-local available balance of `tokenIn`.

This lets the quote engine express:

- Direct swaps.
- Multi-hop swaps.
- Large swaps split across Scale and Uniswap V2 direct pools.
- Split-then-merge routes where two legs both output FAME and the final balance is charged once.

**Rationale:** Base swaps can be large enough that splitting across available liquidity matters. A simple sequential command model is easier to audit than a fully general graph while still supporting practical split execution.

**Downsides:** Sequential split execution can be less gas-efficient than specialized aggregator bytecode. It also requires the offchain quote engine to account for route ordering and balance-bps rounding. The contract must define route-local available balance precisely so ambient token balances cannot change split-route behavior.

**Confidence:** 84%

**Complexity:** Medium

**Status:** Unexplored

### 4. Low-Touch Venue Configuration

**Description:** The contract should avoid frequent community multisig updates by preferring durable, coarse venue configuration over per-route or per-pool governance. For the first production version, the router can support only the FAME route universe already modeled in `www`:

- FAME.
- WETH.
- USDC.
- frxUSD.
- SCALE.
- SPX.
- cbBTC.
- msUSD.
- msETH.
- ZORA.
- basedflick.

The initial executable venue support should be narrower than the token universe:

- Scale/Equalizer V2 router or factory-level venue family support.
- Uniswap V2 Router02 or factory-level venue family support for FAME-relevant V2 routes.

Aerodrome V2, Aerodrome CL, Uniswap V3, and Uniswap V4 should become executable only after adapter-specific fork simulations pass. Where possible, rollout should add protocol-family support that works for future FAME route graph updates without requiring the multisig to approve every new pool individually.

**Rationale:** The router will hold user funds transiently and perform external calls, but the owner should not have to manage a constantly changing frontend route graph. Coarse venue-family controls let the contract bound execution to known router/factory families while keeping day-to-day pool discovery in `www`.

**Downsides:** Coarser venue support relies more heavily on adapter correctness and fork tests. It reduces governance overhead but gives less per-pool control if a supported venue family contains a problematic pool.

**Confidence:** 86%

**Complexity:** Medium

**Status:** Unexplored

### 5. Simulation-First Foundry Harness

**Description:** Build the contract together with fork tests and trace scripts before UI integration. The first test suite should include:

- Unit tests for fee math: default `2222 ppm`, cap enforcement, zero recipient rejection, update events.
- Ownership tests: deployer owns initially, transfer to multisig flow works.
- Revert tests: expired deadline, unsupported token, unsupported venue, insufficient output, mismatched route token, malicious target.
- Base fork tests for Scale/Equalizer V2 WETH/FAME buy and sell.
- Base fork tests for Uniswap V2 WETH/FAME buy and sell.
- Split route test: WETH to FAME across Scale and Uniswap V2 direct pools, final fee charged once.
- FAME DN404 behavior test: the router should not mint or retain mirror NFTs while it transiently holds FAME, and `getSkipNFT(router)` should remain true.
- Cross-protocol multi-hop test once a real route is identified with sufficient liquidity.
- Trace snapshots mirroring the `www` simulation scripts.
- Repo setup for Base fork coverage: add a Base RPC endpoint and Basescan configuration to `foundry.toml`, mirroring the existing Sepolia configuration shape.
- Reproducibility fixtures for route metadata imported from `www`: token addresses, venue addresses, pool keys, tick spacing or fee tiers, expected approval targets, and a pinned Base fork block for every supported production route family.
- Execution failure tests showing that failed swaps revert and do not leave route-local user funds in the router.
- Preview/read helper tests, if included, showing that helpers report decoded route metadata and likely failure points without replacing execution-time reverts.

The target account `0x499e194d7a106AC1305ed4f96c6CEaAff650462D` can continue to be used for no-broadcast simulation where useful, but contract tests should also use Foundry fork impersonation and funded test accounts so approvals and balances are deterministic.

**Rationale:** The current router work already found that live pool metadata can be misleading. Simulation-first development prevents the contract from encoding assumptions that only hold for one venue family. Reproducible fixtures in this repo turn external `www` validation into contract-level evidence that the comprehensive FAME router can actually settle fee-taking routes on Base.

**Downsides:** Fork tests can be brittle across blocks unless pinned. CI needs Base RPC access or a separate mock suite for baseline coverage.

**Confidence:** 92%

**Complexity:** Medium

**Status:** Unexplored

### 6. Two-Phase Adapter Rollout

**Description:** Deliberately split execution support into phases:

Phase 1:

- FAME/WETH via Scale/Equalizer V2.
- FAME/WETH via Uniswap V2.
- Multi-leg and split-route architecture already present.
- Fee, low-touch venue configuration, ownership, and Foundry fork tests complete.

Phase 2:

- Aerodrome V2 reserve-style routes.
- Scale multi-hop routes beyond direct FAME/WETH.
- USDC-preferred paths where live simulation proves execution.

Phase 3:

- Uniswap V3/V4 once their exact Base periphery, pool keys, fee tiers, and quote/simulation paths are fully validated.
- Aerodrome CL can be pulled forward when the contract adapter supports per-leg router selection keyed by factory. Standard Slipstream and Slipstream 2 / Gauge Caps have both been identified on-chain.
- basedflick/ZORA paths after V4/V3/Aerodrome ZORA pools are no longer leaf-only in the route graph.

**Rationale:** The contract can be architected for all venue classes without pretending all venue classes are ready. This keeps the first deploy useful and reviewable while preserving the product requirement for a comprehensive router that can grow into the full FAME route universe.

**Downsides:** Some quoted routes will remain unavailable for execution until later phases. The UI must clearly distinguish quoted-but-staged venues from executable venues.

**Confidence:** 87%

**Complexity:** Medium

**Status:** Unexplored

### 7. Optional Permit2 and Native ETH Support as Follow-Ups

**Description:** Keep the first contract path ERC20-only and approval-based. Add Permit2 and WETH wrap/unwrap support after exact-input ERC20 routes are proven.

Permit2 can reduce user approval friction. Native ETH support can let users buy FAME with ETH by wrapping to WETH in the router and optionally unwrap WETH on sells.

**Rationale:** Permit and native ETH support are valuable, but they add edge cases around signatures, deadlines, replay domains, `msg.value`, refunds, and receive handlers. They should not block the core settlement contract.

**Downsides:** First release requires token approvals. The UX will be less polished until Permit2 lands.

**Confidence:** 78%

**Complexity:** Medium

**Status:** Unexplored

## Tail-End Refinement - 2026-05-12

### Current Status

The original router idea has mostly landed in `fame-contracts`: the router now has typed Solidity adapters, route-local custody accounting, final-output fee settlement, public config and Doppler separation, deployment validation, and a launchable pinned Base fixture manifest. The current fork matrix validates 19 pool metadata fixtures and executes 19 directional route fixtures.

The remaining gap is narrower and sharper than the original ideation problem. The onchain executor is ready enough to make the next question: can a high-quality offchain TypeScript route solver build real `FameRouterTypes.Route` payloads for the supported FAME route universe, and can those exact payloads drive expanded fork tests for composed, split, and split-then-merge production routes?

Current known gap examples:

- A composed production route such as `FAME -> basedflick -> ZORA -> WETH` has not yet been fork-tested as one `FameRouter` route, even though its component legs have individual fork coverage.
- Real split and split-then-merge routes are covered by mock unit tests, not by production Base fork fixtures.
- TypeScript in this repo is currently incidental: `package.json` has `typescript`, `ts-node`, and `viem`, but no strong route-solver package/test harness. `../fleet` is a useful local reference for Bun, viem, V3/V4 quoting, Universal Router encoding, and Anvil fork-style validation.
- The earlier schema-v1 assumption that V4 routes reject non-empty hook data is superseded. Hooked V4 routes with required hook data are in scope for the route compiler and fork matrix, using `../fleet` as the local reference for native hooked V4 swap behavior.

### Tail-End Ranked Ideas

#### 1. TypeScript Fixture-To-Route Compiler

**Description:** Build a pure viem TypeScript compiler that reads the known supported pool config and emits exact `FameRouterTypes.Route` payloads, including adapter-specific `bytes data`, `msg.value`, route hash inputs, funding metadata, and expected minimums.

The compiler should start from explicit supported config, not open-ended discovery. Its first scope should be FAME<->USDC/WETH/ETH plus required intermediate tokens already in the Base fixture universe: basedflick, ZORA, frxUSD, SCALE, msUSD, and msETH only where needed to satisfy supported routes.

**Rationale:** The most important integration boundary is not a quote number; it is the exact ABI route that `FameRouter.executeRoute` will accept. Making TypeScript emit the route struct directly removes a class of drift between docs, fixtures, frontend route builders, and Solidity fork tests.

**Downsides:** It raises the bar for TypeScript correctness. Nested ABI structs, enum ordinals, native ETH identity, and dynamic `bytes data` are all easy to encode almost-right.

**Confidence:** 94%

**Complexity:** Medium

**Status:** Unexplored

#### 2. Production Composed-Route Fork Matrix

**Description:** Promote composed routes to first-class fork fixtures instead of inferring confidence from single-leg coverage. The initial route set should include:

- `FAME -> basedflick -> ZORA -> WETH`
- `FAME -> basedflick -> ZORA -> USDC`
- `USDC -> ZORA -> basedflick -> FAME` if liquidity and directionality make it viable
- ETH/WETH variants that explicitly exercise native ETH vs WETH boundaries
- one real split route
- one real split-then-merge route

**Rationale:** The router's unique risk is cross-leg custody: intermediate balances, Permit2 cleanup, dust refunds, final-output fee settlement, and heterogeneous adapter sequencing. Single-leg fixtures prove adapters; composed fixtures prove the router.

**Downsides:** Some candidate routes may be illiquid or economically silly at the pinned block. The fixture policy needs to distinguish "valid execution evidence" from "best price route."

**Confidence:** 92%

**Complexity:** Medium

**Status:** Unexplored

#### 3. Bun-First Solver Test Harness

**Description:** Introduce a focused Bun/Vitest TypeScript harness for route solving, encoding, fixture generation, and fast golden tests. Keep it scoped: this is not a frontend app, not a general indexing service, and not a full `www` replacement.

Suggested shape:

- `js/router/` or `router-ts/` as the local package boundary.
- Bun scripts for route generation, route gap reports, and ABI parity checks.
- Vitest tests for pure graph solving and payload encoding.
- Foundry fork tests for actual execution of TS-generated fixture artifacts.

**Rationale:** The repo's current TypeScript tooling is good enough for scripts, not for a reference implementation with high standards. Bun is already proven in `../fleet`, and fast TS tests should catch encoding/config mistakes before slow RPC-backed fork runs.

**Downsides:** Migrating or introducing Bun adds package/tooling churn to a Solidity-heavy repo. Keep the footprint small and isolated.

**Confidence:** 88%

**Complexity:** Medium

**Status:** Unexplored

#### 4. Solver Adapter Modules Mirroring Solidity Adapters

**Description:** Implement TypeScript quote/encode modules with the same conceptual boundaries as Solidity:

- `solidly`
- `uniswapV2`
- `slipstream`
- `slipstream2`
- `uniswapV3`
- `uniswapV4`

Each module should expose a common shape such as `quoteExactIn`, `encodeLegPayload`, and `describePool`, while hiding venue-specific ABI details. For V3/V4, mine `../fleet` for viem Universal Router and Quoter patterns, but trim them into a FAME-specific implementation.

**Rationale:** Mirroring the Solidity adapter model makes reviews easier. It also avoids a TypeScript solver that becomes a parallel, incompatible mental model.

**Downsides:** The abstraction can become ceremonial if introduced too early. Keep each adapter thin and driven by actual fixture needs.

**Confidence:** 86%

**Complexity:** Medium

**Status:** Unexplored

#### 5. Route Hash And ABI Parity Harness

**Description:** Add a narrow parity check proving that TypeScript's viem encoding of `FameRouterTypes.Route` matches Solidity `abi.encode(route)` and `FameRouter.hashRoute(route)`.

This should cover:

- enum ordinals for `VenueFamily` and `AmountMode`
- nested `Leg[]`
- dynamic adapter `bytes data`
- native ETH as `address(0)`
- final route hash

**Rationale:** If the solver becomes the reference implementation, ABI parity is the central correctness risk. A solver that quotes correctly but hashes/encodes incorrectly is worse than no solver because it looks authoritative.

**Downsides:** Requires either a small Solidity helper test, a Foundry ffi-style comparison, or a generated fixture format that both TS and Solidity can independently read.

**Confidence:** 91%

**Complexity:** Low-Medium

**Status:** Unexplored

#### 6. Generated Route Gap Matrix

**Description:** Generate a matrix from the supported pool config and fixture inventory that answers:

- Which FAME<->USDC/WETH/ETH directions are supported?
- Which have a solver route?
- Which have TS-generated payloads?
- Which have pinned fork execution?
- Which are intentionally unsupported?
- Which require native ETH, WETH wrapping, Permit2, or V4 hook pools?

**Rationale:** "Complete the remaining routes" will otherwise drift into memory and naming conventions. A generated matrix gives the next work an auditable definition of done.

**Downsides:** It is meta-tooling. It only pays off if it stays tied to tests and fixture generation rather than becoming a stale report.

**Confidence:** 87%

**Complexity:** Low-Medium

**Status:** Unexplored

#### 7. Single Debug Artifact Per Solver Decision

**Description:** For every generated route, emit a structured debug artifact containing candidate paths considered, selected path, pool IDs, venue adapters, per-leg quote, minimum policy, fee-adjusted output, payload bytes, call value, route hash, and expected fork funding.

**Rationale:** Composed cross-venue routes fail in opaque ways. A durable debug artifact lets a reviewer see whether a failure is route choice, quote math, payload encoding, funding, or router execution.

**Downsides:** Debug artifacts can bloat fixture directories. Keep them concise and generated, or put verbose traces behind an explicit command.

**Confidence:** 82%

**Complexity:** Low

**Status:** Unexplored

### Tail-End Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Fully dynamic pool discovery in the solver | Too broad for this tail-end phase; the user explicitly wants a known supported pool config. |
| 2 | Price-first best-route engine | Premature. Executability and payload correctness matter more than marginal route quality at this stage. |
| 3 | Generate Solidity manifest as the first TS milestone | Valuable later, but the first solver should prove route payloads and fork execution before owning every manifest artifact. |
| 4 | Route solver without RPC only | Useful as a mode, but insufficient because real quote/fork validation is central to the task. |
| 5 | Native ETH/WETH normalization as a standalone project | Important, but best treated as a core requirement inside the compiler and gap matrix. |
| 6 | Minimum policy automation as a standalone project | Important, but it belongs inside fixture generation/debug artifacts rather than as the top-level idea. |
| 7 | Port all of `../fleet` swap infrastructure | Too much unrelated fleet/autonomy surface. Mine only the viem V3/V4 quote/encoder patterns. |
| 8 | Add route traces only to Solidity tests | Too narrow; the better artifact spans solver decisions and Foundry execution evidence. |
| 9 | Convert the contracts repo into a full TS monorepo | Too much process for the immediate goal; introduce a focused Bun surface first. |
| 10 | Backend signer or route authorization | Still not needed; the router already relies on slippage, deadlines, custody checks, and venue allowlists. |

### Recommended Tail-End Brainstorm Seed

Brainstorm **TypeScript Fixture-To-Route Compiler + Production Composed-Route Fork Matrix** as one combined next step.

The useful framing is: build the smallest Bun/viem reference implementation that can generate exact `FameRouterTypes.Route` payloads for FAME<->USDC/WETH/ETH over the supported pool config, then prove those payloads by expanding the pinned Base fork suite with composed, split, and split-then-merge routes.

Do not start by making the solver "smart." Start by making it exact, typed, deterministic, and executable.

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Use Uniswap Universal Router as the only router | It does not cover Scale/Equalizer or Aerodrome-specific venues, which are central to the FAME route graph. |
| 2 | Use only public family routers from the frontend | Cannot atomically split or multi-hop across protocol families while charging one FAME community fee. |
| 3 | Onchain pathfinding | Too expensive and unnecessary; the `www` quote engine is the right place for graph search and simulation. |
| 4 | Fully arbitrary multicall executor | Too risky for a user-funded contract unless heavily constrained; a stronger idea is typed adapters plus allowlists. |
| 5 | Charge the fee per leg | Penalizes multi-hop and split routes, makes quotes harder to reason about, and misaligns with the user's single trade intent. |
| 6 | Charge the fee upfront on input | Workable, but final-output fees keep route amounts cleaner and avoid mutating every leg amount around fee math. |
| 7 | Build all CL/V3/V4 support in v1 | Live findings show these venue types need more protocol-specific validation; forcing them into v1 increases risk. |
| 8 | Rely on router return values only | Return values differ across routers and can be misleading; balance-delta checks are more robust. |
| 9 | No venue allowlist, token allowlist only | Still leaves dangerous external-call surface. Venue-level controls are needed. |
| 10 | Owner can sweep any token at any time | Too much custodial power over transient route assets; any rescue function should be narrow and avoid active route tokens when possible. |
| 11 | Make the multisig initial owner at deploy time | Possible, but the stated rollout needs deployer validation first, then ownership transfer after contract and `www` are validated. |
| 12 | Include exact-output swaps in v1 | Exact-output is useful later, but exact-input matches current quote/simulation work and has simpler custody/failure behavior. |
| 13 | Encode every route as a custom Solidity struct per protocol only | Safer but too rigid; adapter-specific bytes behind typed adapter IDs preserves flexibility without becoming arbitrary multicall. |
| 14 | Use a backend signer to authorize every route | Adds key-management and liveness risk; slippage, deadlines, and allowlists should be enough for v1 unless abuse appears. |

## Open Questions for Brainstorming

- Should the fee cap be `1%`, lower, or governance-configurable with a timelock-style delay?
- Should route token controls be broad and mostly immutable from day one, or should v1 avoid token allowlisting and rely on adapter/venue-family constraints plus final balance checks?
- Should adapters be internal functions in one contract for v1, or separate adapter contracts for easier later upgrades?
- Should the router leave token approvals set to zero after each leg, or keep known-router allowances to reduce gas?
- Should the contract expose preview/read helpers for decoded route metadata and likely failure points, while keeping route search and quote simulation outside the contract?
- Should ownership use Solady `Ownable`, Solady `OwnableRoles`, OpenZeppelin `Ownable2Step`, or a project-local two-step transfer pattern?
- What is the smallest owner-managed configuration surface that still lets the router safely support the full FAME route universe?

## Recommended Next Brainstorm Seed

Before the router plan, run a separate `ce:ideate` pass on the in-repo integration surface for advanced venues and Foundry cleanup. That prerequisite should identify the best way to add minimal router interfaces, Base fork fixtures, test organization, and protocol-family support without overfitting the contract to frontend checks.

After that, the strongest router survivor is **Balance-Checked Adapter Executor** with **final-output fee accounting**, **route-local split-route accounting**, and **low-touch venue configuration**. The next `ce:brainstorm` should define the exact Solidity API, adapter payload boundaries, venue-family configuration model, fee events, failure modes, preview/read helpers, and the Base fork simulation matrix.

## Session Log

- 2026-05-10: Initial ideation for `multi-leg router for fame` - 21 candidate directions considered, 7 survived, 14 rejected.
- 2026-05-10: Contracts review follow-up incorporated decisions to keep frontend route checks offchain, prefer low-touch multisig configuration, require route-local final checks, add reproducible in-repo validation fixtures, and run a prerequisite `ce:ideate` on advanced venue integration and Foundry cleanup.
- 2026-05-12: Tail-end solver/fork refinement added after router implementation progress - raw candidates from four framing passes synthesized into 7 survivor ideas focused on a TypeScript route compiler, composed fork matrix, Bun harness, adapter modules, ABI parity, a generated gap matrix, and solver debug artifacts.
