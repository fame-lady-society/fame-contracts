import { encodeAbiParameters, encodePacked, type Address, type Hex } from "viem";
import type { RouteLeg, UniswapV3PoolConfig } from "../compiler/types.js";
import type { BuildLegInput, VenuePayloadEncoder } from "./types.js";

const v3PayloadAbi = [
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

export function encodeV3Path(tokenIn: Address, fee: number, tokenOut: Address): Hex {
  return encodePacked(["address", "uint24", "address"], [tokenIn, fee, tokenOut]);
}

export function encodeUniversalRouterV3Payload(params: {
  tokenIn: Address;
  tokenOut: Address;
  fee: number;
  deadline: bigint;
  recipient: Address;
}): Hex {
  return encodeAbiParameters(v3PayloadAbi, [
    {
      path: encodeV3Path(params.tokenIn, params.fee, params.tokenOut),
      deadline: params.deadline,
      payerIsUser: true,
      recipient: params.recipient
    }
  ]);
}

export const universalRouterV3Encoder: VenuePayloadEncoder<UniswapV3PoolConfig> = {
  venue: "UniswapV3",
  encode(input: BuildLegInput, config: UniswapV3PoolConfig, recipient: Address): Hex {
    return encodeUniversalRouterV3Payload({
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      fee: config.fee,
      deadline: input.deadline,
      recipient
    });
  },
  buildLeg(input: BuildLegInput, config: UniswapV3PoolConfig, recipient: Address): RouteLeg {
    return {
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      venue: "UniswapV3",
      amountMode: "Exact",
      amount: input.amount,
      minAmountOut: input.minAmountOut,
      target: input.target,
      data: this.encode(input, config, recipient)
    };
  }
};
