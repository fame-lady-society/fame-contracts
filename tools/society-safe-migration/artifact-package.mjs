import { isDeepStrictEqual } from "node:util";

import { getAddress } from "viem";

import { buildMigrationArtifacts } from "./migration.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";
import { validateChecksum } from "./transaction-builder.mjs";

function requireExact(label, actual, expected) {
  if (!isDeepStrictEqual(actual, expected)) {
    throw new Error(`${label} does not match the generated review manifest`);
  }
}

export function publicBatchRecord(batch) {
  return {
    id: batch.id,
    filename: batch.filename,
    chainId: batch.chainId,
    sourceSafe: batch.sourceSafe,
    name: batch.name,
    description: batch.description,
    executionGate: batch.executionGate,
    checksum: batch.builder.meta.checksum,
    transactionCount: batch.calls.length,
    calls: batch.calls,
  };
}

export function validateReviewManifest(review) {
  const createdAt = Date.parse(review.generatedAt);
  if (!Number.isFinite(createdAt)) {
    throw new Error("review manifest generatedAt is invalid");
  }
  requireExact(
    "review destination Safe",
    getAddress(review.destinationSafe),
    PUBLIC_MIGRATION_CONFIG.societySafe,
  );
  requireExact(
    "review replacement donation vault",
    getAddress(review.replacementDonationVault),
    PUBLIC_MIGRATION_CONFIG.ethereumDonationVault,
  );
  const expectedArtifacts = buildMigrationArtifacts(review.snapshot, {
    createdAt,
    newDonationVaultAddress: PUBLIC_MIGRATION_CONFIG.ethereumDonationVault,
  });
  requireExact(
    "review batch records",
    review.batches,
    expectedArtifacts.batches.map(publicBatchRecord),
  );
  requireExact("review blocked records", review.blocked, expectedArtifacts.blocked);
  requireExact(
    "review external prerequisites",
    review.externalPrerequisites,
    expectedArtifacts.externalPrerequisites,
  );
  requireExact(
    "review operator filename",
    review.operatorCalldataFile,
    "operator-calldata-not-safe-import.json",
  );
  return expectedArtifacts;
}

export function validateBatchPayload(record, batch, expectedBatch) {
  if (!validateChecksum(batch)) {
    throw new Error(`${record.filename} checksum failed`);
  }
  requireExact(`${record.filename} payload`, batch, expectedBatch.builder);
}

export function validateOperatorPayload(review, payload, expectedArtifacts) {
  requireExact("operator calldata payload", payload, {
    schemaVersion: 1,
    status: "raw-calldata-only-not-a-safe-transaction-builder-file",
    generatedAt: review.snapshot.generatedAt,
    calls: expectedArtifacts.operatorCalls,
  });
}

export function groupBatchesByChain(loadedBatches) {
  const batchesByChain = { 1: [], 137: [], 8453: [] };
  for (const item of loadedBatches) {
    const chainBatches = batchesByChain[item.record.chainId];
    if (!chainBatches) {
      throw new Error(`unsupported migration chain ${item.record.chainId}`);
    }
    chainBatches.push(item);
  }
  return batchesByChain;
}
