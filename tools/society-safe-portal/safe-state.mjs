import { keccak256, toHex } from "viem";

import { SAFE_ABI, storageWordToAddress } from "./core.mjs";
import { SAFE_MANIFEST, SENTINEL_ADDRESS, STORAGE_SLOTS } from "./manifest.mjs";

const ZERO_WORD = `0x${"0".repeat(64)}`;

export function runtimeHash(code) {
  return code && code !== "0x" ? keccak256(code) : null;
}

export async function resolveSafeSnapshot(code, readDeployedSnapshot) {
  const normalizedCode = code ?? "0x";
  if (normalizedCode === "0x") {
    return { code: normalizedCode };
  }

  return readDeployedSnapshot(normalizedCode);
}

function storageAddress(word) {
  return storageWordToAddress(word ?? ZERO_WORD);
}

export async function readSafeSnapshot(
  publicClient,
  code,
  manifest = SAFE_MANIFEST,
) {
  const safeAddress = manifest.safe.predictedAddress;
  const [
    version,
    owners,
    threshold,
    nonce,
    modulePage,
    singletonWord,
    fallbackWord,
    guardWord,
  ] = await Promise.all([
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_ABI,
      functionName: "VERSION",
    }),
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_ABI,
      functionName: "getOwners",
    }),
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_ABI,
      functionName: "getThreshold",
    }),
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_ABI,
      functionName: "nonce",
    }),
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_ABI,
      functionName: "getModulesPaginated",
      args: [SENTINEL_ADDRESS, 50n],
    }),
    publicClient.getStorageAt({
      address: safeAddress,
      slot: toHex(STORAGE_SLOTS.singleton, { size: 32 }),
    }),
    publicClient.getStorageAt({
      address: safeAddress,
      slot: toHex(STORAGE_SLOTS.fallbackHandler, { size: 32 }),
    }),
    publicClient.getStorageAt({
      address: safeAddress,
      slot: toHex(STORAGE_SLOTS.guard, { size: 32 }),
    }),
  ]);

  return {
    code,
    version,
    owners: [...owners],
    threshold,
    nonce,
    modules: [...modulePage[0]],
    modulesNext: modulePage[1],
    singleton: storageAddress(singletonWord),
    fallbackHandler: storageAddress(fallbackWord),
    guard: storageAddress(guardWord),
  };
}
