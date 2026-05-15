import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { keccak256, toBytes, type Hex } from "viem";
import { decodeUniversalRouterV4Payload, v4HookDataKey } from "../adapters/universalRouterV4.js";
import { buildCreatorCoinCatalog } from "../catalog/creatorCoins.js";
import { loadSupportedBasePools } from "../config/base.js";
import { compileRoutes } from "../compiler/compileRoute.js";
import { PINNED_BASE_BLOCK, SCHEMA_VERSION, VenueFamily, type CompiledRoute } from "../compiler/types.js";
import { generateGapMatrix } from "../matrix/generateGapMatrix.js";
import { encodeRoute, hashRoute } from "./routeEncoding.js";
import { solverRoutesFile, toRouteArtifact, type ParityVectorFile, type RouteArtifact } from "./schema.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const solverRoutesPath = join(repoRoot, "test", "router", "fixtures", "base-v1-solver-routes.json");
const gapMatrixPath = join(repoRoot, "test", "router", "fixtures", "base-v1-route-gap-matrix.json");
const parityVectorsPath = join(repoRoot, "test", "router", "fixtures", "base-v1-route-parity-vectors.json");
const creatorCoinCatalogPath = join(repoRoot, "test", "router", "fixtures", "base-v1-creator-coin-catalog.json");
const solverManifestPath = join(repoRoot, "test", "router", "fixtures", "FameRouterSolverFixtureManifest.sol");

export interface GeneratedOutputs {
  solverRoutesJson: string;
  gapMatrixJson: string;
  parityVectorsJson: string;
  creatorCoinCatalogJson: string;
  solverManifestSol: string;
  routeArtifacts: RouteArtifact[];
}

function stableJson(value: object): string {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function hashText(text: string): Hex {
  return keccak256(toBytes(text));
}

function routeArtifact(compiled: CompiledRoute): RouteArtifact {
  const abiEncodedRoute = encodeRoute(compiled.route);
  const routeHash = hashRoute(compiled.route);
  return toRouteArtifact(compiled, abiEncodedRoute, routeHash);
}

function generateSolverManifest(params: {
  solverRoutesJson: string;
  gapMatrixJson: string;
  parityVectorsJson: string;
  creatorCoinCatalogJson: string;
  creatorCoinCatalogEntryCount: number;
  routeArtifacts: RouteArtifact[];
}): string {
  const routeIds = params.routeArtifacts
    .map((artifact, index) => `        if (index == ${index}) return "${artifact.id}";`)
    .join("\n");
  const requiredTargets = uniqueTargets(params.routeArtifacts);
  const requiredHookDataKeys = uniqueHookDataKeys(params.routeArtifacts);
  const targetCases = requiredTargets
    .map(
      (entry, index) =>
        `        if (index == ${index}) return Target(FameRouterTypes.VenueFamily.${entry.venue}, ${entry.target});`
    )
    .join("\n");
  const hookDataKeyCases = requiredHookDataKeys
    .map((key, index) => `        if (index == ${index}) return ${key};`)
    .join("\n");
  const hookDataKeyBody =
    requiredHookDataKeys.length === 0
      ? "        index;\n        revert(\"NO_SOLVER_REQUIRED_V4_HOOK_DATA_KEY\");"
      : `${hookDataKeyCases}\n        revert("NO_SOLVER_REQUIRED_V4_HOOK_DATA_KEY");`;

  return `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameRouterTypes} from "../../../src/router/FameRouterTypes.sol";

library FameRouterSolverFixtureManifest {
    struct Target {
        FameRouterTypes.VenueFamily family;
        address target;
    }

    uint256 internal constant PINNED_BASE_BLOCK = ${PINNED_BASE_BLOCK};
    bytes32 internal constant SOLVER_ROUTES_JSON_HASH = ${hashText(params.solverRoutesJson)};
    bytes32 internal constant GAP_MATRIX_JSON_HASH = ${hashText(params.gapMatrixJson)};
    bytes32 internal constant PARITY_VECTORS_JSON_HASH = ${hashText(params.parityVectorsJson)};
    bytes32 internal constant CREATOR_COIN_CATALOG_JSON_HASH = ${hashText(params.creatorCoinCatalogJson)};

    function pinnedBaseBlock() internal pure returns (uint256) {
        return PINNED_BASE_BLOCK;
    }

    function solverRoutesJsonHash() internal pure returns (bytes32) {
        return SOLVER_ROUTES_JSON_HASH;
    }

    function gapMatrixJsonHash() internal pure returns (bytes32) {
        return GAP_MATRIX_JSON_HASH;
    }

    function parityVectorsJsonHash() internal pure returns (bytes32) {
        return PARITY_VECTORS_JSON_HASH;
    }

    function creatorCoinCatalogJsonHash() internal pure returns (bytes32) {
        return CREATOR_COIN_CATALOG_JSON_HASH;
    }

    function creatorCoinCatalogEntryCount() internal pure returns (uint256) {
        return ${params.creatorCoinCatalogEntryCount};
    }

    function routeArtifactCount() internal pure returns (uint256) {
        return ${params.routeArtifacts.length};
    }

    function routeArtifactId(uint256 index) internal pure returns (string memory) {
${routeIds}
        revert("NO_SOLVER_ROUTE_ARTIFACT");
    }

    function requiredVenueTargetCount() internal pure returns (uint256) {
        return ${requiredTargets.length};
    }

    function requiredVenueTarget(uint256 index) internal pure returns (Target memory) {
${targetCases}
        revert("NO_SOLVER_REQUIRED_TARGET");
    }

    function requiredV4HookDataKeyCount() internal pure returns (uint256) {
        return ${requiredHookDataKeys.length};
    }

    function requiredV4HookDataKey(uint256 index) internal pure returns (bytes32) {
${hookDataKeyBody}
    }
}
`;
}

function uniqueTargets(routeArtifacts: RouteArtifact[]): Array<{ venue: keyof typeof VenueFamily; target: string }> {
  const entries = new Map<string, { venue: keyof typeof VenueFamily; target: string }>();
  for (const artifact of routeArtifacts) {
    for (const leg of artifact.route.legs) {
      const key = `${leg.venue}:${leg.target.toLowerCase()}`;
      if (!entries.has(key)) entries.set(key, { venue: leg.venue, target: leg.target });
    }
  }
  return [...entries.values()].sort((a, b) => `${a.venue}:${a.target}`.localeCompare(`${b.venue}:${b.target}`));
}

function uniqueHookDataKeys(routeArtifacts: RouteArtifact[]): Hex[] {
  const keys = new Set<Hex>();
  for (const artifact of routeArtifacts) {
    for (const leg of artifact.route.legs) {
      if (leg.venue !== "UniswapV4") continue;
      const payload = decodeUniversalRouterV4Payload(leg.data);
      if (payload.hookData === "0x") continue;
      keys.add(v4HookDataKey(payload));
    }
  }
  return [...keys].sort();
}

export function generateOutputs(): GeneratedOutputs {
  const config = loadSupportedBasePools(join(repoRoot, "test", "router", "fixtures", "base-v1-pools.json"));
  const compiled = compileRoutes(config);
  const routeArtifacts = compiled.map(routeArtifact).sort((a, b) => a.id.localeCompare(b.id));
  const creatorCoinCatalog = buildCreatorCoinCatalog(config);
  const solverRoutesJson = stableJson(solverRoutesFile(routeArtifacts));
  const gapMatrixJson = stableJson(generateGapMatrix(compiled));
  const creatorCoinCatalogJson = stableJson(creatorCoinCatalog);
  const parityVectors: ParityVectorFile = {
    schemaVersion: SCHEMA_VERSION,
    pinnedBaseBlock: PINNED_BASE_BLOCK,
    vectors: routeArtifacts.map((artifact) => ({
      id: artifact.id,
      route: artifact.route,
      abiEncodedRoute: artifact.abiEncodedRoute,
      routeHash: artifact.routeHash
    }))
  };
  const parityVectorsJson = stableJson(parityVectors);
  const solverManifestSol = generateSolverManifest({
    solverRoutesJson,
    gapMatrixJson,
    parityVectorsJson,
    creatorCoinCatalogJson,
    creatorCoinCatalogEntryCount: creatorCoinCatalog.entries.length,
    routeArtifacts
  });

  return {
    solverRoutesJson,
    gapMatrixJson,
    parityVectorsJson,
    creatorCoinCatalogJson,
    solverManifestSol,
    routeArtifacts
  };
}

function writeIfChanged(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

function assertFileMatches(path: string, expected: string): void {
  const actual = readFileSync(path, "utf8");
  if (actual !== expected) throw new Error(`${path} is not up to date; run bun run router:generate`);
}

function run(): void {
  const outputs = generateOutputs();
  const check = process.argv.includes("--check");
  if (check) {
    assertFileMatches(solverRoutesPath, outputs.solverRoutesJson);
    assertFileMatches(gapMatrixPath, outputs.gapMatrixJson);
    assertFileMatches(parityVectorsPath, outputs.parityVectorsJson);
    assertFileMatches(creatorCoinCatalogPath, outputs.creatorCoinCatalogJson);
    assertFileMatches(solverManifestPath, outputs.solverManifestSol);
    return;
  }

  writeIfChanged(solverRoutesPath, outputs.solverRoutesJson);
  writeIfChanged(gapMatrixPath, outputs.gapMatrixJson);
  writeIfChanged(parityVectorsPath, outputs.parityVectorsJson);
  writeIfChanged(creatorCoinCatalogPath, outputs.creatorCoinCatalogJson);
  writeIfChanged(solverManifestPath, outputs.solverManifestSol);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run();
}
