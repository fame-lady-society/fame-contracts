import type { Address, Hex } from "viem";
import { poolById } from "../config/base.js";
import { BASEDFLICK, NATIVE_ETH, ZORA } from "../config/tokens.js";
import { PINNED_BASE_BLOCK, SCHEMA_VERSION, type SupportedPoolConfig, type UniswapV4PoolConfig } from "../compiler/types.js";

export type V4FixtureEvidenceType =
  | "hook-address-swap"
  | "non-empty-swap-hook-data"
  | "factory-deploy-hook-data"
  | "local-hook-harness"
  | "diagnostic-probe";

export type SwapHookDataPolicy = "empty" | "non-empty-approved";

export type CreatorCoinEvidenceSourceType =
  | "committed-pool-config"
  | "pinned-fork-metadata-validation"
  | "fleet-reference"
  | "production-fork-route"
  | "local-hook-harness";

export interface CreatorCoinEvidenceSource {
  type: CreatorCoinEvidenceSourceType;
  reference: string;
  detail: string;
}

export interface NonEmptySwapHookDataProof {
  type: "production-fork-route" | "local-hook-harness";
  reference: string;
  detail: string;
}

export interface CreatorCoinCatalogEntry {
  id: string;
  poolConfigId: string;
  v4PoolId: Hex;
  pair: string;
  venue: "uniswap-v4";
  creatorCoin: Address;
  baseCurrency: Address;
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
  hookData: Hex;
  swapHookDataPolicy: SwapHookDataPolicy;
  nonEmptySwapHookDataProof: NonEmptySwapHookDataProof | null;
  routeArtifactIds: string[];
  evidenceTypes: V4FixtureEvidenceType[];
  proves: {
    hookAddressSwap: boolean;
    nonEmptySwapHookData: boolean;
    factoryDeployHookData: boolean;
    localHookHarness: boolean;
  };
  evidence: CreatorCoinEvidenceSource[];
}

export interface CreatorCoinCatalogFile {
  schemaVersion: 1;
  status: "generated-fixture-policy-evidence";
  pinnedBaseBlock: number;
  generator: "router-ts";
  entries: CreatorCoinCatalogEntry[];
}

export interface CreatorCoinPoolSpec {
  id: string;
  poolConfigId: string;
  pair: string;
  creatorCoin: Address;
  baseCurrency: Address;
  swapHookDataPolicy: SwapHookDataPolicy;
  nonEmptySwapHookDataProof?: NonEmptySwapHookDataProof;
  routeArtifactIds: string[];
  evidence: CreatorCoinEvidenceSource[];
}

export const CREATOR_COIN_POOL_SPECS: readonly CreatorCoinPoolSpec[] = [
  {
    id: "creator-basedflick-zora",
    poolConfigId: "uniswap-v4-basedflick-zora",
    pair: "basedflick/ZORA",
    creatorCoin: BASEDFLICK,
    baseCurrency: ZORA,
    swapHookDataPolicy: "empty",
    routeArtifactIds: [
      "solver-eth-zora-basedflick-fame",
      "solver-fame-basedflick-zora-eth",
      "solver-fame-basedflick-zora-usdc",
      "solver-fame-basedflick-zora-weth",
      "solver-usdc-zora-basedflick-fame"
    ],
    evidence: [
      {
        type: "committed-pool-config",
        reference: "test/router/fixtures/base-v1-pools.json",
        detail: "Pool fixture records the basedflick/ZORA V4 PoolKey, hook address, and explicit empty swap hookData."
      },
      {
        type: "pinned-fork-metadata-validation",
        reference: "test/router/FameRouterForkBase.t.sol",
        detail: "Pinned Base fork metadata checks derive the V4 pool id from currency0, currency1, fee, tick spacing, and hooks."
      },
      {
        type: "fleet-reference",
        reference: "docs/ideation/2026-05-12-fame-v4-hook-data-fork-route-ideation.md",
        detail: "Fleet-style creator-coin swaps use hook-address pools with ordinary swap hookData set to 0x."
      }
    ]
  }
] as const;

function isUniswapV4Pool(pool: ReturnType<typeof poolById>): pool is UniswapV4PoolConfig {
  return pool.venue === "uniswap-v4";
}

function sameAddress(left: Address, right: Address): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

function validateCreatorCoinPool(spec: CreatorCoinPoolSpec, pool: UniswapV4PoolConfig): void {
  if (sameAddress(pool.hooks, NATIVE_ETH)) {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} must have a hook address`);
  }
  if (!sameAddress(pool.currency0, spec.baseCurrency) && !sameAddress(pool.currency1, spec.baseCurrency)) {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} does not include configured base currency`);
  }
  if (!sameAddress(pool.currency0, spec.creatorCoin) && !sameAddress(pool.currency1, spec.creatorCoin)) {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} does not include configured creator coin`);
  }
  if (spec.swapHookDataPolicy === "empty" && pool.hookData !== "0x") {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} expected empty swap hookData`);
  }
  if (spec.swapHookDataPolicy === "non-empty-approved" && pool.hookData === "0x") {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} expected approved non-empty swap hookData`);
  }
  if (spec.swapHookDataPolicy === "non-empty-approved" && spec.nonEmptySwapHookDataProof === undefined) {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} requires structured non-empty hookData proof`);
  }
  if (spec.swapHookDataPolicy === "empty" && spec.nonEmptySwapHookDataProof !== undefined) {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} cannot attach non-empty hookData proof to empty policy`);
  }
  if (
    spec.nonEmptySwapHookDataProof !== undefined &&
    (spec.nonEmptySwapHookDataProof.reference.length === 0 || spec.nonEmptySwapHookDataProof.detail.length === 0)
  ) {
    throw new Error(`Creator-coin V4 pool ${spec.poolConfigId} has incomplete non-empty hookData proof`);
  }
}

function evidenceTypesFor(spec: CreatorCoinPoolSpec): V4FixtureEvidenceType[] {
  return spec.swapHookDataPolicy === "empty"
    ? ["hook-address-swap"]
    : ["hook-address-swap", "non-empty-swap-hook-data"];
}

function toCatalogEntry(config: SupportedPoolConfig, spec: CreatorCoinPoolSpec): CreatorCoinCatalogEntry {
  const pool = poolById(config, spec.poolConfigId);
  if (!isUniswapV4Pool(pool)) throw new Error(`Creator-coin pool ${spec.poolConfigId} must be a Uniswap V4 pool`);

  validateCreatorCoinPool(spec, pool);
  const nonEmptySwapHookData = spec.swapHookDataPolicy === "non-empty-approved";

  return {
    id: spec.id,
    poolConfigId: spec.poolConfigId,
    v4PoolId: pool.poolId,
    pair: spec.pair,
    venue: "uniswap-v4",
    creatorCoin: spec.creatorCoin,
    baseCurrency: spec.baseCurrency,
    currency0: pool.currency0,
    currency1: pool.currency1,
    fee: pool.fee,
    tickSpacing: pool.tickSpacing,
    hooks: pool.hooks,
    hookData: pool.hookData,
    swapHookDataPolicy: spec.swapHookDataPolicy,
    nonEmptySwapHookDataProof: spec.nonEmptySwapHookDataProof ?? null,
    routeArtifactIds: spec.routeArtifactIds,
    evidenceTypes: evidenceTypesFor(spec),
    proves: {
      hookAddressSwap: true,
      nonEmptySwapHookData,
      factoryDeployHookData: false,
      localHookHarness: false
    },
    evidence: spec.evidence
  };
}

export function buildCreatorCoinCatalog(
  config: SupportedPoolConfig,
  specs: readonly CreatorCoinPoolSpec[] = CREATOR_COIN_POOL_SPECS
): CreatorCoinCatalogFile {
  return {
    schemaVersion: SCHEMA_VERSION,
    status: "generated-fixture-policy-evidence",
    pinnedBaseBlock: PINNED_BASE_BLOCK,
    generator: "router-ts",
    entries: specs.map((spec) => toCatalogEntry(config, spec)).sort((a, b) => a.id.localeCompare(b.id))
  };
}
