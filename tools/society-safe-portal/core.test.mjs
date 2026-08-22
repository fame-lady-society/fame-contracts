import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  Interface,
  concat,
  getCreate2Address,
  keccak256 as ethersKeccak256,
  toBeHex,
  zeroPadValue,
} from "ethers";
import { decodeFunctionData, getAddress } from "viem";

import {
  SAFE_ABI,
  assertManifest,
  buildApprovedHashSignature,
  buildBootstrap,
  buildInitializer,
  classifySafeState,
  deriveDeployment,
  storageWordToAddress,
  validateDeploymentEvents,
} from "./core.mjs";
import { SAFE_MANIFEST, ZERO_ADDRESS } from "./manifest.mjs";

const proxyCreationCode = (
  await readFile(
    new URL("./proxy-creation-code-v1.5.0.txt", import.meta.url),
    "utf8",
  )
).trim();

function parsePackedCalls(packed) {
  const raw = packed.slice(2);
  const calls = [];
  let cursor = 0;
  while (cursor < raw.length) {
    const operation = Number.parseInt(raw.slice(cursor, cursor + 2), 16);
    cursor += 2;
    const to = getAddress(`0x${raw.slice(cursor, cursor + 40)}`);
    cursor += 40;
    const value = BigInt(`0x${raw.slice(cursor, cursor + 64)}`);
    cursor += 64;
    const dataLength = Number(BigInt(`0x${raw.slice(cursor, cursor + 64)}`));
    cursor += 64;
    const data = `0x${raw.slice(cursor, cursor + dataLength * 2)}`;
    cursor += dataLength * 2;
    calls.push({ operation, to, value, data });
  }
  assert.equal(cursor, raw.length);
  return calls;
}

function safeSnapshot(overrides = {}) {
  return {
    code: "0x60016000",
    version: SAFE_MANIFEST.safe.release,
    singleton: SAFE_MANIFEST.safe.singleton,
    fallbackHandler: SAFE_MANIFEST.safe.fallbackHandler,
    guard: ZERO_ADDRESS,
    modules: [],
    modulesNext: "0x0000000000000000000000000000000000000001",
    owners: [SAFE_MANIFEST.deployer],
    threshold: 1n,
    nonce: 0n,
    ...overrides,
  };
}

test("manifest is checksummed, unique, and fixed at 7-of-15", () => {
  assert.equal(assertManifest(), SAFE_MANIFEST);
  assert.equal(SAFE_MANIFEST.finalOwners.length, 15);
  assert.equal(SAFE_MANIFEST.finalThreshold, 7n);
  assert.equal(
    SAFE_MANIFEST.finalOwners.at(-1),
    "0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db",
  );
});

test("portal manifest matches the committed migration template", async () => {
  const template = JSON.parse(
    await readFile(
      new URL(
        "../../docs/plans/2026-08-20-001-ops-society-vault-transaction-template.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  assert.equal(SAFE_MANIFEST.deployer, template.parameters.deploymentPayer);
  assert.deepEqual(
    SAFE_MANIFEST.finalOwners,
    template.parameters.finalOwnersOrdered,
  );
  assert.equal(
    SAFE_MANIFEST.finalThreshold,
    BigInt(template.parameters.finalThreshold),
  );
  assert.equal(SAFE_MANIFEST.safe.release, template.parameters.safeRelease);
  assert.equal(SAFE_MANIFEST.safe.factory, template.parameters.proxyFactory);
  assert.equal(SAFE_MANIFEST.safe.singleton, template.parameters.singleton);
  assert.equal(
    SAFE_MANIFEST.safe.fallbackHandler,
    template.parameters.fallbackHandler,
  );
  assert.equal(
    SAFE_MANIFEST.safe.multiSendCallOnly,
    template.parameters.multiSendCallOnly,
  );
  assert.equal(
    SAFE_MANIFEST.safe.saltNonce,
    BigInt(template.parameters.saltNonce),
  );
  assert.equal(
    SAFE_MANIFEST.safe.predictedAddress,
    template.parameters.predictedSafeAddress,
  );
});

test("deployment derivation reproduces the independently approved address and hashes", () => {
  const actual = deriveDeployment(proxyCreationCode);
  const setupInterface = new Interface([
    "function setup(address[] owners,uint256 threshold,address to,bytes data,address fallbackHandler,address paymentToken,uint256 payment,address paymentReceiver)",
  ]);
  const factoryInterface = new Interface([
    "function createProxyWithNonceL2(address singleton,bytes initializer,uint256 saltNonce) returns (address proxy)",
  ]);
  const initializer = setupInterface.encodeFunctionData("setup", [
    [SAFE_MANIFEST.deployer],
    1n,
    ZERO_ADDRESS,
    "0x",
    SAFE_MANIFEST.safe.fallbackHandler,
    ZERO_ADDRESS,
    0n,
    ZERO_ADDRESS,
  ]);
  const initCode = concat([
    proxyCreationCode,
    zeroPadValue(SAFE_MANIFEST.safe.singleton, 32),
  ]);
  const salt = ethersKeccak256(
    concat([
      ethersKeccak256(initializer),
      zeroPadValue(toBeHex(SAFE_MANIFEST.safe.saltNonce), 32),
    ]),
  );
  const independentlyPredicted = getCreate2Address(
    SAFE_MANIFEST.safe.factory,
    salt,
    ethersKeccak256(initCode),
  );

  assert.equal(buildInitializer(), initializer);
  assert.equal(
    actual.transactionData,
    factoryInterface.encodeFunctionData("createProxyWithNonceL2", [
      SAFE_MANIFEST.safe.singleton,
      initializer,
      SAFE_MANIFEST.safe.saltNonce,
    ]),
  );
  assert.equal(
    actual.initializerHash,
    "0xa6738cb7343d6e102e6f55e7e8a9104e10e99016b5d7d01004c89468fb255e06",
  );
  assert.equal(
    actual.proxyCreationCodeHash,
    SAFE_MANIFEST.safe.proxyCreationCodeHash,
  );
  assert.equal(actual.predictedAddress, independentlyPredicted);
  assert.equal(actual.predictedAddress, SAFE_MANIFEST.safe.predictedAddress);
  assert.equal(
    actual.transactionDataHash,
    "0xf35f2ebf941c5182d45cc2824440f8c9b63d715cafa1db69caacb151f4221dea",
  );
});

test("deployment verification requires the detailed L2 creation event", () => {
  const deployment = deriveDeployment(proxyCreationCode);
  const factoryInterface = new Interface([
    "event ProxyCreation(address indexed proxy,address singleton)",
    "event ProxyCreationL2(address indexed proxy,address singleton,bytes initializer,uint256 saltNonce)",
  ]);
  const proxyCreation = factoryInterface.encodeEventLog(
    factoryInterface.getEvent("ProxyCreation"),
    [SAFE_MANIFEST.safe.predictedAddress, SAFE_MANIFEST.safe.singleton],
  );
  const proxyCreationL2 = factoryInterface.encodeEventLog(
    factoryInterface.getEvent("ProxyCreationL2"),
    [
      SAFE_MANIFEST.safe.predictedAddress,
      SAFE_MANIFEST.safe.singleton,
      deployment.initializer,
      SAFE_MANIFEST.safe.saltNonce,
    ],
  );
  const asLog = (encoded) => ({
    address: SAFE_MANIFEST.safe.factory,
    data: encoded.data,
    topics: encoded.topics,
  });

  assert.deepEqual(
    validateDeploymentEvents(
      [asLog(proxyCreation), asLog(proxyCreationL2)],
      deployment,
    ),
    { sawProxyCreation: true, sawProxyCreationL2: true },
  );
  assert.throws(
    () => validateDeploymentEvents([asLog(proxyCreation)], deployment),
    /required ProxyCreationL2/,
  );
});

test("bootstrap installs owners in approved order and finishes by removing the deployer", () => {
  const value = buildBootstrap();
  assert.equal(value.calls.length, 16);
  assert.equal(
    value.transactionDataHash,
    "0x9f9a7553e1a14b3f03f6592f86f0b5850db3bc9c32f93f433c78f2ecd7d8badb",
  );
  assert.equal((value.signatures.length - 2) / 2, 65);
  assert.equal(value.signatures.slice(-2), "01");

  const packedCalls = parsePackedCalls(value.packedCalls);
  assert.equal(packedCalls.length, value.calls.length);
  for (const [index, call] of packedCalls.entries()) {
    assert.equal(call.operation, 0);
    assert.equal(call.to, SAFE_MANIFEST.safe.predictedAddress);
    assert.equal(call.value, 0n);
    const decoded = decodeFunctionData({ abi: SAFE_ABI, data: call.data });
    if (index < 15) {
      assert.equal(decoded.functionName, "addOwnerWithThreshold");
      assert.equal(
        decoded.args[0],
        [...SAFE_MANIFEST.finalOwners].reverse()[index],
      );
      assert.equal(decoded.args[1], 1n);
    } else {
      assert.equal(decoded.functionName, "removeOwner");
      assert.equal(decoded.args[0], SAFE_MANIFEST.finalOwners.at(-1));
      assert.equal(decoded.args[1], SAFE_MANIFEST.deployer);
      assert.equal(decoded.args[2], 7n);
    }
  }
});

test("sender-approved signature encodes owner in r and v=1", () => {
  const signature = buildApprovedHashSignature(SAFE_MANIFEST.deployer);
  assert.equal((signature.length - 2) / 2, 65);
  assert.equal(
    storageWordToAddress(`0x${signature.slice(2, 66)}`),
    SAFE_MANIFEST.deployer,
  );
  assert.equal(BigInt(`0x${signature.slice(66, 130)}`), 0n);
  assert.equal(signature.slice(130), "01");
});

test("Safe state classification only accepts exact bootstrap and terminal states", () => {
  assert.equal(classifySafeState({ code: "0x" }).phase, "empty");
  assert.equal(classifySafeState(safeSnapshot()).phase, "bootstrap-ready");
  assert.equal(
    classifySafeState(
      safeSnapshot({
        owners: [...SAFE_MANIFEST.finalOwners],
        threshold: 7n,
        nonce: 1n,
      }),
    ).phase,
    "complete",
  );
  assert.equal(
    classifySafeState(
      safeSnapshot({
        owners: [...SAFE_MANIFEST.finalOwners].reverse(),
        threshold: 7n,
        nonce: 1n,
      }),
    ).phase,
    "invalid",
  );
  assert.equal(
    classifySafeState(safeSnapshot({ guard: SAFE_MANIFEST.deployer })).phase,
    "invalid",
  );
});
