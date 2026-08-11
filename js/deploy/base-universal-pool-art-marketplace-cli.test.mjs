import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  HttpRequestError,
  TransactionReceiptNotFoundError,
  encodeAbiParameters,
  encodeEventTopics,
  keccak256,
  parseAbi,
  stringToHex,
} from "viem";

import {
  findCanonicalTransaction,
  main,
  reconcile,
  reconcileOperation,
  waitForReceiptWithPersistedReplacements,
} from "./base-universal-pool-art-marketplace.mjs";

import {
  assertRpcMode,
  deploymentErrorDetails,
  parseCommandArguments,
} from "./base-universal-pool-art-marketplace-helpers.mjs";
import {
  prepareLifecycleOperation,
  writeManifestAtomic,
} from "./base-universal-pool-art-marketplace-state.mjs";

const DEPLOYER = "0x1111111111111111111111111111111111111111";
const MARKETPLACE = "0x2222222222222222222222222222222222222222";
const CHECKOUT = "0x3333333333333333333333333333333333333333";
const SAFE = "0xc952c53d8b63919e372caa2e6fee605ee24e4d3d";
const ZERO = "0x0000000000000000000000000000000000000000";
const MARKET_CODE = "0x60016000";
const CHECKOUT_CODE = "0x60026000";
const SAFE_ABI = parseAbi([
  "event ExecutionSuccess(bytes32 txHash, uint256 payment)",
  "event ExecutionFailure(bytes32 txHash, uint256 payment)",
]);

function deploymentStep(id, nonce, target, predictedAddress, transactionInput) {
  return {
    id,
    purpose: id,
    sender: DEPLOYER,
    nonce: String(nonce),
    target,
    predictedAddress,
    transactionInputHash: keccak256(transactionInput),
    transactionInput,
    submittedHash: null,
    submittedAtBlock: null,
    replacementHistory: [],
    receipt: null,
    observedResult: null,
  };
}

function deploymentManifest(prefix = 0) {
  const marketInput = "0x6001";
  const checkoutInput = "0x6002";
  const authorizationInput = "0x1234";
  const value = {
    schemaVersion: 1,
    kind: "base-universal-pool-art-marketplace",
    status: "prepared",
    chain: {
      chainId: 8453,
      preparedAtBlock: "100",
      preparedAtBlockHash: `0x${"a".repeat(64)}`,
    },
    intent: {
      deployer: DEPLOYER,
      deploymentMode: "production",
      startingNonce: "40",
      marketplace: MARKETPLACE,
      checkout: CHECKOUT,
      sourceCommit: "abc123",
      foundryProfile: "universal_marketplace",
      solcVersion: "0.8.36",
      evmVersion: "cancun",
      optimizerRuns: 200,
      viaIr: false,
    },
    artifacts: {
      marketplace: {
        abiHash: `0x${"1".repeat(64)}`,
        creationBytecodeHash: `0x${"2".repeat(64)}`,
        runtimeTemplateHash: `0x${"3".repeat(64)}`,
        expectedRuntimeCodeHash: keccak256(MARKET_CODE),
      },
      checkout: {
        abiHash: `0x${"2".repeat(64)}`,
        creationBytecodeHash: `0x${"3".repeat(64)}`,
        runtimeTemplateHash: `0x${"4".repeat(64)}`,
        expectedRuntimeCodeHash: keccak256(CHECKOUT_CODE),
      },
    },
    inputs: {
      canonicalDependencies: {
        mirror: "0x4444444444444444444444444444444444444444",
        childRenderer: "0x5555555555555555555555555555555555555555",
      },
      marketplaceConstructor: {
        values: {
          fame: "0x6666666666666666666666666666666666666666",
          creatorMagic: "0x7777777777777777777777777777777777777777",
          communityFee: "1",
          providerFee: "2",
          feeRecipient: SAFE,
          owner: DEPLOYER,
          activeProviderCap: "88",
        },
        encodedHash: keccak256(marketInput),
      },
      checkoutConstructor: {
        values: {
          router: "0x8888888888888888888888888888888888888888",
          marketplace: MARKETPLACE,
          fame: "0x6666666666666666666666666666666666666666",
          usdc: "0x9999999999999999999999999999999999999999",
          weth: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
        encodedHash: keccak256(checkoutInput),
      },
      authorization: {
        target: MARKETPLACE,
        checkout: CHECKOUT,
        calldataHash: keccak256(authorizationInput),
      },
    },
    steps: [
      deploymentStep("deploy-marketplace", 40, null, MARKETPLACE, marketInput),
      deploymentStep("deploy-checkout", 41, null, CHECKOUT, checkoutInput),
      deploymentStep("authorize-checkout", 42, MARKETPLACE, null, authorizationInput),
    ],
    operations: [],
  };
  for (let index = 0; index < prefix; index += 1) {
    const step = value.steps[index];
    const hash = `0x${String(index + 1).repeat(64)}`;
    step.submittedHash = hash;
    step.submittedAtBlock = String(101 + index);
    step.receipt = {
      transactionHash: hash,
      status: "success",
      blockNumber: String(101 + index),
      blockHash: `0x${String(index + 4).repeat(64)}`,
      contractAddress: index === 0 ? MARKETPLACE : index === 1 ? CHECKOUT : null,
      gasUsed: "50000",
    };
    step.observedResult = { verified: true, verifiedAtBlock: String(101 + index), checks: {} };
  }
  value.status = prefix === 3 ? "deployed" : prefix === 0 ? "prepared" : "in-progress";
  return value;
}

function controlledTransaction(step, hash = step.submittedHash) {
  return {
    hash,
    from: DEPLOYER,
    nonce: BigInt(step.nonce),
    to: step.target,
    input: step.transactionInput,
  };
}

function controlledReceipt(step, index, overrides = {}) {
  return {
    transactionHash: step.submittedHash,
    status: "success",
    blockNumber: BigInt(101 + index),
    blockHash: `0x${String(index + 4).repeat(64)}`,
    contractAddress: index === 0 ? MARKETPLACE : index === 1 ? CHECKOUT : null,
    gasUsed: 50_000n,
    logs: [],
    ...overrides,
  };
}

function controlledClient(value, prefix, options = {}) {
  const transactions = new Map();
  const receipts = new Map();
  for (let index = 0; index < prefix; index += 1) {
    const step = value.steps[index];
    const hash = step.submittedHash ?? `0x${String(index + 1).repeat(64)}`;
    transactions.set(hash, controlledTransaction(step, hash));
    receipts.set(hash, controlledReceipt({ ...step, submittedHash: hash }, index));
  }
  const requestedBlocks = [];
  let readErrorThrown = false;
  const client = {
    requestedBlocks,
    async getChainId() {
      return 8453;
    },
    async getBlockNumber() {
      return BigInt(options.head ?? 200);
    },
    async getTransactionReceipt({ hash }) {
      if (options.receiptError) throw options.receiptError;
      if (options.missingKnownHashes?.includes(hash)) {
        throw new TransactionReceiptNotFoundError({ hash });
      }
      const receipt = receipts.get(hash);
      if (!receipt) throw new TransactionReceiptNotFoundError({ hash });
      return receipt;
    },
    async getTransaction({ hash }) {
      return transactions.get(hash);
    },
    async getTransactionCount({ blockNumber }) {
      if (blockNumber !== undefined && options.consumedAt !== undefined) {
        return blockNumber >= BigInt(options.consumedAt) ? 41 : 40;
      }
      return 40 + prefix;
    },
    async getBlock({ blockNumber }) {
      requestedBlocks.push(blockNumber);
      const recovery = options.recoveryTransaction;
      return {
        transactions:
          recovery && blockNumber === BigInt(options.consumedAt) ? [recovery] : [],
      };
    },
    async getBytecode({ address, blockNumber }) {
      const statePrefix = blockNumber === undefined ? prefix : Number(blockNumber - 100n);
      if (address.toLowerCase() === MARKETPLACE.toLowerCase()) {
        return statePrefix >= 1 ? MARKET_CODE : "0x";
      }
      if (address.toLowerCase() === CHECKOUT.toLowerCase()) {
        return statePrefix >= 2 ? CHECKOUT_CODE : "0x";
      }
      if (address.toLowerCase() === SAFE.toLowerCase()) return "0x6003";
      return "0x";
    },
    async readContract({ address, functionName, blockNumber }) {
      if (options.readError && !readErrorThrown) {
        readErrorThrown = true;
        throw options.readError;
      }
      const statePrefix = blockNumber === undefined ? prefix : Number(blockNumber - 100n);
      if (address.toLowerCase() === MARKETPLACE.toLowerCase()) {
        const market = value.inputs.marketplaceConstructor.values;
        return {
          fame: market.fame,
          mirror: value.inputs.canonicalDependencies.mirror,
          creatorMagic: market.creatorMagic,
          communityFee: BigInt(market.communityFee),
          providerFee: BigInt(market.providerFee),
          feeRecipient: market.feeRecipient,
          owner: market.owner,
          activeProviderCap: BigInt(market.activeProviderCap),
          paused: true,
          authorizedCheckout: statePrefix >= 3 ? CHECKOUT : ZERO,
        }[functionName];
      }
      if (address.toLowerCase() === CHECKOUT.toLowerCase()) {
        const checkout = value.inputs.checkoutConstructor.values;
        return {
          router: checkout.router,
          market: checkout.marketplace,
          fame: checkout.fame,
          usdc: checkout.usdc,
          weth: checkout.weth,
        }[functionName];
      }
      if (functionName === "getSkipNFT") return true;
      throw new Error(`unexpected controlled read: ${functionName}`);
    },
  };
  if (options.recoveryTransaction) {
    transactions.set(options.recoveryTransaction.hash, options.recoveryTransaction);
    receipts.set(
      options.recoveryTransaction.hash,
      controlledReceipt(
        { ...value.steps[0], submittedHash: options.recoveryTransaction.hash },
        0,
        options.recoveryReceipt,
      ),
    );
  }
  return client;
}

async function manifestPath(value) {
  const directory = await mkdtemp(join(tmpdir(), "fame-deployment-cli-"));
  const path = join(directory, "manifest.json");
  await writeManifestAtomic(path, value);
  return path;
}

test("RPC mode validation separates production from loopback rehearsals", () => {
  for (const url of [
    "http://127.0.0.1:8545",
    "http://2130706433:8545",
    "http://0x7f000001:8545",
    "http://[::1]:8545",
    "http://[::ffff:127.0.0.1]:8545",
    "http://[::ffff:127.2.3.4]:8545",
  ]) {
    assert.doesNotThrow(() => assertRpcMode("fork-rehearsal", url));
    assert.throws(
      () => assertRpcMode("production", url),
      /production mode rejects loopback RPC URLs/,
    );
  }
  assert.doesNotThrow(() => assertRpcMode("production", "https://base.example.invalid/rpc"));
  assert.throws(
    () => assertRpcMode("fork-rehearsal", "https://base.example.invalid/rpc"),
    /fork-rehearsal mode requires a loopback RPC URL/,
  );
});

test("deployment errors redact viem URLs, credentials, request bodies, and nested messages", () => {
  const sentinel = "SENTINEL_RPC_CREDENTIAL";
  const error = new HttpRequestError({
    body: { method: "eth_sendRawTransaction", params: [`0x${sentinel}`] },
    details: `nested transport https://user:${sentinel}@rpc.example.invalid/path?api_key=${sentinel}`,
    headers: { authorization: `Bearer ${sentinel}` },
    status: 503,
    url: `https://user:${sentinel}@rpc.example.invalid/path?api_key=${sentinel}`,
  });
  error.cause = new Error(`nested bearer Bearer ${sentinel}`);

  const details = deploymentErrorDetails(error);
  const serialized = JSON.stringify(details);
  assert.equal(details.name, "HttpRequestError");
  assert.equal(serialized.includes(sentinel), false);
  assert.equal(serialized.includes("eth_sendRawTransaction"), false);
  assert.match(details.message, /redacted/);

  const multiline = deploymentErrorDetails(
    new Error(
      `transport failed\nRequest body:\n{\n  "credential": "${sentinel}"\n}\n\nDetails: private_key: "${sentinel}"`,
    ),
  );
  assert.equal(JSON.stringify(multiline).includes(sentinel), false);

  const processResult = spawnSync(
    process.execPath,
    [
      fileURLToPath(new URL("./base-universal-pool-art-marketplace.mjs", import.meta.url)),
      `https://user:${sentinel}@rpc.example.invalid/path?api_key=${sentinel}`,
    ],
    { encoding: "utf8" },
  );
  assert.equal(processResult.status, 1);
  assert.equal(processResult.stderr.includes(sentinel), false);
  assert.match(processResult.stderr, /redacted-url/);
});

test("optional-manifest command grammar preserves required operation IDs", () => {
  assert.deepEqual(parseCommandArguments("replace", ["deploy-marketplace"]), {
    manifestPath: "script/manifests/base-universal-pool-art-marketplace-deployment.json",
    arguments: ["deploy-marketplace"],
  });
  assert.deepEqual(parseCommandArguments("replace", ["/tmp/manifest.json", "deploy-marketplace"]), {
    manifestPath: "/tmp/manifest.json",
    arguments: ["deploy-marketplace"],
  });
  assert.deepEqual(parseCommandArguments("advance-operation", ["deployer-activation-1"]), {
    manifestPath: "script/manifests/base-universal-pool-art-marketplace-deployment.json",
    arguments: ["deployer-activation-1"],
  });
  assert.deepEqual(
    parseCommandArguments("advance-operation", ["/tmp/manifest.json", "deployer-activation-1"]),
    {
      manifestPath: "/tmp/manifest.json",
      arguments: ["deployer-activation-1"],
    },
  );
  assert.throws(() => parseCommandArguments("replace", []), /requires a deployment step ID/);
  assert.throws(
    () => parseCommandArguments("advance-operation", []),
    /requires a lifecycle operation ID/,
  );
});

test("receipt waiting does not finish before replacement persistence", async () => {
  const transactionHash = `0x${"6".repeat(64)}`;
  const replacementHash = `0x${"7".repeat(64)}`;
  const receipt = { status: "success", transactionHash: replacementHash };
  let releasePersistence;
  const persistenceCanFinish = new Promise((resolve) => {
    releasePersistence = resolve;
  });
  let persistenceStarted = false;
  let persistenceFinished = false;
  let waitFinished = false;

  const wait = waitForReceiptWithPersistedReplacements(
    {
      async waitForTransactionReceipt({ hash, onReplaced }) {
        assert.equal(hash, transactionHash);
        onReplaced({
          reason: "repriced",
          transaction: { hash: replacementHash },
        });
        return receipt;
      },
    },
    transactionHash,
    async () => {
      persistenceStarted = true;
      await persistenceCanFinish;
      persistenceFinished = true;
    },
  ).then((result) => {
    waitFinished = true;
    return result;
  });

  try {
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(persistenceStarted, true);
    assert.equal(persistenceFinished, false);
    assert.equal(waitFinished, false, "receipt wait resolved before replacement persistence");
  } finally {
    releasePersistence();
  }

  assert.equal(await wait, receipt);
  assert.equal(persistenceFinished, true);
});

test("replacement persistence stays serialized in callback order", async () => {
  const transactionHash = `0x${"6".repeat(64)}`;
  const firstReplacementHash = `0x${"7".repeat(64)}`;
  const secondReplacementHash = `0x${"8".repeat(64)}`;
  let releaseFirstPersistence;
  const firstPersistenceCanFinish = new Promise((resolve) => {
    releaseFirstPersistence = resolve;
  });
  const persistenceOrder = [];

  const wait = waitForReceiptWithPersistedReplacements(
    {
      async waitForTransactionReceipt({ onReplaced }) {
        onReplaced({ transaction: { hash: firstReplacementHash } });
        onReplaced({ transaction: { hash: secondReplacementHash } });
        return { status: "success", transactionHash: secondReplacementHash };
      },
    },
    transactionHash,
    async ({ transaction }) => {
      persistenceOrder.push(`start:${transaction.hash}`);
      if (transaction.hash === firstReplacementHash) await firstPersistenceCanFinish;
      persistenceOrder.push(`finish:${transaction.hash}`);
    },
  );

  try {
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(persistenceOrder, [`start:${firstReplacementHash}`]);
  } finally {
    releaseFirstPersistence();
  }

  await wait;
  assert.deepEqual(persistenceOrder, [
    `start:${firstReplacementHash}`,
    `finish:${firstReplacementHash}`,
    `start:${secondReplacementHash}`,
    `finish:${secondReplacementHash}`,
  ]);
});

test("production CLI network commands all reject a loopback RPC before reads or sends", async () => {
  const value = deploymentManifest();
  const path = await manifestPath(value);
  const previous = {
    FOUNDRY_PROFILE: process.env.FOUNDRY_PROFILE,
    MARKETPLACE_DEPLOYMENT_MODE: process.env.MARKETPLACE_DEPLOYMENT_MODE,
    RPC_URL: process.env.RPC_URL,
  };
  process.env.FOUNDRY_PROFILE = "universal_marketplace";
  process.env.MARKETPLACE_DEPLOYMENT_MODE = "production";
  process.env.RPC_URL = "http://2130706433:8545";
  try {
    for (const argv of [
      ["prepare", path],
      ["reconcile", path],
      ["advance", path],
      ["replace", path, "deploy-marketplace"],
      ["prepare-operation", path, "deployer-activation"],
      ["advance-operation", path, "deployer-activation-1"],
      ["replace-operation", path, "deployer-activation-1"],
      ["reconcile-operation", path, "deployer-activation-1"],
    ]) {
      await assert.rejects(() => main(argv), /production mode rejects loopback RPC URLs/);
    }
  } finally {
    for (const [key, prior] of Object.entries(previous)) {
      if (prior === undefined) delete process.env[key];
      else process.env[key] = prior;
    }
  }
});

test("executable reconciliation confirms each canonical deployment prefix", async () => {
  for (let prefix = 0; prefix <= 3; prefix += 1) {
    const value = deploymentManifest(prefix);
    const path = await manifestPath(value);
    const result = await reconcile(path, controlledClient(value, prefix));
    if (prefix === 3) {
      assert.deepEqual(result.classification, {
        kind: "complete",
        confirmedPrefix: 3,
        nextStepId: null,
      });
    } else {
      assert.deepEqual(result.classification, {
        kind: "ready",
        confirmedPrefix: prefix,
        nextStepId: value.steps[prefix].id,
      });
    }
  }
});

test("old nonce-spend recovery uses a bounded historical nonce search", async () => {
  const value = deploymentManifest();
  const canonicalHash = `0x${"9".repeat(64)}`;
  const recoveryTransaction = controlledTransaction(value.steps[0], canonicalHash);
  const client = controlledClient(value, 1, {
    consumedAt: 12_345,
    head: 50_000,
    recoveryTransaction,
  });
  const path = await manifestPath(value);
  const result = await reconcile(path, client);

  assert.equal(result.classification.confirmedPrefix, 1);
  assert.equal(result.manifest.steps[0].submittedHash, canonicalHash);
  assert.deepEqual(client.requestedBlocks, [12_345n]);
});

test("nonce recovery switches from bounded linear scanning at the 10,000-block boundary", async () => {
  for (const [head, expectedBlockReads] of [
    [10_100, 10_001],
    [10_101, 1],
  ]) {
    const value = deploymentManifest();
    const canonicalHash = `0x${"9".repeat(64)}`;
    const recoveryTransaction = controlledTransaction(value.steps[0], canonicalHash);
    const client = controlledClient(value, 1, {
      consumedAt: head,
      head,
      recoveryTransaction,
    });
    const canonical = await findCanonicalTransaction(client, value, value.steps[0]);
    assert.equal(canonical.transaction.hash, canonicalHash);
    assert.equal(client.requestedBlocks.length, expectedBlockReads);
  }
});

test("recovery consults persisted last-error hashes before scanning blocks", async () => {
  const value = deploymentManifest();
  const canonicalHash = `0x${"9".repeat(64)}`;
  value.lastError = {
    stepId: "deploy-marketplace",
    transactionHash: canonicalHash,
    observedAt: new Date(0).toISOString(),
    name: "Error",
    code: null,
    message: "send result was not persisted",
  };
  const recoveryTransaction = controlledTransaction(value.steps[0], canonicalHash);
  const client = controlledClient(value, 1, {
    consumedAt: 12_345,
    head: 50_000,
    recoveryTransaction,
  });

  const canonical = await findCanonicalTransaction(client, value, value.steps[0]);
  assert.equal(canonical.transaction.hash, canonicalHash);
  assert.deepEqual(client.requestedBlocks, []);

  const withOperation = prepareLifecycleOperation(deploymentManifest(3), {
    id: "deployer-activation-1",
    kind: "deployer-activation",
    authority: "deployer",
    sender: DEPLOYER,
    nonce: "43",
    target: MARKETPLACE,
    transactionInput: "0x03",
    transactionInputHash: keccak256("0x03"),
    expectedResult: { owner: DEPLOYER, paused: false, eventAccount: DEPLOYER },
    preparedAtBlock: "200",
  });
  withOperation.operations[0].lastError = {
    transactionHash: canonicalHash,
    observedAt: new Date(0).toISOString(),
    name: "Error",
    code: null,
    message: "send result was not persisted",
  };
  const operationTransaction = {
    hash: canonicalHash,
    from: DEPLOYER,
    nonce: 43n,
    to: MARKETPLACE,
    input: "0x03",
  };
  const operationCanonical = await findCanonicalTransaction(
    {
      async getTransactionReceipt() {
        return {
          transactionHash: canonicalHash,
          status: "success",
          blockNumber: 201n,
          blockHash: `0x${"8".repeat(64)}`,
          contractAddress: null,
          gasUsed: 50_000n,
          logs: [],
        };
      },
      async getTransaction() {
        return operationTransaction;
      },
    },
    withOperation,
    withOperation.operations[0],
  );
  assert.equal(operationCanonical.transaction.hash, canonicalHash);
});

test("receipt/result mismatches and reverted replacements remain no-go", async () => {
  const sentinel = "SENTINEL_RPC_CREDENTIAL";
  const rpcError = new HttpRequestError({
    body: { method: "eth_call", params: [`0x${sentinel}`] },
    details: `transport failed at https://rpc.example.invalid/path?key=${sentinel}`,
    url: `https://rpc.example.invalid/path?key=${sentinel}`,
  });
  const mismatched = deploymentManifest(1);
  const mismatchPath = await manifestPath(mismatched);
  await assert.rejects(
    () => reconcile(mismatchPath, controlledClient(mismatched, 1, { readError: rpcError })),
    /canonical result did not match/,
  );
  const persisted = await readFile(mismatchPath, "utf8");
  assert.equal(persisted.includes(sentinel), false);
  assert.equal(persisted.includes("eth_call"), false);

  const changedPayload = deploymentManifest();
  const changedOldHash = `0x${"6".repeat(64)}`;
  const changedReplacementHash = `0x${"7".repeat(64)}`;
  changedPayload.steps[0].submittedHash = changedOldHash;
  changedPayload.steps[0].submittedAtBlock = "100";
  changedPayload.status = "in-progress";
  const changedTransaction = {
    ...controlledTransaction(changedPayload.steps[0], changedReplacementHash),
    input: "0xffff",
  };
  const changedClient = controlledClient(changedPayload, 1, {
    consumedAt: 101,
    head: 101,
    missingKnownHashes: [changedOldHash],
    recoveryTransaction: changedTransaction,
  });
  const changedPath = await manifestPath(changedPayload);
  await assert.rejects(() => reconcile(changedPath, changedClient), /transaction input mismatch/);

  const replaced = deploymentManifest();
  const oldHash = `0x${"6".repeat(64)}`;
  const replacementHash = `0x${"7".repeat(64)}`;
  replaced.steps[0].submittedHash = oldHash;
  replaced.steps[0].submittedAtBlock = "100";
  replaced.status = "in-progress";
  const replacementTransaction = controlledTransaction(replaced.steps[0], replacementHash);
  const replacementClient = controlledClient(replaced, 1, {
    consumedAt: 101,
    head: 101,
    missingKnownHashes: [oldHash],
    recoveryTransaction: replacementTransaction,
    recoveryReceipt: { status: "reverted", transactionHash: replacementHash },
  });
  const replacementPath = await manifestPath(replaced);
  await assert.rejects(() => reconcile(replacementPath, replacementClient), /reverted/);
  const failed = JSON.parse(await readFile(replacementPath, "utf8"));
  assert.equal(failed.status, "needs-reconciliation");
  assert.equal(failed.steps[0].receipt, null);
});

function safeReceipt(eventName, safeTransactionHash, outerHash, includeExecutionEvent = true) {
  const safeLog = includeExecutionEvent
    ? {
        address: SAFE,
        topics: encodeEventTopics({ abi: SAFE_ABI, eventName }),
        data: encodeAbiParameters(
          [{ type: "bytes32" }, { type: "uint256" }],
          [safeTransactionHash, 0n],
        ),
      }
    : null;
  return {
    transactionHash: outerHash,
    status: "success",
    blockNumber: 201n,
    blockHash: `0x${"8".repeat(64)}`,
    contractAddress: null,
    gasUsed: 75_000n,
    logs: [
      ...(safeLog ? [safeLog] : []),
      {
        address: MARKETPLACE,
        topics: [
          keccak256(stringToHex("MarketUnpaused(address)")),
          `0x${SAFE.slice(2).padStart(64, "0")}`,
        ],
        data: "0x",
      },
    ],
  };
}

function safeOperationClient(value, eventName, emittedSafeHash, outerHash, options = {}) {
  const receipt = safeReceipt(
    eventName,
    emittedSafeHash,
    outerHash,
    options.includeExecutionEvent !== false,
  );
  return {
    async getTransactionReceipt() {
      return receipt;
    },
    async getTransaction() {
      return {
        hash: outerHash,
        from: DEPLOYER,
        nonce: 88n,
        to: options.target ?? SAFE,
        input: "0x1234",
      };
    },
    async getBytecode({ address }) {
      return address.toLowerCase() === MARKETPLACE.toLowerCase() ? MARKET_CODE : "0x6003";
    },
    async readContract({ functionName }) {
      return {
        owner: SAFE,
        paused: false,
        authorizedCheckout: CHECKOUT,
      }[functionName];
    },
  };
}

async function safeOperationManifest() {
  const value = deploymentManifest(3);
  const operation = prepareLifecycleOperation(value, {
    id: "safe-activation-1",
    kind: "safe-activation",
    authority: "society-safe",
    sender: SAFE,
    nonce: null,
    target: MARKETPLACE,
    transactionInput: "0x03",
    transactionInputHash: keccak256("0x03"),
    expectedResult: { owner: SAFE, paused: false, eventAccount: SAFE },
    preparedAtBlock: "200",
  });
  return { value: operation, path: await manifestPath(operation) };
}

test("Safe reconciliation binds the outer Safe target and emitted reviewed hash", async () => {
  const outerHash = `0x${"7".repeat(64)}`;
  const reviewedSafeHash = `0x${"a".repeat(64)}`;
  const successful = await safeOperationManifest();
  await reconcileOperation(
    successful.path,
    "safe-activation-1",
    outerHash,
    reviewedSafeHash,
    safeOperationClient(successful.value, "ExecutionSuccess", reviewedSafeHash, outerHash),
  );
  const persisted = JSON.parse(await readFile(successful.path, "utf8"));
  assert.equal(persisted.operations[0].executionTransactionHash, outerHash);
  assert.equal(persisted.operations[0].safeTransactionHash, reviewedSafeHash);

  for (const fixture of [
    {
      eventName: "ExecutionSuccess",
      emittedHash: reviewedSafeHash,
      options: { includeExecutionEvent: false },
      message: /missing ExecutionSuccess or ExecutionFailure/,
    },
    {
      eventName: "ExecutionFailure",
      emittedHash: reviewedSafeHash,
      options: {},
      message: /ExecutionFailure/,
    },
    {
      eventName: "ExecutionSuccess",
      emittedHash: `0x${"b".repeat(64)}`,
      options: {},
      message: /reviewed Safe transaction hash mismatch/,
    },
    {
      eventName: "ExecutionSuccess",
      emittedHash: reviewedSafeHash,
      options: { target: MARKETPLACE },
      message: /outer execution target mismatch/,
    },
  ]) {
    const failed = await safeOperationManifest();
    await assert.rejects(
      () =>
        reconcileOperation(
          failed.path,
          "safe-activation-1",
          outerHash,
          reviewedSafeHash,
          safeOperationClient(
            failed.value,
            fixture.eventName,
            fixture.emittedHash,
            outerHash,
            fixture.options,
          ),
        ),
      fixture.message,
    );
  }
});
