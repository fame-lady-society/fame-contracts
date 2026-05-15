import { encodeAbiParameters, type Address, type Hex } from "viem";
import type { AerodromeV2PoolConfig, RouteLeg } from "../compiler/types.js";
import type { BuildLegInput, VenuePayloadEncoder } from "./types.js";

export const aerodromeV2PayloadAbi = [
  {
    type: "tuple",
    components: [
      {
        name: "routes",
        type: "tuple[]",
        components: [
          { name: "from", type: "address" },
          { name: "to", type: "address" },
          { name: "stable", type: "bool" },
          { name: "factory", type: "address" }
        ]
      },
      { name: "deadline", type: "uint256" }
    ]
  }
] as const;

export interface AerodromeV2RouteHop {
  from: Address;
  to: Address;
  stable: boolean;
  factory: Address;
}

export function encodeAerodromeV2Payload(routes: AerodromeV2RouteHop[], deadline: bigint): Hex {
  if (routes.length === 0) throw new Error("Aerodrome V2 payload requires at least one route hop");
  return encodeAbiParameters(aerodromeV2PayloadAbi, [{ routes, deadline }]);
}

export const aerodromeV2Encoder: VenuePayloadEncoder<AerodromeV2PoolConfig | AerodromeV2RouteHop[]> = {
  venue: "AerodromeV2",
  encode(input: BuildLegInput, config: AerodromeV2PoolConfig | AerodromeV2RouteHop[]): Hex {
    const routes = Array.isArray(config)
      ? config
      : [{ from: input.tokenIn, to: input.tokenOut, stable: config.stable, factory: config.factory }];
    return encodeAerodromeV2Payload(routes, input.deadline);
  },
  buildLeg(input: BuildLegInput, config: AerodromeV2PoolConfig | AerodromeV2RouteHop[], recipient: Address): RouteLeg {
    void recipient;
    return {
      tokenIn: input.tokenIn,
      tokenOut: input.tokenOut,
      venue: "AerodromeV2",
      amountMode: "Exact",
      amount: input.amount,
      minAmountOut: input.minAmountOut,
      target: input.target,
      data: this.encode(input, config, recipient)
    };
  }
};
