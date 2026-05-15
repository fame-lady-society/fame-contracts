import { describe, expect, test } from "bun:test";
import { decodeUniversalRouterV4Payload } from "../src/adapters/universalRouterV4.js";
import { routeFromJson } from "../src/artifacts/schema.js";
import { generateOutputs } from "../src/artifacts/writeArtifacts.js";
import { compileRoutes } from "../src/compiler/compileRoute.js";
import { loadSupportedBasePools } from "../src/config/base.js";
import { NATIVE_ETH } from "../src/config/tokens.js";
import type { GapMatrixFile } from "../src/matrix/types.js";

describe("solver artifacts", () => {
  test("records composed, split, and split-then-merge evidence", () => {
    const artifacts = generateOutputs().routeArtifacts;
    expect(artifacts.map((artifact) => artifact.id)).toEqual([
      "solver-eth-weth-fame",
      "solver-eth-zora-basedflick-fame",
      "solver-fame-basedflick-zora-eth",
      "solver-fame-basedflick-zora-usdc",
      "solver-fame-basedflick-zora-weth",
      "solver-fame-weth-eth",
      "solver-usdc-aerodrome-weth-fame",
      "solver-usdc-split-frxusd-merge-fame",
      "solver-usdc-zora-basedflick-fame",
      "solver-weth-split-fame"
    ]);
    expect(artifacts.find((artifact) => artifact.id === "solver-weth-split-fame")?.capabilities.split).toBe(true);
    expect(
      artifacts.find((artifact) => artifact.id === "solver-usdc-split-frxusd-merge-fame")?.capabilities.splitThenMerge
    ).toBe(true);
    expect(artifacts.find((artifact) => artifact.id === "solver-fame-basedflick-zora-weth")?.capabilities).toMatchObject({
      v4Hooks: true,
      v4HookAddress: true,
      v4NonEmptyHookData: false,
      v4MultiHopPathKeys: false
    });
    expect(artifacts.find((artifact) => artifact.id === "solver-weth-split-fame")?.capabilities).toMatchObject({
      v4Hooks: false,
      v4HookAddress: false,
      v4NonEmptyHookData: false,
      v4MultiHopPathKeys: false
    });
    for (const artifact of artifacts) {
      expect(artifact).toMatchObject({
        artifactKind: "fork-evidence",
        productionExecutable: false,
        executorBinding: "test-only",
        minimumPolicy: "fork-smoke-one-wei"
      });
    }
  });

  test("marks native ETH FAME directions as generated fork evidence", () => {
    const outputs = generateOutputs();
    const matrix = JSON.parse(outputs.gapMatrixJson) as GapMatrixFile;

    expect(matrix.rows.find((row) => row.id === "fame-to-eth")).toMatchObject({
      supported: true,
      executable: "executable",
      tsGenerated: true,
      forkTested: true,
      routeArtifactId: "solver-fame-weth-eth",
      blocker: null
    });
    expect(matrix.rows.find((row) => row.id === "eth-to-fame")).toMatchObject({
      supported: true,
      executable: "executable",
      tsGenerated: true,
      forkTested: true,
      routeArtifactId: "solver-eth-weth-fame",
      blocker: null
    });
  });

  test("marks NativeWrap route artifacts explicitly", () => {
    const artifacts = generateOutputs().routeArtifacts;
    const ethWrap = artifacts.find((artifact) => artifact.id === "solver-eth-weth-fame");
    const wethUnwrap = artifacts.find((artifact) => artifact.id === "solver-fame-weth-eth");

    expect(ethWrap?.capabilities).toMatchObject({ nativeEth: true, weth: true, nativeWrap: true });
    expect(ethWrap?.route.legs[0]).toMatchObject({
      venue: "NativeWrap",
      venueOrdinal: 6,
      amountMode: "Exact",
      minAmountOut: "0",
      target: "0x4200000000000000000000000000000000000006",
      data: "0x"
    });
    expect(ethWrap?.debug.perLegEffectiveMinimums[0]).toBe(ethWrap?.route.legs[0]?.amount);

    expect(wethUnwrap?.capabilities).toMatchObject({ nativeEth: true, weth: true, nativeWrap: true });
    expect(wethUnwrap?.route.legs[1]).toMatchObject({
      venue: "NativeWrap",
      venueOrdinal: 6,
      amountMode: "All",
      amount: "0",
      minAmountOut: "0",
      target: "0x4200000000000000000000000000000000000006",
      data: "0x"
    });
    expect(wethUnwrap?.debug.perLegEffectiveMinimums[1]).not.toBe("0");
  });

  test("generates a creator-coin catalog artifact", () => {
    const outputs = generateOutputs();
    const catalog = JSON.parse(outputs.creatorCoinCatalogJson);

    expect(catalog.entries).toHaveLength(1);
    expect(catalog.entries[0]).toMatchObject({
      id: "creator-basedflick-zora",
      poolConfigId: "uniswap-v4-basedflick-zora",
      v4PoolId: "0x0fe6333346fcd0ffa4be3fda91f271bda52c6755f604b06483b709666d363628",
      swapHookDataPolicy: "empty",
      hookData: "0x",
      evidenceTypes: ["hook-address-swap"],
      proves: {
        hookAddressSwap: true,
        nonEmptySwapHookData: false
      }
    });
  });

  test("route artifacts derive hook coverage claims from encoded V4 payloads", () => {
    for (const artifact of generateOutputs().routeArtifacts) {
      const v4Payloads = artifact.route.legs
        .filter((leg) => leg.venue === "UniswapV4")
        .map((leg) => decodeUniversalRouterV4Payload(leg.data));
      const hasV4 = v4Payloads.length > 0;
      const hasHookAddress = v4Payloads.some((payload) => payload.hooks.toLowerCase() !== NATIVE_ETH);
      const hasNonEmptyHookData = v4Payloads.some((payload) => payload.hookData !== "0x");

      expect(artifact.capabilities.v4Hooks).toBe(hasV4);
      expect(artifact.capabilities.v4HookAddress).toBe(hasHookAddress);
      expect(artifact.capabilities.v4NonEmptyHookData).toBe(hasNonEmptyHookData);
      expect(artifact.capabilities.v4MultiHopPathKeys).toBe(false);
    }
  });

  test("gap matrix route rows mirror referenced artifact capabilities", () => {
    const outputs = generateOutputs();
    const matrix = JSON.parse(outputs.gapMatrixJson) as GapMatrixFile;
    const artifactsById = new Map(outputs.routeArtifacts.map((artifact) => [artifact.id, artifact]));

    for (const row of matrix.rows) {
      if (row.routeArtifactId === null) continue;
      const artifact = artifactsById.get(row.routeArtifactId);
      if (artifact === undefined) throw new Error(`Missing artifact ${row.routeArtifactId}`);
      expect(row.capabilities).toEqual(artifact.capabilities);
    }
  });

  test("catalog hook-address proof links to generated fork-tested route artifacts", () => {
    const outputs = generateOutputs();
    const catalog = JSON.parse(outputs.creatorCoinCatalogJson);
    const matrix = JSON.parse(outputs.gapMatrixJson) as GapMatrixFile;
    const routeIds = new Set(outputs.routeArtifacts.map((artifact) => artifact.id));

    for (const entry of catalog.entries) {
      if (!entry.proves.hookAddressSwap) continue;
      expect(entry.routeArtifactIds.length).toBeGreaterThan(0);
      for (const routeArtifactId of entry.routeArtifactIds) {
        expect(routeIds.has(routeArtifactId)).toBe(true);
        const row = matrix.rows.find((candidate) => candidate.routeArtifactId === routeArtifactId);
        expect(row?.forkTested).toBe(true);
        expect(row?.capabilities.v4HookAddress).toBe(true);
        expect(row?.capabilities.v4NonEmptyHookData).toBe(false);
      }
    }
  });

  test("parameterizes executor in generated Universal Router payloads", () => {
    const executor = "0x0000000000000000000000000000000000002001";
    const recipient = "0x0000000000000000000000000000000000002002";
    const route = compileRoutes(loadSupportedBasePools(), {
      executor,
      recipient,
      deadline: 4_102_444_801n
    }).find((candidate) => candidate.route.legs.some((leg) => leg.venue === "UniswapV4"));
    if (route === undefined) throw new Error("Expected at least one generated route with a V4 leg");
    const v4Leg = route.route.legs.find((leg) => leg.venue === "UniswapV4");
    if (v4Leg === undefined) throw new Error("Expected a V4 leg in the first generated route");

    const payload = decodeUniversalRouterV4Payload(v4Leg.data);
    expect(payload.recipient).toBe(executor);
    expect(route.route.recipient).toBe(recipient);
  });

  test("rejects unknown route JSON enum names even when ordinals are missing", () => {
    const route = cloneJson(firstRouteArtifact().route);
    const leg = route.legs[0];
    if (leg === undefined) throw new Error("Expected route leg");
    leg.venue = "UnknownVenue";
    delete leg.venueOrdinal;

    expectThrows(() => routeFromJson(route), /Unknown venue UnknownVenue/);
  });

  test("rejects missing enum ordinals and unsupported schema versions", () => {
    const missingOrdinalRoute = cloneJson(firstRouteArtifact().route);
    const leg = missingOrdinalRoute.legs[0];
    if (leg === undefined) throw new Error("Expected route leg");
    delete leg.amountModeOrdinal;

    expectThrows(() => routeFromJson(missingOrdinalRoute), /Missing amount mode ordinal/);

    const unsupportedVersionRoute = cloneJson(firstRouteArtifact().route);
    unsupportedVersionRoute.version = 2;

    expectThrows(() => routeFromJson(unsupportedVersionRoute), /Unsupported route schema version 2/);
  });
});

function cloneJson<T>(value: T): any {
  return JSON.parse(JSON.stringify(value));
}

function firstRouteArtifact() {
  const artifact = generateOutputs().routeArtifacts[0];
  if (artifact === undefined) throw new Error("Expected generated route artifact");
  return artifact;
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
