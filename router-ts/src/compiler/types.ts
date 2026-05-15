import type { Address, Hex } from "viem";

export const SCHEMA_VERSION = 1;
export const PINNED_BASE_BLOCK = 45_884_844;
export const DETERMINISTIC_DEADLINE = 4_102_444_800n;
export const BPS_DENOMINATOR = 10_000n;
export const FEE_DENOMINATOR = 1_000_000n;
export const DEFAULT_FEE_PPM = 2_222n;
export const MAX_PAYLOAD_BYTES = 2_048;

export const VenueFamily = {
  Solidly: 0,
  UniswapV2: 1,
  Slipstream: 2,
  Slipstream2: 3,
  UniswapV3: 4,
  UniswapV4: 5,
  NativeWrap: 6,
  AerodromeV2: 7
} as const;

export type VenueFamilyName = keyof typeof VenueFamily;
export type VenueFamilyOrdinal = (typeof VenueFamily)[VenueFamilyName];

export const AmountMode = {
  Exact: 0,
  BalanceBps: 1,
  All: 2
} as const;

export type AmountModeName = keyof typeof AmountMode;
export type AmountModeOrdinal = (typeof AmountMode)[AmountModeName];

export interface RouteLeg {
  tokenIn: Address;
  tokenOut: Address;
  venue: VenueFamilyName;
  amountMode: AmountModeName;
  amount: bigint;
  minAmountOut: bigint;
  target: Address;
  data: Hex;
}

export interface Route {
  version: 1;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minAmountOutAfterFee: bigint;
  recipient: Address;
  deadline: bigint;
  legs: RouteLeg[];
}

export type Funding =
  | {
      type: "deal-erc20";
      token: Address;
      amount: bigint;
      justification: string;
    }
  | {
      type: "native-weth-wrap";
      token: Address;
      amount: bigint;
    }
  | {
      type: "native-eth";
      amount: bigint;
    }
  | {
      type: "acquire-via-route";
      routeId: string;
      amountIn: bigint;
      expectedAmountOut: bigint;
    };

export interface RouteCapabilities {
  nativeEth: boolean;
  weth: boolean;
  nativeWrap: boolean;
  permit2UniversalRouter: boolean;
  v4Hooks: boolean;
  v4HookAddress: boolean;
  v4NonEmptyHookData: boolean;
  v4MultiHopPathKeys: boolean;
  split: boolean;
  splitThenMerge: boolean;
}

export interface CompiledRoute {
  id: string;
  description: string;
  poolIds: string[];
  route: Route;
  executionContext: {
    executor: Address;
    recipient: Address;
    deadline: bigint;
  };
  callValue: bigint;
  funding: Funding;
  capabilities: RouteCapabilities;
  debug: RouteDebug;
}

export interface RouteDebug {
  selectedPath: Address[];
  candidateSummary: string[];
  amountModes: AmountModeName[];
  venueFamilies: VenueFamilyName[];
  perLegMinimums: bigint[];
  perLegEffectiveMinimums: bigint[];
  perLegQuoteValues: bigint[];
  finalPostFeeMinimum: bigint;
}

export interface PoolConfigBase {
  id: string;
  venue: string;
  router: Address;
}

export interface SolidlyPoolConfig extends PoolConfigBase {
  venue: "solidly";
  pool: Address;
  token0: Address;
  token1: Address;
  stable: boolean;
  feeBps: number;
}

export interface UniswapV2PoolConfig extends PoolConfigBase {
  venue: "uniswap-v2";
  pool: Address;
  token0: Address;
  token1: Address;
  feeBps: number;
}

export interface SlipstreamPoolConfig extends PoolConfigBase {
  venue: "aerodrome-slipstream" | "aerodrome-slipstream2";
  factory: Address;
  pool: Address;
  token0: Address;
  token1: Address;
  tickSpacing: number;
  feeBps: number;
}

export interface AerodromeV2PoolConfig extends PoolConfigBase {
  venue: "aerodrome-v2";
  factory: Address;
  pool: Address;
  token0: Address;
  token1: Address;
  stable: boolean;
  feeBps: number;
}

export interface UniswapV3PoolConfig extends PoolConfigBase {
  venue: "uniswap-v3";
  pool: Address;
  token0: Address;
  token1: Address;
  fee: number;
  tickSpacing: number;
}

export interface UniswapV4PoolConfig extends PoolConfigBase {
  venue: "uniswap-v4";
  poolManager: Address;
  stateView: Address;
  poolId: Hex;
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
  hookData: Hex;
}

export type PoolConfig =
  | SolidlyPoolConfig
  | UniswapV2PoolConfig
  | SlipstreamPoolConfig
  | AerodromeV2PoolConfig
  | UniswapV3PoolConfig
  | UniswapV4PoolConfig;

export interface SupportedPoolConfig {
  schemaVersion: 1;
  status: string;
  pinnedBaseBlock: number;
  pools: PoolConfig[];
}
