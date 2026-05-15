import { encodeAbiParameters, type Address, type Hex } from "viem";
import type { RouteLeg, UniswapV2PoolConfig } from "../compiler/types.js";
import type { BuildLegInput, VenuePayloadEncoder } from "./types.js";

const uniswapV2PayloadAbi = [
  {
    type: "tuple",
    components: [
      { name: "path", type: "address[]" },
      { name: "deadline", type: "uint256" }
    ]
  }
] as const;

export function encodeUniswapV2Payload(path: Address[], deadline: bigint): Hex {
  if (path.length < 2) throw new Error("Uniswap V2 payload requires at least two path tokens");
  return encodeAbiParameters(uniswapV2PayloadAbi, [{ path, deadline }]);
}

export const uniswapV2Encoder: VenuePayloadEncoder<UniswapV2PoolConfig | Address[]> = {
  venue: "UniswapV2",
  encode(input: BuildLegInput, config: UniswapV2PoolConfig | Address[]): Hex {
    const path = Array.isArray(config) ? config : [input.tokenIn, input.tokenOut];
    return encodeUniswapV2Payload(path, input.deadline);
  },
  buildLeg(input: BuildLegInput, config: UniswapV2PoolConfig | Address[], recipient: Address): RouteLeg {
    void recipient;
    return {
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      venue: "UniswapV2",
      amountMode: "Exact",
      amount: input.amount,
      minAmountOut: input.minAmountOut,
      target: input.target,
      data: this.encode(input, config, recipient)
    };
  }
};
