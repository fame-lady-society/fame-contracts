import { encodeAbiParameters, keccak256, type Hex } from "viem";
import { AmountMode, VenueFamily, type Route } from "../compiler/types.js";

const routeAbi = [
  {
    type: "tuple",
    components: [
      { name: "version", type: "uint16" },
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOutAfterFee", type: "uint256" },
      { name: "recipient", type: "address" },
      { name: "deadline", type: "uint256" },
      {
        name: "legs",
        type: "tuple[]",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "venue", type: "uint8" },
          { name: "amountMode", type: "uint8" },
          { name: "amount", type: "uint256" },
          { name: "minAmountOut", type: "uint256" },
          { name: "target", type: "address" },
          { name: "data", type: "bytes" }
        ]
      }
    ]
  }
] as const;

export function encodeRoute(route: Route): Hex {
  return encodeAbiParameters(routeAbi, [
    {
      version: route.version,
      tokenIn: route.tokenIn,
      tokenOut: route.tokenOut,
      amountIn: route.amountIn,
      minAmountOutAfterFee: route.minAmountOutAfterFee,
      recipient: route.recipient,
      deadline: route.deadline,
      legs: route.legs.map((leg) => ({
        tokenIn: leg.tokenIn,
        tokenOut: leg.tokenOut,
        venue: VenueFamily[leg.venue],
        amountMode: AmountMode[leg.amountMode],
        amount: leg.amount,
        minAmountOut: leg.minAmountOut,
        target: leg.target,
        data: leg.data
      }))
    }
  ]);
}

export function hashRoute(route: Route): Hex {
  return keccak256(encodeRoute(route));
}
