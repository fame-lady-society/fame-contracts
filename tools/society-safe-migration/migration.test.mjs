import assert from "node:assert/strict";
import test from "node:test";

import { keccak256, toBytes } from "viem";

import {
  ADDRESSES,
  CURRENT_FLS_TOKEN_IDS,
  SQUAD_TOKEN_IDS,
  buildMigrationArtifacts,
} from "./migration.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";

const SNAPSHOT = {
  generatedAt: "2026-08-22T20:00:00.000Z",
  chains: {
    1: {
      blockNumber: "25810000",
      oldSafeNonce: "32",
      newSafeNonce: "1",
      wethBalance: "104000714285714300",
    },
    137: {
      blockNumber: "92370000",
      oldSafeNonce: "5",
      newSafeNonce: "1",
    },
    8453: {
      blockNumber: "50300000",
      oldSafeNonce: "4",
      newSafeNonce: "1",
      usdcBalance: "1041961",
      zoraBalance: "271292401162931083",
      fameBalance: "34086517708905088080739131",
      fameUnit: "1000000000000000000000000",
    },
  },
};
const NEW_DONATION_VAULT = PUBLIC_MIGRATION_CONFIG.ethereumDonationVault;

test("builds approved asset and authority batches in their required order", () => {
  const artifacts = buildMigrationArtifacts(SNAPSHOT, {
    createdAt: 1724350000000,
    flsChunkSize: 20,
    newDonationVaultAddress: NEW_DONATION_VAULT,
  });
  const byId = new Map(artifacts.batches.map((batch) => [batch.id, batch]));

  assert.deepEqual(
    byId.get("B-FAME-DN404").calls.map((call) => call.id),
    [
      "B-FAME-MIRROR-170",
      "B-FAME-MIRROR-230",
      "B-FAME-MIRROR-424",
      "B-FAME-MIRROR-479",
      "B-CORE-FAME-REMAINDER",
    ],
  );
  assert.equal(
    byId.get("B-FAME-DN404").calls.at(-1).args[1],
    "30086517708905088080739131",
  );
  assert.deepEqual(byId.get("E-FLS-AUTHORITY-HANDOFF").calls.map((call) => call.id), [
    "E-FLS-ADMIN-GRANT",
    "E-FLS-TREASURER-GRANT",
    "E-FLS-ROYALTY-RECEIVER",
    "E-FLS-OWNER-START",
  ]);
  assert.deepEqual(byId.get("E-POST-MIGRATION-AUTHORITY").calls.map((call) => call.id), [
    "E-FLS-OWNER-ACCEPT",
    "E-FLS-REVOKE-OLD-TREASURER",
    "E-FLS-REVOKE-OLD-ADMIN",
    "E-FLS-REVOKE-OLD-DONATION",
    "E-ENS-REVERSE",
  ]);
  assert.equal(
    byId.get("E-POST-MIGRATION-AUTHORITY").sourceSafe,
    ADDRESSES.newSafe,
  );
  assert.deepEqual(byId.get("E-FLS-DONATION-GRANT").calls[0].args, [
    "0x3496e2e73c4d42b75d702e60d9e48102720b8691234415963a5a857b86425d07",
    NEW_DONATION_VAULT,
  ]);
});

test("wraps the exact 27 Squad IDs and prepares all 107 FLS transfers in chunks", () => {
  const artifacts = buildMigrationArtifacts(SNAPSHOT, {
    createdAt: 1724350000000,
    flsChunkSize: 20,
    newDonationVaultAddress: NEW_DONATION_VAULT,
  });
  const wrap = artifacts.batches.find((batch) => batch.id === "E-SQUAD-WRAP-FIRST");
  const flsChunks = artifacts.batches.filter((batch) =>
    batch.id.startsWith("E-FLS-721-"),
  );

  assert.deepEqual(wrap.calls[0].args[0], SQUAD_TOKEN_IDS.map(String));
  assert.equal(flsChunks.length, 6);
  assert.equal(flsChunks.flatMap((batch) => batch.calls).length, 107);
  assert.deepEqual(
    flsChunks.flatMap((batch) => batch.calls.map((call) => Number(call.args[2]))),
    [...CURRENT_FLS_TOKEN_IDS, ...SQUAD_TOKEN_IDS].sort((a, b) => a - b),
  );
});

test("emits only exact calldata in importable files and keeps unresolved work blocked", () => {
  const artifacts = buildMigrationArtifacts(SNAPSHOT, {
    createdAt: 1724350000000,
    flsChunkSize: 20,
    newDonationVaultAddress: NEW_DONATION_VAULT,
  });

  for (const batch of artifacts.batches) {
    assert.equal(batch.builder.meta.checksum.startsWith("0x"), true);
    for (const transaction of batch.builder.transactions) {
      assert.match(transaction.to, /^0x[0-9a-fA-F]{40}$/);
      assert.match(transaction.value, /^\d+$/);
      assert.match(transaction.data, /^0x(?:[0-9a-fA-F]{2})*$/);
      assert.equal(JSON.stringify(transaction).includes("$"), false);
    }
  }

  assert.deepEqual(
    artifacts.blocked.map((item) => item.id),
    [
      "CANARY-TRANSFERS",
      "B-NATIVE-FINAL",
      "E-NATIVE-FINAL",
    ],
  );
  assert.equal(
    artifacts.operatorCalls.every((call) => call.data.startsWith("0x")),
    true,
  );
});

test("matches the fully reviewed call and execution-gate vector", () => {
  const artifacts = buildMigrationArtifacts(SNAPSHOT, {
    createdAt: 1724350000000,
    flsChunkSize: 20,
    newDonationVaultAddress: NEW_DONATION_VAULT,
  });
  const reviewedVector = {
    batches: artifacts.batches.map(
      ({ id, chainId, sourceSafe, calls, executionGate }) => ({
        id,
        chainId,
        sourceSafe,
        calls,
        executionGate,
      }),
    ),
    operatorCalls: artifacts.operatorCalls,
  };

  assert.equal(
    keccak256(toBytes(JSON.stringify(reviewedVector))),
    "0x06938e0f5b8c58fdd2990fb6a0a189677a08eaf9b23b4f31bdc2a8a365b36cd9",
  );
});

test("refuses impossible live balance arithmetic", () => {
  const impossible = structuredClone(SNAPSHOT);
  impossible.chains[8453].fameBalance = "3999999999999999999999999";

  assert.throws(
    () =>
      buildMigrationArtifacts(impossible, {
        newDonationVaultAddress: NEW_DONATION_VAULT,
      }),
    /smaller than the four mirror units/,
  );
});

test("refuses to build a complete set without the deployed donation vault address", () => {
  assert.throws(
    () => buildMigrationArtifacts(SNAPSHOT),
    /newDonationVaultAddress is required/,
  );
});

test("refuses a donation vault that differs from curated public config", () => {
  assert.throws(
    () =>
      buildMigrationArtifacts(SNAPSHOT, {
        newDonationVaultAddress:
          "0x1234567890123456789012345678901234567890",
      }),
    /does not match config\/fame-public.env/,
  );
});
