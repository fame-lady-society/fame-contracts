import type { Address, Hex } from "viem";
import type { RouteLeg, VenueFamilyName } from "../compiler/types.js";

export interface BuildLegInput {
  tokenIn: Address;
  tokenOut: Address;
  amount: bigint;
  minAmountOut: bigint;
  target: Address;
  deadline: bigint;
}

export interface VenuePayloadEncoder<TConfig> {
  readonly venue: VenueFamilyName;
  encode(input: BuildLegInput, config: TConfig, recipient: Address): Hex;
  buildLeg(input: BuildLegInput, config: TConfig, recipient: Address): RouteLeg;
}

export function buildLeg<TConfig>(
  encoder: VenuePayloadEncoder<TConfig>,
  input: BuildLegInput,
  config: TConfig,
  recipient: Address
): RouteLeg {
  return encoder.buildLeg(input, config, recipient);
}
