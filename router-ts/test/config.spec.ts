import { describe, expect, test } from "bun:test";
import { loadSupportedBasePools, poolById } from "../src/config/base.js";
import { BASEDFLICK, FAME, NATIVE_ETH, USDC, WETH, ZORA } from "../src/config/tokens.js";
import type {
  AerodromeV2PoolConfig,
  PoolConfig,
  SlipstreamPoolConfig,
  UniswapV3PoolConfig,
  UniswapV4PoolConfig
} from "../src/compiler/types.js";

function expectSlipstream(pool: PoolConfig, venue: "aerodrome-slipstream" | "aerodrome-slipstream2"): SlipstreamPoolConfig {
  expect(pool.venue).toBe(venue);
  if (pool.venue !== venue) throw new Error(`Expected ${venue} pool`);
  return pool;
}

function expectV3(pool: PoolConfig): UniswapV3PoolConfig {
  expect(pool.venue).toBe("uniswap-v3");
  if (pool.venue !== "uniswap-v3") throw new Error("Expected uniswap-v3 pool");
  return pool;
}

function expectV4(pool: PoolConfig): UniswapV4PoolConfig {
  expect(pool.venue).toBe("uniswap-v4");
  if (pool.venue !== "uniswap-v4") throw new Error("Expected uniswap-v4 pool");
  return pool;
}

function expectAerodromeV2(pool: PoolConfig): AerodromeV2PoolConfig {
  expect(pool.venue).toBe("aerodrome-v2");
  if (pool.venue !== "aerodrome-v2") throw new Error("Expected aerodrome-v2 pool");
  return pool;
}

describe("Base supported pool config", () => {
  const config = loadSupportedBasePools();

  test("loads all current pool fixtures with normalized token identities", () => {
    expect(config.pools).toHaveLength(20);
    const basedflickFame = expectSlipstream(poolById(config, "slipstream-basedflick-fame"), "aerodrome-slipstream");
    const aerodromeV2UsdcWeth = expectAerodromeV2(poolById(config, "aerodrome-v2-usdc-weth"));
    const zoraUsdc = expectV3(poolById(config, "uniswap-v3-zora-usdc"));
    const zoraEth = expectV4(poolById(config, "uniswap-v4-zora-eth"));
    const basedflickZora = expectV4(poolById(config, "uniswap-v4-basedflick-zora"));

    expect(basedflickFame.token0.toLowerCase()).toBe(BASEDFLICK);
    expect(basedflickFame.token1.toLowerCase()).toBe(FAME);
    expect(aerodromeV2UsdcWeth.token0.toLowerCase()).toBe(WETH);
    expect(aerodromeV2UsdcWeth.token1.toLowerCase()).toBe(USDC);
    expect(aerodromeV2UsdcWeth.factory.toLowerCase()).toBe("0x420dd381b31aef6683db6b902084cb0ffece40da");
    expect(zoraUsdc.token0.toLowerCase()).toBe(ZORA);
    expect(zoraUsdc.token1.toLowerCase()).toBe(USDC);
    expect(zoraEth.currency0.toLowerCase()).toBe(NATIVE_ETH);
    expect(zoraEth.currency1.toLowerCase()).toBe(ZORA);
    expect(basedflickZora.hookData).toBe("0x");
  });

  test("keeps native ETH and WETH distinct", () => {
    expect(NATIVE_ETH).not.toBe(WETH);
    expect(expectV4(poolById(config, "uniswap-v4-zora-eth"))).toMatchObject({ currency0: NATIVE_ETH });
    expect(expectV3(poolById(config, "uniswap-v3-zora-weth"))).toMatchObject({ token1: WETH });
  });
});
