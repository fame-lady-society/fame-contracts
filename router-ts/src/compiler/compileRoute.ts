import type { Address } from "viem";
import { aerodromeV2Encoder, type AerodromeV2RouteHop } from "../adapters/aerodromeV2.js";
import { solidlyEncoder, type SolidlyRouteHop } from "../adapters/solidly.js";
import { slipstreamEncoder } from "../adapters/slipstream.js";
import { uniswapV2Encoder } from "../adapters/uniswapV2.js";
import { universalRouterV3Encoder } from "../adapters/universalRouterV3.js";
import { universalRouterV4Encoder } from "../adapters/universalRouterV4.js";
import { poolById } from "../config/base.js";
import { BASEDFLICK, FAME, FRXUSD, NATIVE_ETH, USDC, WETH, ZORA } from "../config/tokens.js";
import { postFeeMinimum } from "./minimums.js";
import {
  DETERMINISTIC_DEADLINE,
  SCHEMA_VERSION,
  type AmountModeName,
  type CompiledRoute,
  type Funding,
  type PoolConfig,
  type Route,
  type RouteCapabilities,
  type RouteDebug,
  type RouteLeg,
  type SupportedPoolConfig
} from "./types.js";

export const ROUTER_TEST_RECIPIENT: Address = "0x0000000000000000000000000000000000001003";
export const ROUTER_TEST_EXECUTOR: Address = "0x000000000000000000000000000000000000f00d";

export interface CompileContext {
  executor: Address;
  recipient: Address;
  deadline: bigint;
}

export const DEFAULT_COMPILE_CONTEXT: CompileContext = {
  executor: ROUTER_TEST_EXECUTOR,
  recipient: ROUTER_TEST_RECIPIENT,
  deadline: DETERMINISTIC_DEADLINE
};

interface PoolCandidateLeg {
  kind?: "pool";
  poolId: string;
  tokenIn: Address;
  tokenOut: Address;
  amountMode: AmountModeName;
  amount: bigint;
  minAmountOut: bigint;
  quotedAmountOut: bigint;
  solidlyRoutes?: SolidlyRouteHop[];
  aerodromeV2Routes?: AerodromeV2RouteHop[];
}

interface NativeWrapCandidateLeg {
  kind: "nativeWrap";
  tokenIn: Address;
  tokenOut: Address;
  amountMode: AmountModeName;
  amount: bigint;
  minAmountOut: 0n;
  quotedAmountOut: bigint;
}

type CandidateLeg = PoolCandidateLeg | NativeWrapCandidateLeg;

interface CandidateRoute {
  id: string;
  description: string;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minAmountOutAfterFee: bigint;
  callValue: bigint;
  funding: Funding;
  legs: CandidateLeg[];
  capabilities: RouteCapabilities;
  candidateSummary: string[];
}

function buildLeg(config: SupportedPoolConfig, leg: CandidateLeg, recipient: Address, deadline: bigint): RouteLeg {
  if (leg.kind === "nativeWrap") {
    return {
      tokenIn: leg.tokenIn,
      tokenOut: leg.tokenOut,
      venue: "NativeWrap",
      amountMode: leg.amountMode,
      amount: leg.amount,
      minAmountOut: 0n,
      target: WETH,
      data: "0x"
    };
  }

  const pool = poolById(config, leg.poolId);
  const input = {
    tokenIn: leg.tokenIn,
    tokenOut: leg.tokenOut,
    amount: leg.amount,
    minAmountOut: leg.minAmountOut,
    target: pool.router,
    deadline
  };

  let routeLeg: RouteLeg;
  switch (pool.venue) {
    case "solidly":
      routeLeg = solidlyEncoder.buildLeg(input, leg.solidlyRoutes ?? pool, recipient);
      break;
    case "aerodrome-v2":
      routeLeg = aerodromeV2Encoder.buildLeg(input, leg.aerodromeV2Routes ?? pool, recipient);
      break;
    case "uniswap-v2":
      routeLeg = uniswapV2Encoder.buildLeg(input, pool, recipient);
      break;
    case "aerodrome-slipstream":
    case "aerodrome-slipstream2":
      routeLeg = slipstreamEncoder.buildLeg(input, pool, recipient);
      break;
    case "uniswap-v3":
      routeLeg = universalRouterV3Encoder.buildLeg(input, pool, recipient);
      break;
    case "uniswap-v4":
      routeLeg = universalRouterV4Encoder.buildLeg(input, pool, recipient);
      break;
  }

  return { ...routeLeg, amountMode: leg.amountMode, amount: leg.amount };
}

function buildCompiledRoute(config: SupportedPoolConfig, candidate: CandidateRoute, context: CompileContext): CompiledRoute {
  const legs = candidate.legs.map((leg) => buildLeg(config, leg, context.executor, context.deadline));
  const route: Route = {
    version: SCHEMA_VERSION,
    tokenIn: candidate.tokenIn,
    tokenOut: candidate.tokenOut,
    amountIn: candidate.amountIn,
    minAmountOutAfterFee: candidate.minAmountOutAfterFee,
    recipient: context.recipient,
    deadline: context.deadline,
    legs
  };
  const debug: RouteDebug = {
    selectedPath: [candidate.tokenIn, ...candidate.legs.map((leg) => leg.tokenOut)],
    candidateSummary: candidate.candidateSummary,
    amountModes: legs.map((leg) => leg.amountMode),
    venueFamilies: legs.map((leg) => leg.venue),
    perLegMinimums: candidate.legs.map((leg) => leg.minAmountOut),
    perLegEffectiveMinimums: candidate.legs.map((leg) =>
      leg.kind === "nativeWrap" ? leg.quotedAmountOut : leg.minAmountOut
    ),
    perLegQuoteValues: candidate.legs.map((leg) => leg.quotedAmountOut),
    finalPostFeeMinimum: candidate.minAmountOutAfterFee
  };

  return {
    id: candidate.id,
    description: candidate.description,
    poolIds: candidate.legs.flatMap((leg) => (leg.kind === "nativeWrap" ? [] : [leg.poolId])),
    route,
    executionContext: context,
    callValue: candidate.callValue,
    funding: candidate.funding,
    capabilities: candidate.capabilities,
    debug
  };
}

function requirePool(config: SupportedPoolConfig, id: string): PoolConfig {
  return poolById(config, id);
}

function baseCapabilities(overrides: Partial<RouteCapabilities>): RouteCapabilities {
  return {
    nativeEth: false,
    weth: false,
    nativeWrap: false,
    permit2UniversalRouter: false,
    v4Hooks: false,
    v4HookAddress: false,
    v4NonEmptyHookData: false,
    v4MultiHopPathKeys: false,
    split: false,
    splitThenMerge: false,
    ...overrides
  };
}

export function candidateRoutes(config: SupportedPoolConfig): CandidateRoute[] {
  requirePool(config, "slipstream-basedflick-fame");
  requirePool(config, "uniswap-v4-basedflick-zora");
  requirePool(config, "uniswap-v4-zora-eth");
  requirePool(config, "uniswap-v3-zora-weth");
  requirePool(config, "uniswap-v3-zora-usdc");
  requirePool(config, "scale-equalizer-weth-fame");
  requirePool(config, "aerodrome-v2-usdc-weth");
  requirePool(config, "uniswap-v2-fame-direct");
  requirePool(config, "scale-equalizer-usdc-frxusd");
  requirePool(config, "slipstream-usdc-frxusd");
  requirePool(config, "scale-equalizer-frxusd-fame");

  const fameToBasedflick = 980_100_000_232_613_992n;
  const usdcToZora = 73_837_797_098_392_273_783n;
  const ethToZora = 170_174_733_551_265_108_370n;

  return [
    {
      id: "solver-eth-weth-fame",
      description: "NativeWrap proof route: ETH -> WETH -> FAME.",
      tokenIn: NATIVE_ETH,
      tokenOut: FAME,
      amountIn: 1_000_000_000_000_000n,
      minAmountOutAfterFee: 1n,
      callValue: 1_000_000_000_000_000n,
      funding: {
        type: "native-eth",
        amount: 1_000_000_000_000_000n
      },
      legs: [
        {
          kind: "nativeWrap",
          tokenIn: NATIVE_ETH,
          tokenOut: WETH,
          amountMode: "Exact",
          amount: 1_000_000_000_000_000n,
          minAmountOut: 0n,
          quotedAmountOut: 1_000_000_000_000_000n
        },
        {
          poolId: "scale-equalizer-weth-fame",
          tokenIn: WETH,
          tokenOut: FAME,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ nativeEth: true, weth: true, nativeWrap: true }),
      candidateSummary: ["Wraps native ETH into canonical Base WETH before using existing WETH -> FAME liquidity."]
    },
    {
      id: "solver-fame-basedflick-zora-usdc",
      description: "Composed production route: FAME -> basedflick -> ZORA -> USDC.",
      tokenIn: FAME,
      tokenOut: USDC,
      amountIn: 31_597_600_141_347_829n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "acquire-via-route",
        routeId: "slipstream-basedflick-fame-buy",
        amountIn: 1_000_000_000_000_000_000n,
        expectedAmountOut: 31_597_600_141_347_829n
      },
      legs: [
        {
          poolId: "slipstream-basedflick-fame",
          tokenIn: FAME,
          tokenOut: BASEDFLICK,
          amountMode: "Exact",
          amount: 31_597_600_141_347_829n,
          minAmountOut: fameToBasedflick,
          quotedAmountOut: fameToBasedflick
        },
        {
          poolId: "uniswap-v4-basedflick-zora",
          tokenIn: BASEDFLICK,
          tokenOut: ZORA,
          amountMode: "Exact",
          amount: fameToBasedflick,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "uniswap-v3-zora-usdc",
          tokenIn: ZORA,
          tokenOut: USDC,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ permit2UniversalRouter: true, v4Hooks: true, v4HookAddress: true }),
      candidateSummary: ["Uses pinned single-leg FAME -> basedflick output as the exact V4 input amount."]
    },
    {
      id: "solver-fame-basedflick-zora-weth",
      description: "Composed production route: FAME -> basedflick -> ZORA -> WETH.",
      tokenIn: FAME,
      tokenOut: WETH,
      amountIn: 31_597_600_141_347_829n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "acquire-via-route",
        routeId: "slipstream-basedflick-fame-buy",
        amountIn: 1_000_000_000_000_000_000n,
        expectedAmountOut: 31_597_600_141_347_829n
      },
      legs: [
        {
          poolId: "slipstream-basedflick-fame",
          tokenIn: FAME,
          tokenOut: BASEDFLICK,
          amountMode: "Exact",
          amount: 31_597_600_141_347_829n,
          minAmountOut: fameToBasedflick,
          quotedAmountOut: fameToBasedflick
        },
        {
          poolId: "uniswap-v4-basedflick-zora",
          tokenIn: BASEDFLICK,
          tokenOut: ZORA,
          amountMode: "Exact",
          amount: fameToBasedflick,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "uniswap-v3-zora-weth",
          tokenIn: ZORA,
          tokenOut: WETH,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ weth: true, permit2UniversalRouter: true, v4Hooks: true, v4HookAddress: true }),
      candidateSummary: ["Uses pinned single-leg FAME -> basedflick output as the exact V4 input amount."]
    },
    {
      id: "solver-fame-weth-eth",
      description: "NativeWrap proof route: FAME -> WETH -> ETH.",
      tokenIn: FAME,
      tokenOut: NATIVE_ETH,
      amountIn: 31_597_600_141_347_829n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "acquire-via-route",
        routeId: "slipstream-basedflick-fame-buy",
        amountIn: 1_000_000_000_000_000_000n,
        expectedAmountOut: 31_597_600_141_347_829n
      },
      legs: [
        {
          poolId: "scale-equalizer-weth-fame",
          tokenIn: FAME,
          tokenOut: WETH,
          amountMode: "Exact",
          amount: 31_597_600_141_347_829n,
          minAmountOut: 1n,
          quotedAmountOut: 1n,
          solidlyRoutes: [{ from: FAME, to: WETH, stable: false }]
        },
        {
          kind: "nativeWrap",
          tokenIn: WETH,
          tokenOut: NATIVE_ETH,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 0n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ nativeEth: true, weth: true, nativeWrap: true }),
      candidateSummary: ["Uses existing FAME -> WETH liquidity, then unwraps all route-local WETH to native ETH."]
    },
    {
      id: "solver-fame-basedflick-zora-eth",
      description: "Composed production route: FAME -> basedflick -> ZORA -> ETH.",
      tokenIn: FAME,
      tokenOut: NATIVE_ETH,
      amountIn: 31_597_600_141_347_829n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "acquire-via-route",
        routeId: "slipstream-basedflick-fame-buy",
        amountIn: 1_000_000_000_000_000_000n,
        expectedAmountOut: 31_597_600_141_347_829n
      },
      legs: [
        {
          poolId: "slipstream-basedflick-fame",
          tokenIn: FAME,
          tokenOut: BASEDFLICK,
          amountMode: "Exact",
          amount: 31_597_600_141_347_829n,
          minAmountOut: fameToBasedflick,
          quotedAmountOut: fameToBasedflick
        },
        {
          poolId: "uniswap-v4-basedflick-zora",
          tokenIn: BASEDFLICK,
          tokenOut: ZORA,
          amountMode: "Exact",
          amount: fameToBasedflick,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "uniswap-v4-zora-eth",
          tokenIn: ZORA,
          tokenOut: NATIVE_ETH,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({
        nativeEth: true,
        permit2UniversalRouter: true,
        v4Hooks: true,
        v4HookAddress: true
      }),
      candidateSummary: ["Uses router-computed All mode for the final ZORA -> ETH V4 hop."]
    },
    {
      id: "solver-usdc-zora-basedflick-fame",
      description: "Reverse composed production route: USDC -> ZORA -> basedflick -> FAME.",
      tokenIn: USDC,
      tokenOut: FAME,
      amountIn: 1_000_000n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "deal-erc20",
        token: USDC,
        amount: 1_000_000n,
        justification: "User-side USDC balance setup avoids mutating venue pools or FAME DN404 accounting."
      },
      legs: [
        {
          poolId: "uniswap-v3-zora-usdc",
          tokenIn: USDC,
          tokenOut: ZORA,
          amountMode: "Exact",
          amount: 1_000_000n,
          minAmountOut: usdcToZora,
          quotedAmountOut: usdcToZora
        },
        {
          poolId: "uniswap-v4-basedflick-zora",
          tokenIn: ZORA,
          tokenOut: BASEDFLICK,
          amountMode: "Exact",
          amount: usdcToZora,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "slipstream-basedflick-fame",
          tokenIn: BASEDFLICK,
          tokenOut: FAME,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ permit2UniversalRouter: true, v4Hooks: true, v4HookAddress: true }),
      candidateSummary: ["Uses pinned single-leg USDC -> ZORA output as the exact V4 input amount."]
    },
    {
      id: "solver-usdc-aerodrome-weth-fame",
      description: "Aerodrome V2 proof route: USDC -> WETH -> FAME.",
      tokenIn: USDC,
      tokenOut: FAME,
      amountIn: 1_000_000n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "deal-erc20",
        token: USDC,
        amount: 1_000_000n,
        justification: "User-side USDC balance setup proves Aerodrome V2 connector liquidity without mutating venue pools."
      },
      legs: [
        {
          poolId: "aerodrome-v2-usdc-weth",
          tokenIn: USDC,
          tokenOut: WETH,
          amountMode: "Exact",
          amount: 1_000_000n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "scale-equalizer-weth-fame",
          tokenIn: WETH,
          tokenOut: FAME,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ weth: true }),
      candidateSummary: ["Uses Aerodrome V2 USDC -> WETH explicit-factory routing before existing WETH -> FAME liquidity."]
    },
    {
      id: "solver-eth-zora-basedflick-fame",
      description: "Reverse composed production route: ETH -> ZORA -> basedflick -> FAME.",
      tokenIn: NATIVE_ETH,
      tokenOut: FAME,
      amountIn: 1_000_000_000_000_000n,
      minAmountOutAfterFee: 1n,
      callValue: 1_000_000_000_000_000n,
      funding: {
        type: "native-eth",
        amount: 1_000_000_000_000_000n
      },
      legs: [
        {
          poolId: "uniswap-v4-zora-eth",
          tokenIn: NATIVE_ETH,
          tokenOut: ZORA,
          amountMode: "Exact",
          amount: 1_000_000_000_000_000n,
          minAmountOut: ethToZora,
          quotedAmountOut: ethToZora
        },
        {
          poolId: "uniswap-v4-basedflick-zora",
          tokenIn: ZORA,
          tokenOut: BASEDFLICK,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "slipstream-basedflick-fame",
          tokenIn: BASEDFLICK,
          tokenOut: FAME,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({
        nativeEth: true,
        permit2UniversalRouter: true,
        v4Hooks: true,
        v4HookAddress: true
      }),
      candidateSummary: ["Uses the pinned ETH -> ZORA fixture minimum, then router-computed All mode for downstream hops."]
    },
    {
      id: "solver-weth-split-fame",
      description: "Production split route: WETH splits across Solidly and Uniswap V2 into final FAME.",
      tokenIn: WETH,
      tokenOut: FAME,
      amountIn: 1_000_000_000_000_000n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "native-weth-wrap",
        token: WETH,
        amount: 1_000_000_000_000_000n
      },
      legs: [
        {
          poolId: "scale-equalizer-weth-fame",
          tokenIn: WETH,
          tokenOut: FAME,
          amountMode: "Exact",
          amount: 500_000_000_000_000n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "uniswap-v2-fame-direct",
          tokenIn: WETH,
          tokenOut: FAME,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ weth: true, split: true }),
      candidateSummary: ["Uses exact first branch amount and All for the remaining WETH branch."]
    },
    {
      id: "solver-usdc-split-frxusd-merge-fame",
      description: "Production split-then-merge route: USDC splits into frxUSD through two venues, then merges to FAME.",
      tokenIn: USDC,
      tokenOut: FAME,
      amountIn: 1_000_000n,
      minAmountOutAfterFee: 1n,
      callValue: 0n,
      funding: {
        type: "deal-erc20",
        token: USDC,
        amount: 1_000_000n,
        justification: "User-side USDC balance setup avoids mutating venue pools or FAME DN404 accounting."
      },
      legs: [
        {
          poolId: "scale-equalizer-usdc-frxusd",
          tokenIn: USDC,
          tokenOut: FRXUSD,
          amountMode: "Exact",
          amount: 500_000n,
          minAmountOut: 1n,
          quotedAmountOut: 1n,
          solidlyRoutes: [{ from: USDC, to: FRXUSD, stable: true }]
        },
        {
          poolId: "slipstream-usdc-frxusd",
          tokenIn: USDC,
          tokenOut: FRXUSD,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        },
        {
          poolId: "scale-equalizer-frxusd-fame",
          tokenIn: FRXUSD,
          tokenOut: FAME,
          amountMode: "All",
          amount: 0n,
          minAmountOut: 1n,
          quotedAmountOut: 1n
        }
      ],
      capabilities: baseCapabilities({ split: true, splitThenMerge: true }),
      candidateSummary: ["Uses exact first branch amount and All for the remaining USDC and merged frxUSD balances."]
    }
  ];
}

export function compileRoutes(config: SupportedPoolConfig, context: CompileContext = DEFAULT_COMPILE_CONTEXT): CompiledRoute[] {
  return candidateRoutes(config).map((candidate) => {
    const compiled = buildCompiledRoute(config, candidate, context);
    if (compiled.route.minAmountOutAfterFee > postFeeMinimum(1n) && compiled.route.minAmountOutAfterFee !== 1n) {
      throw new Error(`Unexpected final minimum policy for ${compiled.id}`);
    }
    return compiled;
  });
}
