import { describe, expect, test } from "bun:test";
import type { SupportedPoolConfig } from "../src/compiler/types.js";
import { buildCreatorCoinCatalog } from "../src/catalog/creatorCoins.js";
import { loadSupportedBasePools } from "../src/config/base.js";
import { BASEDFLICK, NATIVE_ETH, ZORA } from "../src/config/tokens.js";

function expectErrorMessage(action: () => unknown, message: string): void {
  try {
    action();
  } catch (error) {
    if (!(error instanceof Error)) throw error;
    expect(error.message).toContain(message);
    return;
  }
  throw new Error(`Expected error containing: ${message}`);
}

describe("creator-coin catalog", () => {
  const config = loadSupportedBasePools();

  test("classifies basedflick/ZORA as hook-address coverage with empty swap hookData", () => {
    const catalog = buildCreatorCoinCatalog(config);

    expect(catalog.entries).toHaveLength(1);
    const [entry] = catalog.entries;
    if (entry === undefined) throw new Error("Expected catalog entry");

    expect(entry.id).toBe("creator-basedflick-zora");
    expect(entry.poolConfigId).toBe("uniswap-v4-basedflick-zora");
    expect(entry.v4PoolId).toBe("0x0fe6333346fcd0ffa4be3fda91f271bda52c6755f604b06483b709666d363628");
    expect(entry.creatorCoin.toLowerCase()).toBe(BASEDFLICK);
    expect(entry.baseCurrency.toLowerCase()).toBe(ZORA);
    expect(entry.hooks).not.toBe(NATIVE_ETH);
    expect(entry.hookData).toBe("0x");
    expect(entry.swapHookDataPolicy).toBe("empty");
    expect(entry.nonEmptySwapHookDataProof).toBe(null);
    expect(entry.routeArtifactIds).toEqual([
      "solver-eth-zora-basedflick-fame",
      "solver-fame-basedflick-zora-eth",
      "solver-fame-basedflick-zora-usdc",
      "solver-fame-basedflick-zora-weth",
      "solver-usdc-zora-basedflick-fame"
    ]);
    expect(entry.evidenceTypes).toEqual(["hook-address-swap"]);
    expect(entry.proves).toEqual({
      hookAddressSwap: true,
      nonEmptySwapHookData: false,
      factoryDeployHookData: false,
      localHookHarness: false
    });
  });

  test("rejects configured creator-coin entries that are not Uniswap V4 pools", () => {
    expectErrorMessage(
      () => buildCreatorCoinCatalog(config, [
        {
          id: "invalid-zora-usdc",
          poolConfigId: "uniswap-v3-zora-usdc",
          pair: "ZORA/USDC",
          creatorCoin: ZORA,
          baseCurrency: BASEDFLICK,
          swapHookDataPolicy: "empty",
          routeArtifactIds: [],
          evidence: []
        }
      ]),
      "must be a Uniswap V4 pool"
    );
  });

  test("rejects non-empty swap hookData unless it is an approved evidence target", () => {
    const mutated: SupportedPoolConfig = {
      ...config,
      pools: config.pools.map((pool) =>
        pool.id === "uniswap-v4-basedflick-zora" && pool.venue === "uniswap-v4"
          ? { ...pool, hookData: "0x1234" }
          : pool
      )
    };

    expectErrorMessage(() => buildCreatorCoinCatalog(mutated), "expected empty swap hookData");
  });

  test("rejects approved non-empty swap hookData without structured proof", () => {
    const mutated = withBasedflickHookData(config, "0x1234");

    expectErrorMessage(
      () => buildCreatorCoinCatalog(mutated, [
        {
          id: "invalid-non-empty",
          poolConfigId: "uniswap-v4-basedflick-zora",
          pair: "basedflick/ZORA",
          creatorCoin: BASEDFLICK,
          baseCurrency: ZORA,
          swapHookDataPolicy: "non-empty-approved",
          routeArtifactIds: [],
          evidence: []
        }
      ]),
      "requires structured non-empty hookData proof"
    );
  });

  test("allows approved non-empty swap hookData only with explicit production or harness proof", () => {
    const mutated = withBasedflickHookData(config, "0x1234");
    const catalog = buildCreatorCoinCatalog(mutated, [
      {
        id: "local-harness-non-empty",
        poolConfigId: "uniswap-v4-basedflick-zora",
        pair: "basedflick/ZORA",
        creatorCoin: BASEDFLICK,
        baseCurrency: ZORA,
        swapHookDataPolicy: "non-empty-approved",
        nonEmptySwapHookDataProof: {
          type: "local-hook-harness",
          reference: "test/router/FameRouter.t.sol",
          detail: "Test-only proof fixture requires and validates non-empty swap hookData."
        },
        routeArtifactIds: [],
        evidence: [
          {
            type: "local-hook-harness",
            reference: "test/router/FameRouter.t.sol",
            detail: "Test-only proof fixture requires and validates non-empty swap hookData."
          }
        ]
      }
    ]);

    const [entry] = catalog.entries;
    if (entry === undefined) throw new Error("Expected catalog entry");
    expect(entry.swapHookDataPolicy).toBe("non-empty-approved");
    expect(entry.proves.nonEmptySwapHookData).toBe(true);
    expect(entry.evidenceTypes).toEqual(["hook-address-swap", "non-empty-swap-hook-data"]);
  });
});

function withBasedflickHookData(config: SupportedPoolConfig, hookData: "0x1234"): SupportedPoolConfig {
  return {
    ...config,
    pools: config.pools.map((pool) =>
      pool.id === "uniswap-v4-basedflick-zora" && pool.venue === "uniswap-v4" ? { ...pool, hookData } : pool
    )
  };
}
