import type { Address } from "viem";

export const NATIVE_ETH: Address = "0x0000000000000000000000000000000000000000";
export const WETH: Address = "0x4200000000000000000000000000000000000006";
export const USDC: Address = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
export const FAME: Address = "0xf307e242bfe1ec1ff01a4cef2fdaa81b10a52418";
export const BASEDFLICK: Address = "0x15e012abf9d32cd67fc6cf480ea0e318e9ed5926";
export const ZORA: Address = "0x1111111111166b7fe7bd91427724b487980afc69";
export const FRXUSD: Address = "0xe5020a6d073a794b6e7f05678707de47986fb0b6";
export const SCALE: Address = "0x54016a4848a38f257b6e96331f7404073fd9c32c";
export const MSUSD: Address = "0x526728dbc96689597f85ae4cd716d4f7fccbae9d";
export const MSETH: Address = "0x7ba6f01772924a82d9626c126347a28299e98c98";
export const SPX: Address = "0x50da645f148798f68ef2d7db7c1cb22a6819bb2c";

export interface TokenConfig {
  symbol: string;
  address: Address;
  decimals: number;
  native: boolean;
}

export const TOKENS: Record<string, TokenConfig> = {
  ETH: { symbol: "ETH", address: NATIVE_ETH, decimals: 18, native: true },
  WETH: { symbol: "WETH", address: WETH, decimals: 18, native: false },
  USDC: { symbol: "USDC", address: USDC, decimals: 6, native: false },
  FAME: { symbol: "FAME", address: FAME, decimals: 18, native: false },
  BASEDFLICK: { symbol: "basedflick", address: BASEDFLICK, decimals: 18, native: false },
  ZORA: { symbol: "ZORA", address: ZORA, decimals: 18, native: false },
  FRXUSD: { symbol: "frxUSD", address: FRXUSD, decimals: 18, native: false },
  SCALE: { symbol: "SCALE", address: SCALE, decimals: 18, native: false },
  MSUSD: { symbol: "msUSD", address: MSUSD, decimals: 18, native: false },
  MSETH: { symbol: "msETH", address: MSETH, decimals: 18, native: false },
  SPX: { symbol: "SPX", address: SPX, decimals: 18, native: false }
};

export function tokenSymbol(address: Address): string {
  const normalized = address.toLowerCase();
  for (const token of Object.values(TOKENS)) {
    if (token.address.toLowerCase() === normalized) return token.symbol;
  }
  return address;
}
