import assert from "node:assert/strict";
import test from "node:test";

import {
  groupBatchesByChain,
  publicBatchRecord,
  validateBatchPayload,
  validateOperatorPayload,
  validateReviewManifest,
} from "./artifact-package.mjs";
import { ADDRESSES, buildMigrationArtifacts } from "./migration.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";
import { addChecksum, validateChecksum } from "./transaction-builder.mjs";

const SNAPSHOT = {
  generatedAt: "2026-08-22T20:00:00.000Z",
  destinationSafe: PUBLIC_MIGRATION_CONFIG.societySafe,
  chains: {
    1: { wethBalance: "104000714285714300" },
    137: {},
    8453: {
      usdcBalance: "1041961",
      zoraBalance: "271292401162931083",
      fameBalance: "34086517708905088080739131",
      fameUnit: "1000000000000000000000000",
    },
  },
};
const CREATED_AT = Date.parse(SNAPSHOT.generatedAt);

function packageFixture() {
  const artifacts = buildMigrationArtifacts(SNAPSHOT, {
    createdAt: CREATED_AT,
    newDonationVaultAddress: PUBLIC_MIGRATION_CONFIG.ethereumDonationVault,
  });
  const review = {
    generatedAt: SNAPSHOT.generatedAt,
    destinationSafe: PUBLIC_MIGRATION_CONFIG.societySafe,
    replacementDonationVault: PUBLIC_MIGRATION_CONFIG.ethereumDonationVault,
    snapshot: SNAPSHOT,
    batches: artifacts.batches.map(publicBatchRecord),
    blocked: artifacts.blocked,
    externalPrerequisites: artifacts.externalPrerequisites,
    operatorCalldataFile: "operator-calldata-not-safe-import.json",
  };
  return { artifacts, review };
}

test("binds every review record to the regenerated migration package", () => {
  const { artifacts, review } = packageFixture();

  assert.equal(validateReviewManifest(review).batches.length, artifacts.batches.length);
  const changedChain = structuredClone(review);
  changedChain.batches[0].chainId = 1;
  assert.throws(
    () => validateReviewManifest(changedChain),
    /review batch records does not match/,
  );
});

test("rejects a tampered batch even when its self-checksum is recomputed", () => {
  const { artifacts } = packageFixture();
  const expected = artifacts.batches[0];
  const record = publicBatchRecord(expected);
  const tampered = structuredClone(expected.builder);
  tampered.transactions[0].to =
    "0x000000000000000000000000000000000000dEaD";
  const selfChecksummed = addChecksum(tampered);

  assert.equal(validateChecksum(selfChecksummed), true);
  assert.throws(
    () => validateBatchPayload(record, selfChecksummed, expected),
    /payload does not match/,
  );
});

test("rejects operator calldata that differs from the reviewed package", () => {
  const { artifacts, review } = packageFixture();
  const payload = {
    schemaVersion: 1,
    status: "raw-calldata-only-not-a-safe-transaction-builder-file",
    generatedAt: review.snapshot.generatedAt,
    calls: structuredClone(artifacts.operatorCalls),
  };
  payload.calls[0].to = "0x000000000000000000000000000000000000dEaD";

  assert.throws(
    () => validateOperatorPayload(review, payload, artifacts),
    /operator calldata payload does not match/,
  );
});

test("preserves each validated record beside its executable batch", () => {
  const { artifacts } = packageFixture();
  const loaded = artifacts.batches.map((batch) => ({
    record: publicBatchRecord(batch),
    batch: batch.builder,
  }));
  const grouped = groupBatchesByChain(loaded);

  assert.equal(grouped[137][0].record.id, "P-CTRL-01");
  assert.equal(grouped[137][0].batch.meta.createdFromSafeAddress, ADDRESSES.oldSafes[137]);
});
