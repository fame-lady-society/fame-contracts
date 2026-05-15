import { DEFAULT_FEE_PPM, FEE_DENOMINATOR } from "./types.js";

export function postFeeMinimum(grossAmountOut: bigint): bigint {
  const fee = (grossAmountOut * DEFAULT_FEE_PPM) / FEE_DENOMINATOR;
  return grossAmountOut - fee;
}
