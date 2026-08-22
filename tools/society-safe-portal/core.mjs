import {
  concatHex,
  decodeEventLog,
  encodeFunctionData,
  getAddress,
  getContractAddress,
  keccak256,
  pad,
  parseAbi,
  size,
  toHex,
} from "viem";

import { SAFE_MANIFEST, SENTINEL_ADDRESS, ZERO_ADDRESS } from "./manifest.mjs";

export const FACTORY_ABI = parseAbi([
  "function createProxyWithNonceL2(address singleton, bytes initializer, uint256 saltNonce) returns (address proxy)",
  "function proxyCreationCode() view returns (bytes)",
  "event ProxyCreation(address indexed proxy, address singleton)",
  "event ProxyCreationL2(address indexed proxy, address singleton, bytes initializer, uint256 saltNonce)",
]);

export const SAFE_ABI = parseAbi([
  "event ExecutionSuccess(bytes32 indexed txHash, uint256 payment)",
  "event ExecutionFailure(bytes32 indexed txHash, uint256 payment)",
  "function VERSION() view returns (string)",
  "function setup(address[] owners, uint256 threshold, address to, bytes data, address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver)",
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
  "function nonce() view returns (uint256)",
  "function getModulesPaginated(address start, uint256 pageSize) view returns (address[] array, address next)",
  "function addOwnerWithThreshold(address owner, uint256 threshold)",
  "function removeOwner(address prevOwner, address owner, uint256 threshold)",
  "function execTransaction(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, bytes signatures) returns (bool success)",
]);

export const MULTISEND_ABI = parseAbi([
  "function multiSend(bytes transactions)",
]);

function sameAddress(left, right) {
  return typeof left === "string" && typeof right === "string"
    ? left.toLowerCase() === right.toLowerCase()
    : false;
}

function sameAddressList(left, right) {
  return (
    Array.isArray(left) &&
    Array.isArray(right) &&
    left.length === right.length &&
    left.every((address, index) => sameAddress(address, right[index]))
  );
}

export function buildInitializer(manifest = SAFE_MANIFEST) {
  const setup = manifest.initializer;
  return encodeFunctionData({
    abi: SAFE_ABI,
    functionName: "setup",
    args: [
      [...setup.owners],
      setup.threshold,
      setup.setupTo,
      setup.setupData,
      setup.fallbackHandler,
      setup.paymentToken,
      setup.payment,
      setup.paymentReceiver,
    ],
  });
}

export function deriveDeployment(proxyCreationCode, manifest = SAFE_MANIFEST) {
  const initializer = buildInitializer(manifest);
  const singletonWord = pad(manifest.safe.singleton, { size: 32 });
  const proxyInitCode = concatHex([proxyCreationCode, singletonWord]);
  const salt = keccak256(
    concatHex([
      keccak256(initializer),
      toHex(manifest.safe.saltNonce, { size: 32 }),
    ]),
  );
  const predictedAddress = getContractAddress({
    bytecode: proxyInitCode,
    from: manifest.safe.factory,
    opcode: "CREATE2",
    salt,
  });
  const transactionData = encodeFunctionData({
    abi: FACTORY_ABI,
    functionName: manifest.safe.creationMethod,
    args: [manifest.safe.singleton, initializer, manifest.safe.saltNonce],
  });

  return Object.freeze({
    initializer,
    initializerHash: keccak256(initializer),
    proxyCreationCodeHash: keccak256(proxyCreationCode),
    proxyInitCodeHash: keccak256(proxyInitCode),
    salt,
    predictedAddress,
    transactionData,
    transactionDataHash: keccak256(transactionData),
  });
}

export function validateDeploymentEvents(
  logs,
  deployment,
  manifest = SAFE_MANIFEST,
) {
  let sawProxyCreation = false;
  let sawProxyCreationL2 = false;

  for (const log of logs) {
    if (!sameAddress(log.address, manifest.safe.factory)) continue;
    let decoded;
    try {
      decoded = decodeEventLog({
        abi: FACTORY_ABI,
        data: log.data,
        topics: log.topics,
      });
    } catch {
      continue;
    }
    if (
      decoded.eventName !== "ProxyCreation" &&
      decoded.eventName !== "ProxyCreationL2"
    ) {
      continue;
    }
    if (!sameAddress(decoded.args.proxy, manifest.safe.predictedAddress)) {
      throw new Error(`${decoded.eventName} emitted an unexpected Safe address`);
    }
    if (!sameAddress(decoded.args.singleton, manifest.safe.singleton)) {
      throw new Error(`${decoded.eventName} emitted an unexpected singleton`);
    }
    if (decoded.eventName === "ProxyCreation") {
      sawProxyCreation = true;
      continue;
    }
    if (decoded.args.initializer.toLowerCase() !== deployment.initializer.toLowerCase()) {
      throw new Error("ProxyCreationL2 emitted an unexpected initializer");
    }
    if (decoded.args.saltNonce !== manifest.safe.saltNonce) {
      throw new Error("ProxyCreationL2 emitted an unexpected salt nonce");
    }
    sawProxyCreationL2 = true;
  }

  if (!sawProxyCreation) {
    throw new Error("receipt does not contain the expected ProxyCreation event");
  }
  if (!sawProxyCreationL2) {
    throw new Error("receipt does not contain the required ProxyCreationL2 event");
  }
  return Object.freeze({ sawProxyCreation, sawProxyCreationL2 });
}

export function encodeMultiSendCalls(calls) {
  return concatHex(
    calls.map((call) =>
      concatHex([
        toHex(call.operation, { size: 1 }),
        getAddress(call.to),
        toHex(call.value, { size: 32 }),
        toHex(size(call.data), { size: 32 }),
        call.data,
      ]),
    ),
  );
}

export function buildApprovedHashSignature(owner) {
  return concatHex([
    pad(getAddress(owner), { size: 32 }),
    toHex(0, { size: 32 }),
    toHex(1, { size: 1 }),
  ]);
}

export function buildBootstrap(manifest = SAFE_MANIFEST) {
  const safeAddress = manifest.safe.predictedAddress;
  const addCalls = [...manifest.finalOwners].reverse().map((owner) => ({
    method: "addOwnerWithThreshold",
    args: [owner, 1n],
    operation: 0,
    to: safeAddress,
    value: 0n,
    data: encodeFunctionData({
      abi: SAFE_ABI,
      functionName: "addOwnerWithThreshold",
      args: [owner, 1n],
    }),
  }));
  const removeCall = {
    method: "removeOwner",
    args: [
      manifest.finalOwners.at(-1),
      manifest.deployer,
      manifest.finalThreshold,
    ],
    operation: 0,
    to: safeAddress,
    value: 0n,
    data: encodeFunctionData({
      abi: SAFE_ABI,
      functionName: "removeOwner",
      args: [
        manifest.finalOwners.at(-1),
        manifest.deployer,
        manifest.finalThreshold,
      ],
    }),
  };
  const calls = Object.freeze([...addCalls, Object.freeze(removeCall)]);
  const packedCalls = encodeMultiSendCalls(calls);
  const multiSendData = encodeFunctionData({
    abi: MULTISEND_ABI,
    functionName: "multiSend",
    args: [packedCalls],
  });
  const signatures = buildApprovedHashSignature(manifest.deployer);
  const execArgs = Object.freeze([
    manifest.safe.multiSendCallOnly,
    0n,
    multiSendData,
    1,
    0n,
    0n,
    0n,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    signatures,
  ]);
  const transactionData = encodeFunctionData({
    abi: SAFE_ABI,
    functionName: "execTransaction",
    args: execArgs,
  });

  return Object.freeze({
    calls,
    packedCalls,
    multiSendData,
    signatures,
    execArgs,
    transactionData,
    transactionDataHash: keccak256(transactionData),
  });
}

export function storageWordToAddress(word) {
  if (typeof word !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(word)) {
    throw new Error("storage word must be 32 bytes");
  }
  return getAddress(`0x${word.slice(-40)}`);
}

function check(label, expected, actual, pass) {
  return Object.freeze({ label, expected, actual, pass });
}

function commonSafeChecks(snapshot, manifest) {
  return [
    check(
      "Safe version",
      manifest.safe.release,
      snapshot.version,
      snapshot.version === manifest.safe.release,
    ),
    check(
      "Singleton",
      manifest.safe.singleton,
      snapshot.singleton,
      sameAddress(snapshot.singleton, manifest.safe.singleton),
    ),
    check(
      "Fallback handler",
      manifest.safe.fallbackHandler,
      snapshot.fallbackHandler,
      sameAddress(snapshot.fallbackHandler, manifest.safe.fallbackHandler),
    ),
    check(
      "Guard",
      ZERO_ADDRESS,
      snapshot.guard,
      sameAddress(snapshot.guard, ZERO_ADDRESS),
    ),
    check(
      "Modules",
      "none",
      snapshot.modules,
      Array.isArray(snapshot.modules) &&
        snapshot.modules.length === 0 &&
        sameAddress(snapshot.modulesNext, SENTINEL_ADDRESS),
    ),
  ];
}

export function classifySafeState(snapshot, manifest = SAFE_MANIFEST) {
  if (!snapshot.code || snapshot.code === "0x") {
    return Object.freeze({ phase: "empty", checks: Object.freeze([]) });
  }

  const common = commonSafeChecks(snapshot, manifest);
  const bootstrapChecks = [
    ...common,
    check(
      "Owners",
      manifest.initializer.owners,
      snapshot.owners,
      sameAddressList(snapshot.owners, manifest.initializer.owners),
    ),
    check(
      "Threshold",
      "1",
      String(snapshot.threshold),
      snapshot.threshold === 1n,
    ),
    check(
      "Safe nonce",
      "0",
      String(snapshot.nonce),
      snapshot.nonce === manifest.bootstrapSafeNonce,
    ),
  ];
  if (bootstrapChecks.every((item) => item.pass)) {
    return Object.freeze({
      phase: "bootstrap-ready",
      checks: Object.freeze(bootstrapChecks),
    });
  }

  const completeChecks = [
    ...common,
    check(
      "Owners",
      manifest.finalOwners,
      snapshot.owners,
      sameAddressList(snapshot.owners, manifest.finalOwners),
    ),
    check(
      "Threshold",
      String(manifest.finalThreshold),
      String(snapshot.threshold),
      snapshot.threshold === manifest.finalThreshold,
    ),
    check("Safe nonce", "1", String(snapshot.nonce), snapshot.nonce === 1n),
    check(
      "Deployer removed",
      "not an owner",
      snapshot.owners,
      !snapshot.owners.some((owner) => sameAddress(owner, manifest.deployer)),
    ),
  ];
  if (completeChecks.every((item) => item.pass)) {
    return Object.freeze({
      phase: "complete",
      checks: Object.freeze(completeChecks),
    });
  }

  return Object.freeze({
    phase: "invalid",
    checks: Object.freeze(
      completeChecks.map((item) =>
        item.pass
          ? item
          : Object.freeze({ ...item, bootstrapStateAlsoFailed: true }),
      ),
    ),
  });
}

export function assertManifest(manifest = SAFE_MANIFEST) {
  const addresses = [
    manifest.deployer,
    manifest.safe.factory,
    manifest.safe.singleton,
    manifest.safe.fallbackHandler,
    manifest.safe.multiSendCallOnly,
    manifest.safe.predictedAddress,
    ...manifest.initializer.owners,
    ...manifest.finalOwners,
  ];
  for (const address of addresses) {
    if (getAddress(address) !== address)
      throw new Error(`non-checksummed address: ${address}`);
  }
  if (manifest.finalOwners.length !== 15)
    throw new Error("expected exactly 15 final owners");
  if (manifest.safe.release !== "1.5.0")
    throw new Error("Safe release must be 1.5.0");
  if (manifest.safe.creationMethod !== "createProxyWithNonceL2") {
    throw new Error("deployment must use createProxyWithNonceL2");
  }
  if (
    new Set(manifest.finalOwners.map((address) => address.toLowerCase()))
      .size !== 15
  ) {
    throw new Error("final owners must be unique");
  }
  if (
    manifest.finalOwners.some((owner) => sameAddress(owner, manifest.deployer))
  ) {
    throw new Error("deployer must not remain in final owner set");
  }
  if (manifest.finalThreshold !== 7n)
    throw new Error("final threshold must be 7");
  if (manifest.bootstrapSafeNonce !== 0n)
    throw new Error("bootstrap Safe nonce must be 0");
  if (!sameAddress(manifest.initializer.owners[0], manifest.deployer)) {
    throw new Error("initializer owner must be the deployer");
  }
  if (manifest.initializer.threshold !== 1n)
    throw new Error("initializer threshold must be 1");
  if (
    !sameAddress(
      manifest.finalOwners.at(-1),
      "0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db",
    )
  ) {
    throw new Error("approved new signer must be last");
  }
  return manifest;
}

export { SENTINEL_ADDRESS };
