import type { Address, Hex } from "viem";
import {
  AmountMode,
  PINNED_BASE_BLOCK,
  SCHEMA_VERSION,
  VenueFamily,
  type AmountModeName,
  type CompiledRoute,
  type Funding,
  type Route,
  type RouteCapabilities,
  type RouteDebug,
  type RouteLeg,
  type VenueFamilyName
} from "../compiler/types.js";

export interface JsonLeg {
  tokenIn: Address;
  tokenOut: Address;
  venue: VenueFamilyName;
  venueOrdinal: number;
  amountMode: AmountModeName;
  amountModeOrdinal: number;
  amount: string;
  minAmountOut: string;
  target: Address;
  data: Hex;
}

export interface JsonRoute {
  version: 1;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: string;
  minAmountOutAfterFee: string;
  recipient: Address;
  deadline: string;
  legs: JsonLeg[];
}

export interface RouteArtifact {
  artifactKind: "fork-evidence";
  productionExecutable: false;
  executorBinding: "test-only";
  minimumPolicy: "fork-smoke-one-wei";
  id: string;
  description: string;
  poolIds: string[];
  executionContext: JsonExecutionContext;
  route: JsonRoute;
  abiEncodedRoute: Hex;
  routeHash: Hex;
  callValue: string;
  funding: JsonFunding;
  capabilities: RouteCapabilities;
  debug: JsonRouteDebug;
}

export interface JsonExecutionContext {
  executor: Address;
  recipient: Address;
  deadline: string;
}

export type JsonFunding =
  | {
      type: "deal-erc20";
      token: Address;
      amount: string;
      justification: string;
    }
  | {
      type: "native-weth-wrap";
      token: Address;
      amount: string;
    }
  | {
      type: "native-eth";
      amount: string;
    }
  | {
      type: "acquire-via-route";
      routeId: string;
      amountIn: string;
      expectedAmountOut: string;
    };

export interface JsonRouteDebug {
  selectedPath: Address[];
  candidateSummary: string[];
  amountModes: AmountModeName[];
  venueFamilies: VenueFamilyName[];
  perLegMinimums: string[];
  perLegEffectiveMinimums: string[];
  perLegQuoteValues: string[];
  finalPostFeeMinimum: string;
}

export interface SolverRoutesFile {
  schemaVersion: 1;
  status: "generated-fork-evidence";
  pinnedBaseBlock: number;
  generator: "router-ts";
  routes: RouteArtifact[];
}

export interface ParityVector {
  id: string;
  route: JsonRoute;
  abiEncodedRoute: Hex;
  routeHash: Hex;
}

export interface ParityVectorFile {
  schemaVersion: 1;
  pinnedBaseBlock: number;
  vectors: ParityVector[];
}

export function toJsonRoute(route: Route): JsonRoute {
  return {
    version: SCHEMA_VERSION,
    tokenIn: route.tokenIn,
    tokenOut: route.tokenOut,
    amountIn: route.amountIn.toString(),
    minAmountOutAfterFee: route.minAmountOutAfterFee.toString(),
    recipient: route.recipient,
    deadline: route.deadline.toString(),
    legs: route.legs.map(toJsonLeg)
  };
}

export function toJsonLeg(leg: RouteLeg): JsonLeg {
  return {
    tokenIn: leg.tokenIn,
    tokenOut: leg.tokenOut,
    venue: leg.venue,
    venueOrdinal: VenueFamily[leg.venue],
    amountMode: leg.amountMode,
    amountModeOrdinal: AmountMode[leg.amountMode],
    amount: leg.amount.toString(),
    minAmountOut: leg.minAmountOut.toString(),
    target: leg.target,
    data: leg.data
  };
}

export function routeFromJson(route: JsonRoute): Route {
  if (route.version !== SCHEMA_VERSION) {
    throw new Error(`Unsupported route schema version ${String(route.version)}`);
  }
  if (!Array.isArray(route.legs)) {
    throw new Error("Route JSON legs must be an array");
  }

  return {
    version: route.version,
    tokenIn: route.tokenIn,
    tokenOut: route.tokenOut,
    amountIn: BigInt(route.amountIn),
    minAmountOutAfterFee: BigInt(route.minAmountOutAfterFee),
    recipient: route.recipient,
    deadline: BigInt(route.deadline),
    legs: route.legs.map(legFromJson)
  };
}

export function legFromJson(leg: JsonLeg): RouteLeg {
  const venue = checkedEnumName(VenueFamily, "venue", leg.venue, leg.venueOrdinal) as VenueFamilyName;
  const amountMode = checkedEnumName(
    AmountMode,
    "amount mode",
    leg.amountMode,
    leg.amountModeOrdinal
  ) as AmountModeName;

  return {
    tokenIn: leg.tokenIn,
    tokenOut: leg.tokenOut,
    venue,
    amountMode,
    amount: BigInt(leg.amount),
    minAmountOut: BigInt(leg.minAmountOut),
    target: leg.target,
    data: leg.data
  };
}

function checkedEnumName<T extends Record<string, number>>(
  enumValues: T,
  label: string,
  name: unknown,
  ordinal: unknown
): keyof T & string {
  if (typeof name !== "string" || !Object.prototype.hasOwnProperty.call(enumValues, name)) {
    throw new Error(`Unknown ${label} ${String(name)}`);
  }
  if (typeof ordinal !== "number") {
    throw new Error(`Missing ${label} ordinal for ${name}`);
  }
  if (enumValues[name] !== ordinal) {
    throw new Error(`${capitalize(label)} ordinal mismatch for ${name}`);
  }
  return name;
}

function capitalize(value: string): string {
  return `${value.slice(0, 1).toUpperCase()}${value.slice(1)}`;
}

export function toJsonFunding(funding: Funding): JsonFunding {
  switch (funding.type) {
    case "deal-erc20":
      return { ...funding, amount: funding.amount.toString() };
    case "native-weth-wrap":
      return { ...funding, amount: funding.amount.toString() };
    case "native-eth":
      return { ...funding, amount: funding.amount.toString() };
    case "acquire-via-route":
      return {
        ...funding,
        amountIn: funding.amountIn.toString(),
        expectedAmountOut: funding.expectedAmountOut.toString()
      };
  }
}

export function toJsonDebug(debug: RouteDebug): JsonRouteDebug {
  return {
    selectedPath: debug.selectedPath,
    candidateSummary: debug.candidateSummary,
    amountModes: debug.amountModes,
    venueFamilies: debug.venueFamilies,
    perLegMinimums: debug.perLegMinimums.map((amount) => amount.toString()),
    perLegEffectiveMinimums: debug.perLegEffectiveMinimums.map((amount) => amount.toString()),
    perLegQuoteValues: debug.perLegQuoteValues.map((amount) => amount.toString()),
    finalPostFeeMinimum: debug.finalPostFeeMinimum.toString()
  };
}

export function toRouteArtifact(compiled: CompiledRoute, abiEncodedRoute: Hex, routeHash: Hex): RouteArtifact {
  return {
    artifactKind: "fork-evidence",
    productionExecutable: false,
    executorBinding: "test-only",
    minimumPolicy: "fork-smoke-one-wei",
    id: compiled.id,
    description: compiled.description,
    poolIds: compiled.poolIds,
    executionContext: {
      executor: compiled.executionContext.executor,
      recipient: compiled.executionContext.recipient,
      deadline: compiled.executionContext.deadline.toString()
    },
    route: toJsonRoute(compiled.route),
    abiEncodedRoute,
    routeHash,
    callValue: compiled.callValue.toString(),
    funding: toJsonFunding(compiled.funding),
    capabilities: compiled.capabilities,
    debug: toJsonDebug(compiled.debug)
  };
}

export function solverRoutesFile(routes: RouteArtifact[]): SolverRoutesFile {
  return {
    schemaVersion: SCHEMA_VERSION,
    status: "generated-fork-evidence",
    pinnedBaseBlock: PINNED_BASE_BLOCK,
    generator: "router-ts",
    routes
  };
}
