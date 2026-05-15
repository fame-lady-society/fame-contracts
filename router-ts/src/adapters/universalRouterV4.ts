import { decodeAbiParameters, encodeAbiParameters, keccak256, type Address, type Hex } from "viem";
import type { RouteLeg, UniswapV4PoolConfig } from "../compiler/types.js";
import type { BuildLegInput, VenuePayloadEncoder } from "./types.js";

const v4PayloadAbi = [
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

const v4HookDataKeyAbi = [
  { type: "address", name: "currency0" },
  { type: "address", name: "currency1" },
  { type: "uint24", name: "fee" },
  { type: "int24", name: "tickSpacing" },
  { type: "address", name: "hooks" },
  { type: "bytes32", name: "hookDataHash" }
] as const;

export interface V4PayloadInput {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minAmountOut: bigint;
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
  hookData: Hex;
  deadline: bigint;
  recipient: Address;
}

export function encodeUniversalRouterV4Payload(params: V4PayloadInput): Hex {
  const zeroForOne = params.currency0.toLowerCase() === params.tokenIn.toLowerCase();
  return encodeAbiParameters(v4PayloadAbi, [
    {
      tokenIn: params.tokenIn,
      tokenOut: params.tokenOut,
      amountIn: params.amountIn,
      minAmountOut: params.minAmountOut,
      currency0: params.currency0,
      currency1: params.currency1,
      zeroForOne,
      fee: params.fee,
      tickSpacing: params.tickSpacing,
      hooks: params.hooks,
      hookData: params.hookData,
      deadline: params.deadline,
      recipient: params.recipient,
      payerIsUser: false
    }
  ]);
}

export function decodeUniversalRouterV4Payload(data: Hex): V4PayloadInput & { zeroForOne: boolean; payerIsUser: boolean } {
  const [payload] = decodeAbiParameters(v4PayloadAbi, data);
  return payload;
}

export function v4HookDataKey(params: Pick<V4PayloadInput, "currency0" | "currency1" | "fee" | "tickSpacing" | "hooks" | "hookData">): Hex {
  return keccak256(
    encodeAbiParameters(v4HookDataKeyAbi, [
      params.currency0,
      params.currency1,
      params.fee,
      params.tickSpacing,
      params.hooks,
      keccak256(params.hookData)
    ])
  );
}

export const universalRouterV4Encoder: VenuePayloadEncoder<UniswapV4PoolConfig> = {
  venue: "UniswapV4",
  encode(input: BuildLegInput, config: UniswapV4PoolConfig, recipient: Address): Hex {
    return encodeUniversalRouterV4Payload({
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      amountIn: input.amount,
      minAmountOut: input.minAmountOut,
      currency0: config.currency0,
      currency1: config.currency1,
      fee: config.fee,
      tickSpacing: config.tickSpacing,
      hooks: config.hooks,
      hookData: config.hookData,
      deadline: input.deadline,
      recipient
    });
  },
  buildLeg(input: BuildLegInput, config: UniswapV4PoolConfig, recipient: Address): RouteLeg {
    return {
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      venue: "UniswapV4",
      amountMode: "Exact",
      amount: input.amount,
      minAmountOut: input.minAmountOut,
      target: input.target,
      data: this.encode(input, config, recipient)
    };
  }
};
