import { getAddress, keccak256, toBytes } from "viem";

export const TRANSACTION_BUILDER_FILE_VERSION = "1.0";
export const TRANSACTION_BUILDER_APP_VERSION = "2.1.0";

function stringifyReplacer(_key, value) {
  return value === undefined ? null : value;
}

function serializeJsonValue(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => serializeJsonValue(item)).join(",")}]`;
  }

  if (typeof value === "object" && value !== null) {
    const keys = Object.keys(value).sort();
    let serialized = `{${JSON.stringify(keys, stringifyReplacer)}`;
    for (const key of keys) {
      serialized += `${serializeJsonValue(value[key])},`;
    }
    return `${serialized}}`;
  }

  return JSON.stringify(value, stringifyReplacer);
}

export function calculateChecksum(batchFile) {
  const { checksum: _checksum, ...metaWithoutChecksum } = batchFile.meta;
  const serialized = serializeJsonValue({
    ...batchFile,
    meta: { ...metaWithoutChecksum, name: null },
  });
  return keccak256(toBytes(serialized));
}

export function addChecksum(batchFile) {
  return {
    ...batchFile,
    meta: {
      ...batchFile.meta,
      checksum: calculateChecksum(batchFile),
    },
  };
}

export function validateChecksum(batchFile) {
  return batchFile.meta.checksum === calculateChecksum(batchFile);
}

function assertTransaction(call, index) {
  try {
    getAddress(call.to);
  } catch {
    throw new Error(`transaction ${index} must have a valid target address`);
  }
  if (typeof call.value !== "string" || !/^\d+$/.test(call.value)) {
    throw new Error(`transaction ${index} value must be an unsigned integer string`);
  }
  if (
    typeof call.data !== "string" ||
    !/^0x(?:[0-9a-fA-F]{2})*$/.test(call.data)
  ) {
    throw new Error(`transaction ${index} must have byte-aligned hex calldata`);
  }
}

export function buildTransactionBuilderBatch({
  chainId,
  safeAddress,
  name,
  description,
  calls,
  createdAt = Date.now(),
}) {
  const numericChainId = String(chainId);
  if (!/^\d+$/.test(numericChainId) || numericChainId === "0") {
    throw new Error("chainId must be a positive integer");
  }
  let normalizedSafeAddress;
  try {
    normalizedSafeAddress = getAddress(safeAddress);
  } catch {
    throw new Error("createdFromSafeAddress must be a valid address");
  }
  if (!Array.isArray(calls) || calls.length === 0) {
    throw new Error("a Transaction Builder batch requires at least one transaction");
  }
  if (!Number.isSafeInteger(createdAt) || createdAt < 0) {
    throw new Error("createdAt must be a non-negative millisecond timestamp");
  }

  calls.forEach(assertTransaction);

  return addChecksum({
    version: TRANSACTION_BUILDER_FILE_VERSION,
    chainId: numericChainId,
    createdAt,
    meta: {
      name,
      description,
      txBuilderVersion: TRANSACTION_BUILDER_APP_VERSION,
      createdFromSafeAddress: normalizedSafeAddress,
      createdFromOwnerAddress: "",
    },
    transactions: calls.map(({ to, value, data }) => ({
      to: getAddress(to),
      value,
      data,
    })),
  });
}
