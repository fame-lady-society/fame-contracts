# FAME Router Schema

The FAME router accepts schema version `1` routes. `www` remains responsible for route discovery, quoting, and route quality. The contract receives a deterministic exact-input execution plan and enforces custody, minimum output, fee, and settlement rules.

## Route

- `version`: must equal `1`.
- `tokenIn`: ERC-20 input token, or `address(0)` for native ETH.
- `tokenOut`: final output token, or `address(0)` for native ETH.
- `amountIn`: exact amount funded by `msg.sender`.
- `minAmountOutAfterFee`: recipient minimum after the community fee.
- `recipient`: final output recipient.
- `deadline`: timestamp after which execution reverts.
- `legs`: one or more typed venue legs.

## Leg

- `tokenIn`: route-local asset consumed by this leg.
- `tokenOut`: route-local asset produced by this leg.
- `venue`: one of the `VenueFamily` wire values below.
- `amountMode`: one of the `AmountMode` wire values below.
- `amount`: exact amount or bps value, depending on `amountMode`.
- `minAmountOut`: leg-local output floor before the next leg.
- `target`: enabled venue target for the selected family. Until typed venue payload docs land, this field is not implementable by `www`; see the implementation boundary below.
- `data`: bounded venue payload, currently capped at 2048 bytes.

Native ETH is represented as `address(0)` and is distinct from WETH. Native input routes require `msg.value == amountIn`; ERC-20 input routes reject nonzero `msg.value`.

## Wire Values

Schema version `1` uses Solidity ABI encoding for `FameRouterTypes.Route` and `FameRouterTypes.Leg`.

### VenueFamily

| Value | Name |
|---:|---|
| `0` | `Solidly` |
| `1` | `UniswapV2` |
| `2` | `Slipstream` |
| `3` | `Slipstream2` |
| `4` | `UniswapV3` |
| `5` | `UniswapV4` |
| `6` | `NativeWrap` |
| `7` | `AerodromeV2` |

Values outside this table are not valid schema version `1` venue families. ABI decoding rejects out-of-range enum values before route execution.

### AmountMode

| Value | Name | `amount` meaning |
|---:|---|---|
| `0` | `Exact` | Spend exactly `amount` units of `tokenIn` from route-local balance. |
| `1` | `BalanceBps` | Spend `(availableRouteLocalBalance * amount) / 10_000`, rounded down. |
| `2` | `All` | Spend the full route-local balance of `tokenIn`; `amount` is ignored and should be encoded as `0`. |

`BalanceBps` uses a `10_000` denominator. Valid values are `0..10_000`, although any mode that computes a zero spend reverts. Values greater than `10_000` revert.

## Fee

The default community fee is `2222 ppm` over a `1_000_000` denominator. It is charged once on final route-local output after all legs complete and before net settlement to `recipient`. The fee rate is owner-updatable up to `10_000 ppm`.

## Route Identity

`RouteExecuted` includes `routeHash = keccak256(abi.encode(route))`, the submitted schema version, `tokenIn`, and `amountIn`. Indexers and `www` can recompute this value from the exact ABI route submitted to `executeRoute` and match settlement events back to an offchain route fixture or quote.

## Custody Rules

The router snapshots its own balances before execution and uses only route-local balance deltas for leg spending, leg minimums, final minimums, fee settlement, and dust refunds. Ambient balances that existed before execution do not satisfy route checks. Successful routes refund route-local non-output leftovers to `msg.sender`.

## Approval And Native Asset Policy

The router clears direct ERC-20 allowances after each non-Permit2 leg. Universal Router V3 and V4 ERC-20 legs use the canonical Permit2 singleton and clear both token-to-Permit2 and Permit2-to-router allowances after execution.

The router does not perform implicit wrap or unwrap conversions. Native ETH remains `address(0)` in the route schema, and WETH routes must use the WETH token address explicitly.

`NativeWrap` is the only wrap/unwrap venue. It is an explicit route leg, not a pre-route flag, post-route flag, or generic external call. Valid directions are:

- `address(0) -> leg.target`, where `leg.target` is the enabled canonical WETH target for that chain.
- `leg.target -> address(0)`, where `leg.target` is the enabled canonical WETH target for that chain.

`NativeWrap` legs must encode empty `data`, `minAmountOut = 0`, and no approval is created. `Exact`, `BalanceBps`, and `All` amount modes are supported; `All` should encode `amount = 0`. The router derives the effective leg minimum from the computed spend amount and enforces it with the same route-local balance-delta accounting used by swap venues.

Pure wrap routes are out of scope. Routes whose legs are all `NativeWrap` revert before funds move; valid NativeWrap routes must include at least one non-NativeWrap swap leg. The router intentionally does not add economic route-quality heuristics such as dust-swap detection. Route discovery, quote quality, and whether a route is worth showing remain offchain responsibilities.

## Current Implementation Boundary

For production v1 routes, `target` is the real enabled venue target for the selected family, not a Fame-owned generic executor. Supported typed payloads are:

- `Solidly`: enabled Solidly-compatible swap router. Payload is `SolidlyRouterAdapter.Payload(Route[] routes, uint256 deadline)` where each route has `from`, `to`, and `stable`.
- `AerodromeV2`: enabled Aerodrome V2 router. Payload is `AerodromeV2RouterAdapter.Payload(Route[] routes, uint256 deadline)` where each route has `from`, `to`, `stable`, and `factory`. This is intentionally separate from `Solidly`; Aerodrome V2 route bytes must include the explicit factory field for each hop.
- `UniswapV2`: enabled Uniswap V2-compatible router. Payload is `UniswapV2Adapter.Payload(address[] path, uint256 deadline)`.
- `Slipstream` and `Slipstream2`: enabled Aerodrome concentrated-liquidity router. Payload is `SlipstreamAdapter.Payload(address router, address factory, address tokenIn, address tokenOut, int24 tickSpacing, uint160 sqrtPriceLimitX96, uint256 deadline)`. The adapter verifies the target router's live `factory()` matches the payload factory before execution.
- `UniswapV3` and `UniswapV4`: enabled Universal Router target. Payloads are structured V3/V4 exact-input fields; the router constructs only supported Universal Router commands and rejects raw command payloads. V4 payload `amountIn` may be `0` for route-local dynamic amount modes such as `All`; when it is nonzero it must match the router-computed leg input. V4 fixtures pin hook addresses, and schema version `1` supports bounded hook data for explicitly allowed configured hooked pools when the route requires it. The onchain v1 policy allowlists the Universal Router target rather than individual pools or hook addresses. Non-empty hook data must be constrained by router validation; hooked pools with empty swap `hookData` execute under the structured payload checks and offchain pool-universe policy.
- `NativeWrap`: enabled canonical WETH target. Payload is always empty, `minAmountOut` is always encoded as `0`, and artifacts should expose a `nativeWrap` capability so schema v1 consumers do not infer support from schema version alone.

The checked-in generic `IRouterLegExecutor` path is test scaffolding used by local router custody tests; it is not a `www` payload contract and is not a production venue ABI.

The checked-in contract implements the route schema, custody accounting, fee/governance controls, bounded payload validation, enabled family/target validation, and typed production adapter call surfaces. The production Base fixture snapshot is populated, launchable, and covered by pinned-fork pool metadata plus all-route execution tests.
