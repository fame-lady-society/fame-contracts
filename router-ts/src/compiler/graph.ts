import type { Address } from "viem";
import type { PoolConfig, SupportedPoolConfig } from "./types.js";

export interface PoolEdge {
  pool: PoolConfig;
  tokenIn: Address;
  tokenOut: Address;
}

export function directedEdges(config: SupportedPoolConfig): PoolEdge[] {
  const edges: PoolEdge[] = [];
  for (const pool of config.pools) {
    if ("token0" in pool) {
      edges.push({ pool, tokenIn: pool.token0, tokenOut: pool.token1 });
      edges.push({ pool, tokenIn: pool.token1, tokenOut: pool.token0 });
    } else {
      edges.push({ pool, tokenIn: pool.currency0, tokenOut: pool.currency1 });
      edges.push({ pool, tokenIn: pool.currency1, tokenOut: pool.currency0 });
    }
  }
  return edges;
}

export function assertPoolConnects(pool: PoolConfig, tokenIn: Address, tokenOut: Address): void {
  const normalizedIn = tokenIn.toLowerCase();
  const normalizedOut = tokenOut.toLowerCase();
  const endpoints = "token0" in pool ? [pool.token0, pool.token1] : [pool.currency0, pool.currency1];
  const first = endpoints[0];
  const second = endpoints[1];
  if (!first || !second) throw new Error(`Pool ${pool.id} has incomplete endpoints`);
  const connects =
    first.toLowerCase() === normalizedIn && second.toLowerCase() === normalizedOut
      ? true
      : second.toLowerCase() === normalizedIn && first.toLowerCase() === normalizedOut;
  if (!connects) throw new Error(`Pool ${pool.id} does not connect requested tokens`);
}
