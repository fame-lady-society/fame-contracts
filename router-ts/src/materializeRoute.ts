import { decodeAbiParameters, encodeAbiParameters, type Address, type Hex } from "viem";
import { aerodromeV2PayloadAbi } from "./adapters/aerodromeV2.js";
import { encodeRoute, hashRoute } from "./artifacts/routeEncoding.js";
import { routeFromJson, type JsonRoute } from "./artifacts/schema.js";
import type { Route, RouteLeg } from "./compiler/types.js";

const DEFAULT_MAX_PRODUCTION_DEADLINE_SECONDS = 30n * 60n;

const solidlyPayloadAbi = [
  {
    type: "tuple",
    components: [
      {
        name: "routes",
        type: "tuple[]",
        components: [
          { name: "from", type: "address" },
          { name: "to", type: "address" },
          { name: "stable", type: "bool" }
        ]
      },
      { name: "deadline", type: "uint256" }
    ]
  }
] as const;

const uniswapV2PayloadAbi = [
  {
    type: "tuple",
    components: [
      { name: "path", type: "address[]" },
      { name: "deadline", type: "uint256" }
    ]
  }
] as const;

const slipstreamPayloadAbi = [
  {
    type: "tuple",
    components: [
      { name: "router", type: "address" },
      { name: "factory", type: "address" },
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "tickSpacing", type: "int24" },
      { name: "sqrtPriceLimitX96", type: "uint160" },
      { name: "deadline", type: "uint256" }
    ]
  }
] as const;

export const universalRouterV3MaterializePayloadAbi = [
  {
    type: "tuple",
    components: [
      { name: "path", type: "bytes" },
      { name: "deadline", type: "uint256" },
      { name: "payerIsUser", type: "bool" },
      { name: "recipient", type: "address" }
    ]
  }
] as const;

export const universalRouterV4MaterializePayloadAbi = [
  {
    type: "tuple",
    components: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "currency0", type: "address" },
      { name: "currency1", type: "address" },
      { name: "zeroForOne", type: "bool" },
      { name: "fee", type: "uint24" },
      { name: "tickSpacing", type: "int24" },
      { name: "hooks", type: "address" },
      { name: "hookData", type: "bytes" },
      { name: "deadline", type: "uint256" },
      { name: "recipient", type: "address" },
      { name: "payerIsUser", type: "bool" }
    ]
  }
] as const;

export interface MaterializedRoute {
  route: Route;
  abiEncodedRoute: Hex;
  routeHash: Hex;
}

export interface ProductionCalldataArtifact {
  productionExecutable: boolean;
  abiEncodedRoute: Hex;
}

export interface ProductionMaterializeOptions {
  routerAddress: Address;
  recipient: Address;
  deadline: bigint;
  now: bigint;
  minAmountOutAfterFee: bigint;
  legMinAmountOut: readonly bigint[];
  maxDeadlineSecondsFromNow?: bigint;
}

export function materializeProductionRouteFromJson(route: JsonRoute, options: ProductionMaterializeOptions): MaterializedRoute {
  return materializeProductionRoute(routeFromJson(route), options);
}

export function materializeProductionRoute(route: Route, options: ProductionMaterializeOptions): MaterializedRoute {
  validateProductionMaterializeOptions(route, options);
  const materializedRoute: Route = {
    ...route,
    recipient: options.recipient,
    deadline: options.deadline,
    minAmountOutAfterFee: options.minAmountOutAfterFee,
    legs: route.legs.map((leg, index) =>
      materializeLeg(leg, options.routerAddress, options.deadline, options.legMinAmountOut[index] ?? 0n)
    )
  };

  return {
    route: materializedRoute,
    abiEncodedRoute: encodeRoute(materializedRoute),
    routeHash: hashRoute(materializedRoute)
  };
}

export function productionCalldataFromArtifact(artifact: ProductionCalldataArtifact): Hex {
  if (!artifact.productionExecutable) {
    throw new Error("Fork-evidence artifacts require production materialization before calldata use");
  }
  return artifact.abiEncodedRoute;
}

function validateProductionMaterializeOptions(route: Route, options: ProductionMaterializeOptions): void {
  if (options.deadline <= options.now) throw new Error("Production route deadline must be in the future");
  const maxDeadline = options.maxDeadlineSecondsFromNow ?? DEFAULT_MAX_PRODUCTION_DEADLINE_SECONDS;
  if (options.deadline > options.now + maxDeadline) throw new Error("Production route deadline must be near-term");
  if (options.minAmountOutAfterFee <= 0n) throw new Error("Production route requires quote-derived final minimum");
  if (options.legMinAmountOut.length !== route.legs.length) {
    throw new Error("Production route requires quote-derived minimum for every leg");
  }
  for (let i = 0; i < route.legs.length; ++i) {
    const leg = route.legs[i];
    const minimum = options.legMinAmountOut[i];
    if (leg === undefined) throw new Error("Production route requires quote-derived minimum for every leg");
    if (minimum === undefined) throw new Error("Production route requires quote-derived minimum for every leg");
    if (leg.venue === "NativeWrap") {
      if (minimum !== 0n) throw new Error("NativeWrap production leg minimum must remain zero");
    } else if (minimum <= 0n) {
      throw new Error("Production swap legs require positive quote-derived minimums");
    }
  }
}

function materializeLeg(
  leg: RouteLeg,
  routerAddress: Address,
  deadline: bigint,
  minAmountOut: bigint
): RouteLeg {
  const materialized: RouteLeg = {
    ...leg,
    minAmountOut
  };
  return {
    ...materialized,
    data: materializeLegPayload(materialized, routerAddress, deadline)
  };
}

function materializeLegPayload(leg: RouteLeg, routerAddress: Address, deadline: bigint): Hex {
  switch (leg.venue) {
    case "Solidly":
      return patchDeadline(solidlyPayloadAbi, leg.data, deadline);
    case "AerodromeV2":
      return patchDeadline(aerodromeV2PayloadAbi, leg.data, deadline);
    case "UniswapV2":
      return patchDeadline(uniswapV2PayloadAbi, leg.data, deadline);
    case "Slipstream":
    case "Slipstream2":
      return patchDeadline(slipstreamPayloadAbi, leg.data, deadline);
    case "UniswapV3":
      return patchUniversalRouterV3Payload(leg.data, routerAddress, deadline);
    case "UniswapV4":
      return patchUniversalRouterV4Payload(leg.data, routerAddress, deadline, leg.amount, leg.minAmountOut);
    case "NativeWrap":
      return leg.data;
  }
}

function patchDeadline(
  abi:
    | typeof solidlyPayloadAbi
    | typeof aerodromeV2PayloadAbi
    | typeof uniswapV2PayloadAbi
    | typeof slipstreamPayloadAbi,
  data: Hex,
  deadline: bigint
): Hex {
  const typedAbi = abi as typeof solidlyPayloadAbi;
  const [payload] = decodeAbiParameters(typedAbi, data);
  return encodeAbiParameters(typedAbi, [{ ...payload, deadline }]);
}

function patchUniversalRouterV3Payload(data: Hex, routerAddress: Address, deadline: bigint): Hex {
  const [payload] = decodeAbiParameters(universalRouterV3MaterializePayloadAbi, data);
  return encodeAbiParameters(universalRouterV3MaterializePayloadAbi, [{ ...payload, recipient: routerAddress, deadline }]);
}

function patchUniversalRouterV4Payload(
  data: Hex,
  routerAddress: Address,
  deadline: bigint,
  amountIn: bigint,
  minAmountOut: bigint
): Hex {
  const [payload] = decodeAbiParameters(universalRouterV4MaterializePayloadAbi, data);
  return encodeAbiParameters(universalRouterV4MaterializePayloadAbi, [
    {
      ...payload,
      amountIn: payload.amountIn === 0n ? 0n : amountIn,
      minAmountOut,
      recipient: routerAddress,
      deadline
    }
  ]);
}
