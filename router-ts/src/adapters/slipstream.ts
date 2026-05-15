import { encodeAbiParameters, type Address, type Hex } from "viem";
import type { RouteLeg, SlipstreamPoolConfig } from "../compiler/types.js";
import type { BuildLegInput, VenuePayloadEncoder } from "./types.js";

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

export function encodeSlipstreamPayload(params: {
  router: Address;
  factory: Address;
  tokenIn: Address;
  tokenOut: Address;
  tickSpacing: number;
  sqrtPriceLimitX96: bigint;
  deadline: bigint;
}): Hex {
  return encodeAbiParameters(slipstreamPayloadAbi, [params]);
}

export const slipstreamEncoder: VenuePayloadEncoder<SlipstreamPoolConfig> = {
  venue: "Slipstream",
  encode(input: BuildLegInput, config: SlipstreamPoolConfig): Hex {
    return encodeSlipstreamPayload({
      router: config.router,
      factory: config.factory,
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      tickSpacing: config.tickSpacing,
      sqrtPriceLimitX96: 0n,
      deadline: input.deadline
    });
  },
  buildLeg(input: BuildLegInput, config: SlipstreamPoolConfig, recipient: Address): RouteLeg {
    void recipient;
    return {
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      venue: config.venue === "aerodrome-slipstream2" ? "Slipstream2" : "Slipstream",
      amountMode: "Exact",
      amount: input.amount,
      minAmountOut: input.minAmountOut,
      target: input.target,
      data: this.encode(input, config, recipient)
    };
  }
};
