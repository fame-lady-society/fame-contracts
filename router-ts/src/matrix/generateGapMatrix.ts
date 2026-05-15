import { FAME, NATIVE_ETH, USDC, WETH } from "../config/tokens.js";
import { PINNED_BASE_BLOCK, SCHEMA_VERSION, type CompiledRoute } from "../compiler/types.js";
import type { GapMatrixFile, GapMatrixRow } from "./types.js";

const requiredDirections = [
  { id: "fame-to-usdc", tokenIn: FAME, tokenOut: USDC, direction: "FAME->USDC" },
  { id: "usdc-to-fame", tokenIn: USDC, tokenOut: FAME, direction: "USDC->FAME" },
  { id: "fame-to-weth", tokenIn: FAME, tokenOut: WETH, direction: "FAME->WETH" },
  { id: "weth-to-fame", tokenIn: WETH, tokenOut: FAME, direction: "WETH->FAME" },
  { id: "fame-to-eth", tokenIn: FAME, tokenOut: NATIVE_ETH, direction: "FAME->ETH" },
  { id: "eth-to-fame", tokenIn: NATIVE_ETH, tokenOut: FAME, direction: "ETH->FAME" }
] as const;

export function generateGapMatrix(routes: CompiledRoute[]): GapMatrixFile {
  const rows: GapMatrixRow[] = requiredDirections.map((direction) => {
    const route = routes.find(
      (candidate) =>
        candidate.route.tokenIn.toLowerCase() === direction.tokenIn.toLowerCase() &&
        candidate.route.tokenOut.toLowerCase() === direction.tokenOut.toLowerCase()
    );

    if (route) {
      return {
        id: direction.id,
        tokenIn: direction.tokenIn,
        tokenOut: direction.tokenOut,
        direction: direction.direction,
        supported: true,
        executable: "executable",
        tsGenerated: true,
        forkTested: true,
        routeArtifactId: route.id,
        blocker: null,
        capabilities: route.capabilities
      };
    }

    return {
      id: direction.id,
      tokenIn: direction.tokenIn,
      tokenOut: direction.tokenOut,
      direction: direction.direction,
      supported: true,
      executable: "blocked",
      tsGenerated: false,
      forkTested: false,
      routeArtifactId: null,
      blocker:
        direction.tokenIn === NATIVE_ETH || direction.tokenOut === NATIVE_ETH
          ? "Native ETH FAME-facing composed route still requires a deterministic exact V4 intermediate amount at the pinned block."
          : "No deterministic executable artifact selected in the current focused matrix.",
      capabilities: {
        nativeEth: direction.tokenIn === NATIVE_ETH || direction.tokenOut === NATIVE_ETH,
        weth: direction.tokenIn === WETH || direction.tokenOut === WETH,
        nativeWrap: false,
        permit2UniversalRouter: true,
        v4Hooks: true,
        v4HookAddress: false,
        v4NonEmptyHookData: false,
        v4MultiHopPathKeys: false,
        split: false,
        splitThenMerge: false
      }
    };
  });

  rows.push({
    id: "split-weth-to-fame",
    tokenIn: WETH,
    tokenOut: FAME,
    direction: "WETH split -> FAME",
    supported: true,
    executable: "executable",
    tsGenerated: true,
    forkTested: true,
    routeArtifactId: "solver-weth-split-fame",
    blocker: null,
    capabilities: {
      nativeEth: false,
      weth: true,
      nativeWrap: false,
      permit2UniversalRouter: false,
      v4Hooks: false,
      v4HookAddress: false,
      v4NonEmptyHookData: false,
      v4MultiHopPathKeys: false,
      split: true,
      splitThenMerge: false
    }
  });

  rows.push({
    id: "split-merge-usdc-to-fame",
    tokenIn: USDC,
    tokenOut: FAME,
    direction: "USDC split -> frxUSD merge -> FAME",
    supported: true,
    executable: "executable",
    tsGenerated: true,
    forkTested: true,
    routeArtifactId: "solver-usdc-split-frxusd-merge-fame",
    blocker: null,
    capabilities: {
      nativeEth: false,
      weth: false,
      nativeWrap: false,
      permit2UniversalRouter: false,
      v4Hooks: false,
      v4HookAddress: false,
      v4NonEmptyHookData: false,
      v4MultiHopPathKeys: false,
      split: true,
      splitThenMerge: true
    }
  });

  const referencedArtifactIds = new Set(rows.flatMap((row) => (row.routeArtifactId === null ? [] : [row.routeArtifactId])));
  for (const route of routes) {
    if (referencedArtifactIds.has(route.id)) continue;
    rows.push({
      id: `artifact-${route.id}`,
      tokenIn: route.route.tokenIn,
      tokenOut: route.route.tokenOut,
      direction: route.description,
      supported: true,
      executable: "executable",
      tsGenerated: true,
      forkTested: true,
      routeArtifactId: route.id,
      blocker: null,
      capabilities: route.capabilities
    });
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    pinnedBaseBlock: PINNED_BASE_BLOCK,
    rows
  };
}
