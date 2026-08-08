import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { keccak256 } from "viem";

import {
  INITCODE_LIMIT_BYTES,
  RUNTIME_LIMIT_BYTES,
  assertReleaseSizes,
  buildReleaseEvidence,
  canonicalJson,
  compareEvidence,
  inspectReleaseArtifact,
  writeJsonAtomically,
} from "./marketplace-release-evidence.mjs";

function artifact({
  initcodeBytes = 10,
  runtimeBytes = 8,
  solc = "0.8.36+commit.test",
  constructorInputs = [],
} = {}) {
  return {
    abi: [
      { type: "constructor", inputs: constructorInputs, stateMutability: "nonpayable" },
      { type: "function", name: "value", inputs: [], outputs: [] },
    ],
    storageLayout: { storage: [], types: {} },
    bytecode: { object: `0x${"11".repeat(initcodeBytes)}` },
    deployedBytecode: { object: `0x${"22".repeat(runtimeBytes)}` },
    metadata: {
      compiler: { version: solc },
      settings: {
        evmVersion: "cancun",
        optimizer: { enabled: true, runs: 200 },
        viaIR: false,
      },
    },
  };
}

test("canonical JSON is independent of object key insertion order", () => {
  assert.equal(canonicalJson({ b: 2, a: { d: 4, c: 3 } }), canonicalJson({ a: { c: 3, d: 4 }, b: 2 }));
});

test("inspects exact runtime and initcode sizes and headroom", () => {
  const result = inspectReleaseArtifact("Release", artifact({ initcodeBytes: 123, runtimeBytes: 45 }));
  assert.equal(result.creationBytecodeSizeBytes, 123);
  assert.equal(result.constructorArgsSizeBytes, 0);
  assert.equal(result.initcodeSizeBytes, 123);
  assert.equal(result.initcodeHeadroomBytes, INITCODE_LIMIT_BYTES - 123);
  assert.equal(result.runtimeSizeBytes, 45);
  assert.equal(result.runtimeHeadroomBytes, RUNTIME_LIMIT_BYTES - 45);
});

test("counts ABI-encoded constructor bytes without changing the raw creation-bytecode hash", () => {
  const creationBytecode = `0x${"11".repeat(123)}`;
  const result = inspectReleaseArtifact(
    "Release",
    artifact({
      initcodeBytes: 123,
      constructorInputs: [
        { name: "owner", type: "address" },
        { name: "fee", type: "uint256" },
      ],
    }),
    undefined,
    undefined,
    ["0x1111111111111111111111111111111111111111", 1n],
  );

  assert.equal(result.creationBytecodeHash, keccak256(creationBytecode));
  assert.equal(result.creationBytecodeSizeBytes, 123);
  assert.equal(result.constructorArgsSizeBytes, 64);
  assert.equal(result.initcodeSizeBytes, 187);
  assert.equal(result.initcodeHeadroomBytes, INITCODE_LIMIT_BYTES - 187);
});

test("rejects full deploy data over EIP-3860 when raw creation bytecode is below the limit", () => {
  const result = inspectReleaseArtifact(
    "Release",
    artifact({
      initcodeBytes: INITCODE_LIMIT_BYTES - 31,
      constructorInputs: [{ name: "value", type: "uint256" }],
    }),
    undefined,
    undefined,
    [1n],
  );

  assert.equal(result.creationBytecodeSizeBytes, INITCODE_LIMIT_BYTES - 31);
  assert.equal(result.constructorArgsSizeBytes, 32);
  assert.equal(result.initcodeSizeBytes, INITCODE_LIMIT_BYTES + 1);
  assert.equal(result.initcodeHeadroomBytes, -1);
  assert.throws(() => assertReleaseSizes({ Release: result }), /EIP-3860/);
});

test("rejects the wrong compiler even when other profile settings match", () => {
  assert.throws(
    () => inspectReleaseArtifact("Release", artifact({ solc: "0.8.28+commit.old" })),
    /expected 0\.8\.36/,
  );
});

test("can inspect the pinned 0.8.28 compiler-delta baseline explicitly", () => {
  assert.doesNotThrow(() =>
    inspectReleaseArtifact("Release", artifact({ solc: "0.8.28+commit.old" }), undefined, "0.8.28"),
  );
});

test("fails only when a named release target exceeds an applicable limit", () => {
  const valid = inspectReleaseArtifact("Release", artifact());
  assert.doesNotThrow(() => assertReleaseSizes({ Release: valid }));
  assert.throws(
    () => assertReleaseSizes({ Release: { ...valid, runtimeSizeBytes: RUNTIME_LIMIT_BYTES + 1, runtimeHeadroomBytes: -1 } }),
    /EIP-170/,
  );
  assert.throws(
    () => assertReleaseSizes({ Release: { ...valid, initcodeSizeBytes: INITCODE_LIMIT_BYTES + 1, initcodeHeadroomBytes: -1 } }),
    /EIP-3860/,
  );
});

test("the scoped gate ignores unrelated oversized script artifacts", async () => {
  const root = await mkdtemp(join(tmpdir(), "fame-release-sizes-"));
  const releaseArtifact = "out/Release.sol/Release.json";
  await mkdir(join(root, "out/Release.sol"), { recursive: true });
  await mkdir(join(root, "out/LegacyScript.sol"), { recursive: true });
  await writeFile(join(root, releaseArtifact), JSON.stringify(artifact()), "utf8");
  await writeFile(
    join(root, "out/LegacyScript.sol/LegacyScript.json"),
    JSON.stringify(artifact({ initcodeBytes: INITCODE_LIMIT_BYTES + 1, runtimeBytes: RUNTIME_LIMIT_BYTES + 1 })),
    "utf8",
  );

  const evidence = await buildReleaseEvidence({
    root,
    targets: [{ name: "Release", artifact: releaseArtifact }],
    sourceCommit: "test",
    forgeVersion: "test",
    workingTreeClean: true,
  });
  assert.equal(evidence.contracts.Release.runtimeSizeBytes, 8);
});

test("build evidence includes each target's constructor arguments in initcode", async () => {
  const root = await mkdtemp(join(tmpdir(), "fame-release-constructor-"));
  const releaseArtifact = "out/Release.sol/Release.json";
  await mkdir(join(root, "out/Release.sol"), { recursive: true });
  await writeFile(
    join(root, releaseArtifact),
    JSON.stringify(
      artifact({
        initcodeBytes: 10,
        constructorInputs: [{ name: "value", type: "uint256" }],
      }),
    ),
    "utf8",
  );

  const evidence = await buildReleaseEvidence({
    root,
    targets: [{ name: "Release", artifact: releaseArtifact, constructorArgs: [1n] }],
    sourceCommit: "test",
    forgeVersion: "test",
    workingTreeClean: true,
  });

  assert.equal(evidence.contracts.Release.creationBytecodeSizeBytes, 10);
  assert.equal(evidence.contracts.Release.constructorArgsSizeBytes, 32);
  assert.equal(evidence.contracts.Release.initcodeSizeBytes, 42);
});

test("requires storage layout output for compiler-delta evidence", () => {
  const incomplete = artifact();
  delete incomplete.storageLayout;
  assert.throws(() => inspectReleaseArtifact("Release", incomplete), /missing required compiler output/);
});

test("reports compiler baseline deltas without treating expected bytecode drift as failure", () => {
  const current = { contracts: { Release: { abiHash: "a", storageLayoutHash: "s", creationBytecodeHash: "c2", runtimeBytecodeHash: "r2", initcodeSizeBytes: 12, runtimeSizeBytes: 9 } } };
  const baseline = { toolchain: { solcVersion: "0.8.28" }, contracts: { Release: { abiHash: "a", storageLayoutHash: "s", creationBytecodeHash: "c1", runtimeBytecodeHash: "r1", initcodeSizeBytes: 10, runtimeSizeBytes: 8 } } };
  assert.deepEqual(compareEvidence(current, baseline), {
    baselineSolcVersion: "0.8.28",
    contracts: {
      Release: {
        abiChanged: false,
        storageLayoutChanged: false,
        creationBytecodeChanged: true,
        runtimeBytecodeChanged: true,
        initcodeSizeDeltaBytes: 2,
        runtimeSizeDeltaBytes: 1,
      },
    },
  });
});

test("writes complete evidence atomically", async () => {
  const directory = await mkdtemp(join(tmpdir(), "fame-release-evidence-"));
  const output = join(directory, "evidence.json");
  await writeJsonAtomically(output, { schemaVersion: 1, contracts: { Release: { runtimeSizeBytes: 8 } } });
  assert.deepEqual(JSON.parse(await readFile(output, "utf8")), {
    schemaVersion: 1,
    contracts: { Release: { runtimeSizeBytes: 8 } },
  });
});
