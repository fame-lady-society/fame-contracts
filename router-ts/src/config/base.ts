import { getAddress, isAddress, type Address, type Hex } from "viem";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { NATIVE_ETH } from "./tokens.js";
import {
  PINNED_BASE_BLOCK,
  SCHEMA_VERSION,
  type AerodromeV2PoolConfig,
  type PoolConfig,
  type SolidlyPoolConfig,
  type SlipstreamPoolConfig,
  type SupportedPoolConfig,
  type UniswapV2PoolConfig,
  type UniswapV3PoolConfig,
  type UniswapV4PoolConfig
} from "../compiler/types.js";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const POOLS_FIXTURE_PATH = join(REPO_ROOT, "test", "router", "fixtures", "base-v1-pools.json");

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(record: Record<string, unknown>, key: string): string {
  const value = record[key];
  if (typeof value !== "string") throw new Error(`Expected string field ${key}`);
  return value;
}

function readAddress(record: Record<string, unknown>, key: string): Address {
  const value = readString(record, key);
  if (!isAddress(value)) throw new Error(`Expected address field ${key}`);
  return getAddress(value);
}

function readHex(record: Record<string, unknown>, key: string): Hex {
    const value = readString(record, key);
  if (!isHexValue(value)) throw new Error(`Expected hex field ${key}`);
  return value;
}

function readBytes32(record: Record<string, unknown>, key: string): Hex {
  const value = readHex(record, key);
  if (value.length !== 66) throw new Error(`Expected bytes32 field ${key}`);
  return value;
}

function readNumber(record: Record<string, unknown>, key: string): number {
  const value = record[key];
  if (typeof value !== "number") throw new Error(`Expected number field ${key}`);
  return value;
}

function readBoolean(record: Record<string, unknown>, key: string): boolean {
  const value = record[key];
  if (typeof value !== "boolean") throw new Error(`Expected boolean field ${key}`);
  return value;
}

function optionalAddress(record: Record<string, unknown>, key: string): Address | null {
  const value = record[key];
  if (value === undefined) return null;
  if (typeof value !== "string" || !isAddress(value)) throw new Error(`Expected optional address field ${key}`);
  return getAddress(value);
}

function parsePool(raw: unknown): PoolConfig {
  if (!isRecord(raw)) throw new Error("Pool entry must be an object");
  const id = readString(raw, "id");
  const venue = readString(raw, "venue");
  const router = readAddress(raw, "router");

  if (venue === "solidly") {
    const pool: SolidlyPoolConfig = {
      id,
      venue,
      router,
      pool: readAddress(raw, "pool"),
      token0: readAddress(raw, "token0"),
      token1: readAddress(raw, "token1"),
      stable: readBoolean(raw, "stable"),
      feeBps: readNumber(raw, "feeBps")
    };
    return pool;
  }

  if (venue === "uniswap-v2") {
    const pool: UniswapV2PoolConfig = {
      id,
      venue,
      router,
      pool: readAddress(raw, "pool"),
      token0: readAddress(raw, "token0"),
      token1: readAddress(raw, "token1"),
      feeBps: readNumber(raw, "feeBps")
    };
    return pool;
  }

  if (venue === "aerodrome-slipstream" || venue === "aerodrome-slipstream2") {
    const pool: SlipstreamPoolConfig = {
      id,
      venue,
      router,
      factory: readAddress(raw, "factory"),
      pool: readAddress(raw, "pool"),
      token0: readAddress(raw, "token0"),
      token1: readAddress(raw, "token1"),
      tickSpacing: readNumber(raw, "tickSpacing"),
      feeBps: readNumber(raw, "feeBps")
    };
    return pool;
  }

  if (venue === "aerodrome-v2") {
    const pool: AerodromeV2PoolConfig = {
      id,
      venue,
      router,
      factory: readAddress(raw, "factory"),
      pool: readAddress(raw, "pool"),
      token0: readAddress(raw, "token0"),
      token1: readAddress(raw, "token1"),
      stable: readBoolean(raw, "stable"),
      feeBps: readNumber(raw, "feeBps")
    };
    return pool;
  }

  if (venue === "uniswap-v3") {
    const pool: UniswapV3PoolConfig = {
      id,
      venue,
      router,
      pool: readAddress(raw, "pool"),
      token0: readAddress(raw, "token0"),
      token1: readAddress(raw, "token1"),
      fee: readNumber(raw, "fee"),
      tickSpacing: readNumber(raw, "tickSpacing")
    };
    return pool;
  }

  if (venue === "uniswap-v4") {
    const hooks = readAddress(raw, "hooks");
    if (hooks !== NATIVE_ETH && raw["hookData"] === undefined) {
      throw new Error(`V4 hooked pool ${id} must include explicit hookData`);
    }
    const normalizedHookData = raw["hookData"] === undefined ? "0x" : readHex(raw, "hookData");
    const pool: UniswapV4PoolConfig = {
      id,
      venue,
      router,
      poolManager: readAddress(raw, "poolManager"),
      stateView: readAddress(raw, "stateView"),
      poolId: readBytes32(raw, "poolId"),
      currency0: optionalAddress(raw, "currency0") ?? NATIVE_ETH,
      currency1: optionalAddress(raw, "currency1") ?? NATIVE_ETH,
      fee: readNumber(raw, "fee"),
      tickSpacing: readNumber(raw, "tickSpacing"),
      hooks,
      hookData: normalizedHookData
    };
    return pool;
  }

  throw new Error(`Unsupported pool venue ${venue} for ${id}`);
}

function isHexValue(value: unknown): value is Hex {
  return typeof value === "string" && /^0x([0-9a-fA-F]{2})*$/.test(value);
}

export function loadSupportedBasePools(path = POOLS_FIXTURE_PATH): SupportedPoolConfig {
  const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
  if (!isRecord(parsed)) throw new Error("Pool fixture root must be an object");
  const rawPools = parsed["pools"];
  if (!Array.isArray(rawPools)) throw new Error("Pool fixture must include pools[]");
  const schemaVersion = parsed["schemaVersion"];
  const pinnedBaseBlock = parsed["pinnedBaseBlock"];
  const status = parsed["status"];
  if (schemaVersion !== SCHEMA_VERSION) throw new Error(`Unsupported pool schema version ${String(schemaVersion)}`);
  if (pinnedBaseBlock !== PINNED_BASE_BLOCK) throw new Error(`Unexpected pinned block ${String(pinnedBaseBlock)}`);
  if (typeof status !== "string") throw new Error("Pool fixture status must be a string");

  const pools = rawPools.map(parsePool);
  const ids = new Set<string>();
  for (const pool of pools) {
    if (ids.has(pool.id)) throw new Error(`Duplicate pool id ${pool.id}`);
    ids.add(pool.id);
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    status,
    pinnedBaseBlock: PINNED_BASE_BLOCK,
    pools
  };
}

export function poolById(config: SupportedPoolConfig, id: string): PoolConfig {
  const pool = config.pools.find((candidate) => candidate.id === id);
  if (!pool) throw new Error(`Unknown pool id ${id}`);
  return pool;
}
