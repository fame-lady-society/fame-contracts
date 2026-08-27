import assert from "node:assert/strict";
import test from "node:test";

import {
  addChecksum,
  buildTransactionBuilderBatch,
  validateChecksum,
} from "./transaction-builder.mjs";

const SAFE_OFFICIAL_CHECKSUM_VECTOR = {
  version: "1.0",
  chainId: "4",
  createdAt: 1646321521061,
  meta: {
    name: "test batch file",
    txBuilderVersion: "1.4.0",
    checksum: "",
    createdFromSafeAddress: "0xDF8a1Ce35c9a6ACE153B4e0767942f1E2291a1Aa",
    createdFromOwnerAddress: "0x49d4450977E2c95362C13D3a31a09311E0Ea26A6",
  },
  transactions: [
    {
      to: "0x49d4450977E2c95362C13D3a31a09311E0Ea26A6",
      value: "0",
      contractMethod: {
        inputs: [
          {
            internalType: "address",
            name: "paramAddress",
            type: "address",
          },
        ],
        name: "testAddress",
        payable: false,
      },
      contractInputsValues: {
        paramAddress: "0x49d4450977E2c95362C13D3a31a09311E0Ea26A6",
      },
    },
    {
      to: "0x49d4450977E2c95362C13D3a31a09311E0Ea26A6",
      value: "0",
      contractMethod: {
        inputs: [
          {
            internalType: "bool",
            name: "paramBool",
            type: "bool",
          },
        ],
        name: "testBool",
        payable: false,
      },
      contractInputsValues: {
        paramAddress: "",
        paramBool: "false",
      },
    },
    {
      to: "0x49d4450977E2c95362C13D3a31a09311E0Ea26A6",
      value: "2000000000000000000",
      data: "0x42f4579000000000000000000000000049d4450977e2c95362c13d3a31a09311e0ea26a6",
    },
  ],
};

test("matches Safe Transaction Builder's official checksum vector", () => {
  const batch = addChecksum(SAFE_OFFICIAL_CHECKSUM_VECTOR);

  assert.equal(
    batch.meta.checksum,
    "0x86c81826dbf7e8a37612153294cc85fdf5c81998dd0a44b86d945502a7eace7c",
  );
  assert.equal(validateChecksum(batch), true);
});

test("builds an importable raw-calldata batch for the exact source Safe", () => {
  const batch = buildTransactionBuilderBatch({
    chainId: 8453,
    safeAddress: "0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D",
    name: "Base Society migration",
    description: "Unsigned review artifact",
    createdAt: 1724350000000,
    calls: [
      {
        to: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        value: "0",
        data: "0xa9059cbb0000000000000000000000000000fa3e509d629516ae56dc6fdd31047300114d00000000000000000000000000000000000000000000000000000000000fe629",
      },
    ],
  });

  assert.equal(batch.version, "1.0");
  assert.equal(batch.chainId, "8453");
  assert.equal(batch.meta.txBuilderVersion, "2.1.0");
  assert.equal(
    batch.meta.createdFromSafeAddress,
    "0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D",
  );
  assert.equal(batch.meta.createdFromOwnerAddress, "");
  assert.deepEqual(Object.keys(batch.transactions[0]).sort(), [
    "data",
    "to",
    "value",
  ]);
  assert.equal(validateChecksum(batch), true);
});

test("refuses unresolved placeholders, empty batches, and malformed calldata", () => {
  const base = {
    chainId: 1,
    safeAddress: "0xCDF3e235A04624d7f23909EbBaD008Db2c54e1cF",
    name: "Unsafe batch",
    description: "must fail",
    createdAt: 1724350000000,
  };

  assert.throws(
    () => buildTransactionBuilderBatch({ ...base, calls: [] }),
    /at least one transaction/,
  );
  assert.throws(
    () =>
      buildTransactionBuilderBatch({
        ...base,
        calls: [
          {
            to: "$NEW_SAFE",
            value: "0",
            data: "0x",
          },
        ],
      }),
    /valid target address/,
  );
  assert.throws(
    () =>
      buildTransactionBuilderBatch({
        ...base,
        calls: [
          {
            to: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            value: "0",
            data: "$REFRESHED_CALLDATA",
          },
        ],
      }),
    /hex calldata/,
  );
});
