import { encodeAbiParameters, type Address, type Hex } from "viem";
import type { RouteLeg, SolidlyPoolConfig } from "../compiler/types.js";
import type { BuildLegInput, VenuePayloadEncoder } from "./types.js";

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

export interface SolidlyRouteHop {
  from: Address;
  to: Address;
  stable: boolean;
}

export function encodeSolidlyPayload(routes: SolidlyRouteHop[], deadline: bigint): Hex {
  if (routes.length === 0) throw new Error("Solidly payload requires at least one route hop");
  return encodeAbiParameters(solidlyPayloadAbi, [{ routes, deadline }]);
}

export const solidlyEncoder: VenuePayloadEncoder<SolidlyPoolConfig | SolidlyRouteHop[]> = {
  venue: "Solidly",
  encode(input: BuildLegInput, config: SolidlyPoolConfig | SolidlyRouteHop[]): Hex {
    const routes = Array.isArray(config)
      ? config
      : [{ from: input.tokenIn, to: input.tokenOut, stable: config.stable }];
    return encodeSolidlyPayload(routes, input.deadline);
  },
  buildLeg(input: BuildLegInput, config: SolidlyPoolConfig | SolidlyRouteHop[], recipient: Address): RouteLeg {
    void recipient;
    return {
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      venue: "Solidly",
      amountMode: "Exact",
      amount: input.amount,
      minAmountOut: input.minAmountOut,
      target: input.target,
      data: this.encode(input, config, recipient)
    };
  }
};
