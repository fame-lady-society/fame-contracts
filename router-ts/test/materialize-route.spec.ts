import { describe, expect, test } from "bun:test";
import { decodeAbiParameters } from "viem";
import { aerodromeV2PayloadAbi } from "../src/adapters/aerodromeV2.js";
import { decodeUniversalRouterV4Payload } from "../src/adapters/universalRouterV4.js";
import { generateOutputs } from "../src/artifacts/writeArtifacts.js";
import {
  materializeProductionRouteFromJson,
  productionCalldataFromArtifact,
  universalRouterV3MaterializePayloadAbi
} from "../src/materializeRoute.js";

const routerAddress = "0x0000000000000000000000000000000000002001";
const recipient = "0x0000000000000000000000000000000000002002";
const now = 1_800_000_000n;
const deadline = now + 900n;

function artifact(id: string) {
  const found = generateOutputs().routeArtifacts.find((candidate) => candidate.id === id);
  if (found === undefined) throw new Error(`Missing route artifact ${id}`);
  return found;
}

function positiveLegMinimums(legCount: number): bigint[] {
  return Array.from({ length: legCount }, () => 2n);
}

function expectThrows(fn: () => unknown, pattern: RegExp): void {
  try {
    fn();
  } catch (error) {
    expect(error instanceof Error ? error.message : String(error)).toMatch(pattern);
    return;
  }
  throw new Error("Expected function to throw");
}

describe("production route materialization", () => {
  test("patches Universal Router payload recipients and deadlines to the deployed router", () => {
    const source = artifact("solver-fame-basedflick-zora-usdc");
    const materialized = materializeProductionRouteFromJson(source.route, {
      routerAddress,
      recipient,
      deadline,
      now,
      minAmountOutAfterFee: 10n,
      legMinAmountOut: positiveLegMinimums(source.route.legs.length)
    });

    expect(materialized.route.recipient).toBe(recipient);
    expect(materialized.route.deadline).toBe(deadline);
    expect(materialized.route.minAmountOutAfterFee).toBe(10n);
    expect(materialized.routeHash).not.toBe(source.routeHash);

    const v4Leg = materialized.route.legs.find((leg) => leg.venue === "UniswapV4");
    if (v4Leg === undefined) throw new Error("Expected V4 leg");
    const v4Payload = decodeUniversalRouterV4Payload(v4Leg.data);
    expect(v4Payload.recipient).toBe(routerAddress);
    expect(v4Payload.deadline).toBe(deadline);
    expect(v4Payload.minAmountOut).toBe(v4Leg.minAmountOut);
    expect(v4Payload.amountIn).toBe(v4Leg.amount);

    const v3Leg = materialized.route.legs.find((leg) => leg.venue === "UniswapV3");
    if (v3Leg === undefined) throw new Error("Expected V3 leg");
    const [v3Payload] = decodeAbiParameters(universalRouterV3MaterializePayloadAbi, v3Leg.data);
    expect(v3Payload.recipient).toBe(routerAddress);
    expect(v3Payload.deadline).toBe(deadline);
  });

  test("patches Aerodrome V2 deadlines without dropping the explicit factory", () => {
    const source = artifact("solver-usdc-aerodrome-weth-fame");
    const materialized = materializeProductionRouteFromJson(source.route, {
      routerAddress,
      recipient,
      deadline,
      now,
      minAmountOutAfterFee: 10n,
      legMinAmountOut: positiveLegMinimums(source.route.legs.length)
    });

    const aerodromeLeg = materialized.route.legs.find((leg) => leg.venue === "AerodromeV2");
    if (aerodromeLeg === undefined) throw new Error("Expected Aerodrome V2 leg");
    const [payload] = decodeAbiParameters(aerodromeV2PayloadAbi, aerodromeLeg.data);
    expect(payload.deadline).toBe(deadline);
    expect(payload.routes[0]?.factory.toLowerCase()).toBe("0x420dd381b31aef6683db6b902084cb0ffece40da");
  });

  test("keeps NativeWrap leg minimums encoded as zero", () => {
    const source = artifact("solver-eth-weth-fame");
    const materialized = materializeProductionRouteFromJson(source.route, {
      routerAddress,
      recipient,
      deadline,
      now,
      minAmountOutAfterFee: 10n,
      legMinAmountOut: [0n, 2n]
    });

    expect(materialized.route.legs[0]).toMatchObject({
      venue: "NativeWrap",
      minAmountOut: 0n,
      data: "0x"
    });
  });

  test("preserves explicit intermediate exact amounts in split and merge routes", () => {
    const source = artifact("solver-usdc-split-frxusd-merge-fame");
    const route = cloneJson(source.route);
    route.legs[2].amountMode = "Exact";
    route.legs[2].amountModeOrdinal = 0;
    route.legs[2].amount = "123";

    const materialized = materializeProductionRouteFromJson(route, {
      routerAddress,
      recipient,
      deadline,
      now,
      minAmountOutAfterFee: 10n,
      legMinAmountOut: positiveLegMinimums(route.legs.length)
    });

    expect(materialized.route.legs[2]?.amountMode).toBe("Exact");
    expect(materialized.route.legs[2]?.amount).toBe(123n);
  });

  test("refuses to expose fork-evidence artifacts as production calldata", () => {
    const source = artifact("solver-fame-weth-eth");

    expectThrows(() => productionCalldataFromArtifact(source), /production materialization/);
  });

  test("rejects long-lived fork-evidence deadlines for production materialization", () => {
    const source = artifact("solver-fame-basedflick-zora-usdc");
    expectThrows(() =>
      materializeProductionRouteFromJson(source.route, {
        routerAddress,
        recipient,
        deadline: 4_102_444_800n,
        now,
        minAmountOutAfterFee: 10n,
        legMinAmountOut: positiveLegMinimums(source.route.legs.length)
      }),
    /near-term/);
  });

  test("requires quote-derived production minimums", () => {
    const source = artifact("solver-fame-basedflick-zora-usdc");
    expectThrows(() =>
      materializeProductionRouteFromJson(source.route, {
        routerAddress,
        recipient,
        deadline,
        now,
        minAmountOutAfterFee: 0n,
        legMinAmountOut: positiveLegMinimums(source.route.legs.length)
      }),
    /final minimum/);

    expectThrows(() =>
      materializeProductionRouteFromJson(source.route, {
        routerAddress,
        recipient,
        deadline,
        now,
        minAmountOutAfterFee: 10n,
        legMinAmountOut: [1n]
      }),
    /minimum for every leg/);
  });
});

function cloneJson<T>(value: T): any {
  return JSON.parse(JSON.stringify(value));
}
