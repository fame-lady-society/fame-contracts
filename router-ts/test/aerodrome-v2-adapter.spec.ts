import { describe, expect, test } from "bun:test";
import { decodeAbiParameters } from "viem";
import { aerodromeV2Encoder, encodeAerodromeV2Payload } from "../src/adapters/aerodromeV2.js";
import { encodeSolidlyPayload } from "../src/adapters/solidly.js";
import { loadSupportedBasePools } from "../src/config/base.js";
import { DETERMINISTIC_DEADLINE, VenueFamily } from "../src/compiler/types.js";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const USDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
const WETH = "0x4200000000000000000000000000000000000006";
const ROUTER = "0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43";
const FACTORY = "0x420dd381b31aef6683db6b902084cb0ffece40da";
const POOL = "0xcdac0d6c6c59727a65f871236188350531885c43";
const RECIPIENT = "0x0000000000000000000000000000000000001003";

const aerodromeV2PayloadAbi = [
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

describe("Aerodrome V2 adapter encoding", () => {
  test("encodes explicit factory route hops", () => {
    const payload = encodeAerodromeV2Payload(
      [{ from: USDC, to: WETH, stable: false, factory: FACTORY }],
      DETERMINISTIC_DEADLINE
    );

    const [decoded] = decodeAbiParameters(aerodromeV2PayloadAbi, payload);
    expect(decoded.deadline).toBe(DETERMINISTIC_DEADLINE);
    const firstRoute = decoded.routes[0];
    if (firstRoute === undefined) throw new Error("Expected decoded Aerodrome route");
    expect(firstRoute.from.toLowerCase()).toBe(USDC);
    expect(firstRoute.to.toLowerCase()).toBe(WETH);
    expect(firstRoute.stable).toBe(false);
    expect(firstRoute.factory.toLowerCase()).toBe(FACTORY);
  });

  test("builds AerodromeV2 route legs with venue ordinal 7", () => {
    const leg = aerodromeV2Encoder.buildLeg(
      {
        tokenIn: USDC,
        tokenOut: WETH,
        amount: 1_000_000n,
        minAmountOut: 1n,
        target: ROUTER,
        deadline: DETERMINISTIC_DEADLINE
      },
      {
        id: "aerodrome-v2-usdc-weth",
        venue: "aerodrome-v2",
        router: ROUTER,
        factory: FACTORY,
        pool: POOL,
        token0: WETH,
        token1: USDC,
        stable: false,
        feeBps: 30
      },
      RECIPIENT
    );

    expect(leg.venue).toBe("AerodromeV2");
    expect(VenueFamily[leg.venue]).toBe(7);
    expect(leg.target).toBe(ROUTER);
    const [decoded] = decodeAbiParameters(aerodromeV2PayloadAbi, leg.data);
    expect(decoded.routes[0]?.factory.toLowerCase()).toBe(FACTORY);
  });

  test("keeps Solidly payloads three-field only", () => {
    const solidlyPayload = encodeSolidlyPayload([{ from: USDC, to: WETH, stable: false }], DETERMINISTIC_DEADLINE);
    const aerodromePayload = encodeAerodromeV2Payload(
      [{ from: USDC, to: WETH, stable: false, factory: FACTORY }],
      DETERMINISTIC_DEADLINE
    );

    const [decodedSolidly] = decodeAbiParameters(solidlyPayloadAbi, solidlyPayload);
    const firstSolidlyRoute = decodedSolidly.routes[0];
    if (firstSolidlyRoute === undefined) throw new Error("Expected decoded Solidly route");
    expect("factory" in firstSolidlyRoute).toBe(false);
    expectThrows(() => decodeAbiParameters(aerodromeV2PayloadAbi, solidlyPayload));
    expect(aerodromePayload.length).toBeGreaterThan(solidlyPayload.length);
  });

  test("requires factory for aerodrome-v2 fixtures", () => {
    const fixturePath = writeFixture({
      pools: [
        {
          id: "aerodrome-v2-usdc-weth",
          venue: "aerodrome-v2",
          router: ROUTER,
          pool: POOL,
          token0: WETH,
          token1: USDC,
          stable: false,
          feeBps: 30
        }
      ]
    });

    expectThrows(() => loadSupportedBasePools(fixturePath), "Expected string field factory");
  });

  test("does not treat Solidly fixtures with factory metadata as AerodromeV2", () => {
    const fixturePath = writeFixture({
      pools: [
        {
          id: "solidly-usdc-weth",
          venue: "solidly",
          router: ROUTER,
          factory: FACTORY,
          pool: POOL,
          token0: WETH,
          token1: USDC,
          stable: false,
          feeBps: 30
        }
      ]
    });

    const config = loadSupportedBasePools(fixturePath);
    expect(config.pools[0]?.venue).toBe("solidly");
  });
});

function writeFixture(value: { pools: unknown[] }): string {
  const dir = mkdtempSync(join(tmpdir(), "fame-router-ts-"));
  const path = join(dir, "base-v1-pools.json");
  writeFileSync(
    path,
    JSON.stringify({
      schemaVersion: 1,
      status: "test",
      pinnedBaseBlock: 45_884_844,
      pools: value.pools
    })
  );
  return path;
}

function expectThrows(fn: () => unknown, includes?: string): void {
  try {
    fn();
  } catch (error) {
    if (includes !== undefined) {
      expect(error instanceof Error ? error.message : String(error)).toContain(includes);
    }
    return;
  }
  throw new Error("Expected function to throw");
}
